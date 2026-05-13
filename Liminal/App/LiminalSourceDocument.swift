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
    let cstInspector: CSTInspector
    private let writesThroughToFile: Bool

    /// CST-aware undo history. Captures `(tree, source, cursor, marks)`
    /// snapshots at every vim transaction boundary; on undo, the
    /// snapshot tree is reinstalled into the parser session verbatim
    /// so anchor identity is preserved (no reparse). One per document.
    ///
    /// `@MainActor`-isolated lazy so construction is deferred to first
    /// access on the main thread. `LiminalSourceDocument` itself is
    /// built off the MainActor by SwiftUI's DocumentGroup; the
    /// canonical first-access site is the Coordinator's `makeNSView`
    /// (always on main), which triggers init via
    /// `seedInitialUndoSnapshotIfNeeded()`. All call sites are
    /// already MainActor-isolated.
    @MainActor
    private(set) lazy var undoHistory: CSTUndoHistory = CSTUndoHistory()

    /// The Cocoa undo manager wired into the responder chain so
    /// system menu actions (`undo:` / `redo:` from the Edit menu and
    /// ⌘Z / ⌘⇧Z bindings) walk into our snapshot history. The
    /// NSTextView subclass overrides its own `undoManager` getter to
    /// return this one; `allowsUndo = false` on the text view so
    /// NSTextView doesn't try to register byte-level edits with it.
    ///
    /// `@MainActor` because `UndoManager` itself is `@MainActor` in
    /// recent SDKs, and Cocoa always invokes `undo:` / `redo:`
    /// actions on the main thread anyway.
    @MainActor
    private(set) lazy var undoManager: CSTUndoManager = CSTUndoManager()

    @Published private(set) var diagnosticsCount: Int = 0
    @Published private(set) var reuseSummary: ReuseSummary = .empty

    /// File URL for the document on disk, if any. Populated from the
    /// view layer (`ReferenceFileDocumentConfiguration.fileURL`) — the
    /// document layer itself doesn't natively know its URL in SwiftUI's
    /// document architecture. Nil for untitled new documents until first
    /// save. Updates on Save As.
    @Published private(set) var fileURL: URL?

    /// Push the current file URL down from the view layer. Idempotent
    /// — no-op when unchanged. On a transition (nil → URL, URL → URL',
    /// URL → nil) updates the `VaultRegistry`: drops us from the old
    /// vault entry and indexes the current document into the new one.
    @MainActor
    func setFileURL(_ url: URL?) {
        guard fileURL != url else { return }
        let oldURL = fileURL
        fileURL = url
        if let oldURL {
            VaultRegistry.shared.entry(for: oldURL).remove(oldURL)
        }
        indexInVault()
    }

    /// Re-index the open document into its vault entry. No-op when
    /// the document is untitled (no URL) or has no CST yet (no parse
    /// has completed). Uses `currentRootSyntax` so the path works after
    /// either a textual edit (parse result fresh) or a structural edit
    /// (parse result nil but `currentTree` advanced).
    @MainActor
    private func indexInVault() {
        guard let url = fileURL,
              let root = currentRootSyntax
        else { return }
        let entry = VaultRegistry.shared.entry(for: url)
        entry.indexCurrentDocument(
            url,
            rootSyntax: root,
            content: session.source
        )
        // Kick off the one-shot vault scan so Cmd-clicks to
        // not-yet-open notes can resolve. Idempotent across calls.
        entry.beginColdStartScanIfNeeded()
    }

    init() {
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        self.cstInspector = CSTInspector()
        self.writesThroughToFile = false
        // undoHistory / undoManager are lazy — first access happens
        // on the MainActor in the Coordinator's makeNSView. Don't
        // touch them here.
        syncFromSession()
    }

    @MainActor
    convenience init(standaloneFileURL url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(standaloneSource: source, fileURL: url)
    }

    private init(standaloneSource source: String, fileURL: URL) throws {
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        self.cstInspector = CSTInspector()
        self.writesThroughToFile = true
        try session.replaceSource(source)
        syncFromSession()
        // This init is reached from the @MainActor convenience init
        // below, so this assumeIsolated is correct. setFileURL needs
        // to fire here for vault registration; the undo snapshot seed
        // is handled by Coordinator.makeNSView.
        MainActor.assumeIsolated {
            setFileURL(fileURL)
        }
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        self.cstInspector = CSTInspector()
        self.writesThroughToFile = false
        try session.replaceSource(source)
        syncFromSession()
        // Seeding deferred to Coordinator.makeNSView.
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
        MainActor.assumeIsolated {
            if let oldRoot, let newRoot = currentRootSyntax {
                vimController.reanchorMarks(
                    oldRoot: oldRoot,
                    edits: edits,
                    newRoot: newRoot
                )
                // Inspector snapshot is computed against the new root;
                // the Coordinator will pick it up on the next selection
                // notification, but text edits also need to trigger an
                // immediate refresh so the snapshot tracks structural
                // changes even when the cursor doesn't move.
                cstInspector.refresh(
                    cursorByteOffset: cstInspector.snapshot.map { Int($0.cursor.byteOffset.rawValue) },
                    root: newRoot,
                    source: session.source
                )
            }
            indexInVault()
            writeThroughIfNeeded()
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
            cstInspector.refresh(
                cursorByteOffset: cstInspector.snapshot.map { Int($0.cursor.byteOffset.rawValue) },
                root: newRoot,
                source: session.source
            )
        }
        indexInVault()
        writeThroughIfNeeded()
        return true
    }

    @MainActor
    @discardableResult
    func writeToBackingFileIfPossible() -> Bool {
        guard writesThroughToFile, let fileURL else { return false }
        do {
            try Data(session.source.utf8).write(to: fileURL, options: .atomic)
            return true
        } catch {
            NSLog("LiminalSourceDocument: write-through failed for \(fileURL.path): \(error)")
            return false
        }
    }

    @MainActor
    private func writeThroughIfNeeded() {
        writeToBackingFileIfPossible()
    }

    // MARK: - Undo / redo

    /// Idempotent wrapper called from the Coordinator on attach. Seeds
    /// only when the history is empty so this is safe to call from
    /// every `makeNSView` (including re-attaches after view rebuilds).
    @MainActor
    func seedInitialUndoSnapshotIfNeeded() {
        guard undoHistory.depth == 0 else { return }
        seedInitialUndoSnapshot()
    }

    /// Seed the undo history's initial state: snapshot[0] = "as
    /// loaded". Required before any forward edits so undo can rewind
    /// back to the initial state. Called from each init path AFTER
    /// the first parse has populated `session.currentTree`.
    @MainActor
    func seedInitialUndoSnapshot() {
        guard let tree = session.currentTree else { return }
        let snap = CSTUndoSnapshot(
            tree: tree,
            source: session.source,
            cursor: 0,
            marks: vimController.marks
        )
        undoHistory.reset(initial: snap)
        // Wire the pre-undo hook: ⌘Z while in insert mode commits
        // the active session first so the undo lands at the pre-insert
        // state instead of needing two ⌘Zs to clear the typed text.
        undoManager.preUndoHook = { [weak self] in
            guard let self else { return }
            if self.vimController.mode == .insert,
               self.undoHistory.insertSessionActive {
                let cursor = self.snapshotInstaller?.currentCursorForUndo() ?? 0
                self.commitInsertSession(at: cursor)
                self.vimController.forceNormalMode()
            }
        }
    }

    /// Snapshot the current document state at a vim transaction
    /// boundary. Called by the Coordinator after every `applyOperator`,
    /// paste, visual-mode delete, and on insert-session commit (Esc).
    /// No-op detection inside `CSTUndoHistory.snapshot(_:)` drops
    /// snapshots that don't actually change the source — and we skip
    /// registering an NSUndoManager entry in that case too.
    @MainActor
    func captureSnapshot(at cursor: Int) {
        guard let tree = session.currentTree else { return }
        let snap = CSTUndoSnapshot(
            tree: tree,
            source: session.source,
            cursor: cursor,
            marks: vimController.marks
        )
        let appended = undoHistory.snapshot(snap)
        if appended { registerUndoStep() }
    }

    /// Open an insert-session bracket. Captures the entry-point
    /// snapshot so `commitInsertSession` can decide whether to record
    /// a transaction (text changed) or drop the session as a no-op
    /// (entered insert and pressed Esc without typing).
    @MainActor
    func beginInsertSession(at cursor: Int) {
        guard let tree = session.currentTree else { return }
        let entry = CSTUndoSnapshot(
            tree: tree,
            source: session.source,
            cursor: cursor,
            marks: vimController.marks
        )
        undoHistory.beginInsertSession(at: entry)
    }

    /// Close an insert session, recording one transaction if the
    /// source changed during the session.
    @MainActor
    func commitInsertSession(at cursor: Int) {
        guard let tree = session.currentTree else { return }
        let commit = CSTUndoSnapshot(
            tree: tree,
            source: session.source,
            cursor: cursor,
            marks: vimController.marks
        )
        let appended = undoHistory.commitInsertSession(commit: commit)
        if appended { registerUndoStep() }
    }

    /// Restore a snapshot wholesale: install its tree (no reparse,
    /// preserving anchor identity), update `self.source`, restore
    /// marks. The Coordinator is responsible for forcing the text
    /// view to match (`installSnapshotAndUpdateView` below wraps this
    /// with the view-side effects).
    @MainActor
    @discardableResult
    func installSnapshot(_ snap: CSTUndoSnapshot) -> CSTUndoSnapshot {
        session.installSnapshot(tree: snap.tree, source: snap.source)
        vimController.restoreMarks(snap.marks)
        return snap
    }

    /// The Coordinator hooks itself here on attach so the document can
    /// drive the text view from the undo path without a hard
    /// dependency on the SwiftUI Coordinator type.
    weak var snapshotInstaller: CSTSnapshotInstaller?

    /// Install a snapshot and push the text + cursor into the view.
    /// Used by the NSUndoManager closures wired in `registerUndoStep`.
    @MainActor
    func installSnapshotAndUpdateView(_ snap: CSTUndoSnapshot) {
        installSnapshot(snap)
        snapshotInstaller?.applyInstalledSnapshot(snap)
    }

    /// Register one paired undo/redo step on the Cocoa undo manager.
    /// The closure walks `undoHistory` by one (undo or redo, depending
    /// on whether NSUndoManager is currently performing an undo or a
    /// redo) and re-registers itself so the chain stays alive.
    @MainActor
    private func registerUndoStep() {
        undoManager.registerUndo(withTarget: self) { (doc: LiminalSourceDocument) in
            // NSUndoManager runs this closure during `undo()`. Walk
            // history one step back and apply.
            if let prior = doc.undoHistory.undo() {
                doc.installSnapshotAndUpdateView(prior)
            }
            // We're inside an undo group, so this registers the
            // matching REDO. Inside the redo it'll register the next
            // UNDO, and so on.
            doc.registerRedoStep()
        }
    }

    @MainActor
    private func registerRedoStep() {
        undoManager.registerUndo(withTarget: self) { (doc: LiminalSourceDocument) in
            if let next = doc.undoHistory.redo() {
                doc.installSnapshotAndUpdateView(next)
            }
            doc.registerUndoStep()
        }
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
