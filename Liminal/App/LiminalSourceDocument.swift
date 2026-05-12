import CambiumBuilder
import CambiumCore
import CambiumIncremental
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI document-group document. Owns a `LiminalEditorSession` and
/// re-publishes per-parse derived state (diagnostics count, reuse summary)
/// so SwiftUI views can observe it. The session itself stays a plain
/// orchestrator class; Combine is kept at the app boundary.
///
/// Not isolated to MainActor — SwiftUI's DocumentGroup constructs documents
/// from a non-isolated Sendable closure, and `ReferenceFileDocument`
/// conformance brings its own thread-safety expectations via @Published.
final class LiminalSourceDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.liminalMarkup, .plainText] }
    static var writableContentTypes: [UTType] { [.liminalMarkup] }

    let session: LiminalEditorSession
    let vimController: VimController

    @Published private(set) var diagnosticsCount: Int = 0
    @Published private(set) var reuseSummary: ReuseSummary = .empty

    init() {
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        syncFromSession()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        try session.replaceSource(source)
        syncFromSession()
    }

    func snapshot(contentType: UTType) throws -> String {
        session.source
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// Forward a textual edit to the session. Called by `LiminalTextView`'s
    /// `NSTextStorageDelegate` coordinator on user-initiated edits.
    func applyTextEdits(_ edits: [TextEdit]) {
        let oldRoot = session.parseResult?.rootSyntax
        do {
            try session.applyTextEdits(edits)
        } catch {
            NSLog("LiminalSourceDocument: applyTextEdits failed: \(error)")
            return
        }
        syncFromSession()
        if let oldRoot, let newRoot = currentRootSyntax {
            MainActor.assumeIsolated {
                vimController.reanchorMarks(
                    oldRoot: oldRoot,
                    edits: edits,
                    newRoot: newRoot
                )
            }
        }
    }

    /// `parseResult` is nil after a structural edit (by Phase 5a's design —
    /// the parser hasn't re-run, so diagnostics are stale). Consumers that
    /// just want "the current CST root" should go through this accessor;
    /// it transparently bridges both paths.
    var currentRootSyntax: RootSyntax? {
        if let parsed = session.parseResult {
            return parsed.rootSyntax
        }
        if let tree = session.currentTree {
            return RootSyntax(unchecked: tree.rootHandle())
        }
        return nil
    }

    /// Toggle the task-marker token inside `listItemHandle`, preserving
    /// every other token and subtree by identity (token children via the
    /// interner, child nodes via `reuseSubtree`). Commits via the
    /// structural-replace primitive — no reparse, no source-to-string
    /// round-trip, no full highlight pass.
    @MainActor
    func structuralToggleTask(listItemHandle: SyntaxNodeHandle<LiminalLanguage>) -> Bool {
        let listItem = ListItemSyntax(unchecked: listItemHandle)
        guard let state = listItem.taskState else { return false }

        let newMarkerText: String
        switch state {
        case .unchecked: newMarkerText = "[x]"
        case .checked:   newMarkerText = "[ ]"
        }

        let oldRoot = currentRootSyntax

        do {
            try listItemHandle.withCursor { (cursor: borrowing SyntaxNodeCursor<LiminalLanguage>) in
                var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
                builder.startNode(.listItem)
                try cursor.forEachChildOrToken { element in
                    switch element {
                    case .token(let token):
                        let kind = LiminalLanguage.kind(for: token.rawKind)
                        if kind == .taskMarker {
                            // The one truly new allocation: the flipped marker.
                            try builder.token(.taskMarker, text: newMarkerText)
                        } else if LiminalLanguage.staticText(for: kind) != nil {
                            try builder.staticToken(kind)
                        } else {
                            // Dynamic token re-emitted with identical content;
                            // the interner deduplicates so green identity
                            // matches the original after the replace lands.
                            try builder.token(kind, text: token.makeString())
                        }
                    case .node(let childCursor):
                        _ = try builder.reuseSubtree(childCursor)
                    }
                }
                try builder.finishNode()
                let buildResult = try builder.finish()
                _ = try session.replaceSubtree(listItemHandle, with: buildResult)
            }
        } catch {
            NSLog("LiminalSourceDocument: structuralToggleTask failed: \(error)")
            return false
        }

        syncFromSession()
        // Toggle is byte-length-preserving ([ ] ↔ [x] both 3 bytes), so
        // no textual deltas to feed the registry — pass [].
        if let oldRoot, let newRoot = currentRootSyntax {
            vimController.reanchorMarks(
                oldRoot: oldRoot,
                edits: [],
                newRoot: newRoot
            )
        }
        return true
    }

    private func syncFromSession() {
        // After a structural edit, `parseResult` is nil and we don't have a
        // fresh diagnostics count. Preserve the last-known value rather than
        // clobbering to 0.
        if let parsed = session.parseResult {
            diagnosticsCount = parsed.diagnostics.count
        }
        reuseSummary = session.lastReuseSummary
    }
}
