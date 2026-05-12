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
        do {
            try session.applyTextEdits(edits)
        } catch {
            NSLog("LiminalSourceDocument: applyTextEdits failed: \(error)")
        }
        syncFromSession()
    }

    /// Toggle the task checkbox at the given byte offset, if the cursor
    /// is inside a list item with a task marker. Called by the vim
    /// `<Space>t` binding via the coordinator.
    @MainActor
    func toggleTaskAt(byteOffset: Int) {
        guard let parsed = session.parseResult,
              let location = StructureCursor.taskListItem(at: byteOffset, in: parsed.rootSyntax)
        else { return }

        // Swap the marker text: "[ ]" → "[x]" and "[x]"/"[X]" → "[ ]".
        let newMarkerText: String
        switch location.state {
        case .unchecked: newMarkerText = "[x]"
        case .checked:   newMarkerText = "[ ]"
        }

        // Build a minimal replacement: a fresh `.taskMarker` token. The
        // structural-replace path expects a node-shaped replacement, so
        // we wrap the token in a `.listItem` node containing only the
        // marker — but that won't structurally match. Simpler and
        // correct: we structurally replace the marker token's parent
        // list-item with a list-item containing the new marker plus the
        // original item's other children.
        //
        // Even simpler: build a snapshot whose root contains just a
        // replacement listItem subtree by re-rendering. For slice 3 we
        // take the simplest correct route — a textual edit on the
        // marker range. The marker is always exactly 3 bytes ("[ ]" /
        // "[x]" / "[X]"); we replace those bytes via `applyTextEdits`.
        let edit = TextEdit(
            range: location.markerByteRange,
            replacement: newMarkerText
        )
        applyTextEdits([edit])
    }

    private func syncFromSession() {
        diagnosticsCount = session.parseResult?.diagnostics.count ?? 0
        reuseSummary = session.lastReuseSummary
    }
}
