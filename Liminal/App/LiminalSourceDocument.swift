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

    /// CST-aware undo history. Captures tree/cursor/mark snapshots
    /// and text patches at vim transaction boundaries; on undo, the
    /// target tree is reinstalled into the parser session verbatim
    /// and the live source is patched through the recorded ranges.
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

    @Published private(set) var diagnosticsCount: Int = 0
    @Published private(set) var reuseSummary: ReuseSummary = .empty

    /// Monotonic counter bumped after every tree-mutating action
    /// (textual edits, structural toggles, structural replacements).
    /// Unlike `vimController.$marks` — which silently skips its
    /// publish step when the byte-mark registry is empty — this fires
    /// unconditionally, so view-layer observers that need to refresh
    /// per-tree state (forest mark outlines, future invariants) can
    /// rely on it.
    @Published private(set) var treeVersion: Int = 0

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
        // Mark this URL as backed by a live editor so the watcher's
        // refresh path won't reparse it from disk out from under us.
        entry.registerOpenDocument(url)
        entry.indexCurrentDocument(
            url,
            rootSyntax: root,
            content: session.source
        )
        // Kick off the one-shot vault scan so Cmd-clicks to
        // not-yet-open notes can resolve. Idempotent across calls.
        entry.beginColdStartScanIfNeeded()
    }

    deinit {
        // When the last reference to this document drops (tab closed and
        // not retained), clear its open-document registration so the
        // vault watcher resumes treating the file as a closed note.
        guard let url = fileURL else { return }
        Task { @MainActor in
            VaultRegistry.shared.entry(for: url).unregisterOpenDocument(url)
        }
    }

    init() {
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        self.cstInspector = CSTInspector()
        self.writesThroughToFile = false
        // undoHistory is lazy — first access happens
        // on the MainActor in the Coordinator's makeNSView. Don't
        // touch it here.
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
    @discardableResult
    func applyTextEdits(_ edits: [TextEdit]) -> Bool {
        let oldRoot = session.parseResult?.rootSyntax
        do {
            try session.applyTextEdits(edits)
        } catch {
            NSLog("LiminalSourceDocument: applyTextEdits failed: \(error)")
            return false
        }
        syncFromSession()
        MainActor.assumeIsolated {
            if undoHistory.insertSessionActive {
                undoHistory.appendInsertEdits(edits)
            }
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
                treeVersion &+= 1
            }
            indexInVault()
            writeThroughIfNeeded()
        }
        return true
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
            treeVersion &+= 1
        }
        indexInVault()
        writeThroughIfNeeded()
        return true
    }

    @MainActor
    func applyStructuralReplacement(
        target: SyntaxNodeHandle<LiminalLanguage>,
        replacement: GreenTreeSnapshot<LiminalLanguage>,
        edits: [TextEdit]
    ) -> Bool {
        let oldRoot = currentRootSyntax
        do {
            _ = try session.replaceSubtree(target, with: replacement)
        } catch {
            NSLog("LiminalSourceDocument: structural replacement failed: \(error)")
            return false
        }

        syncFromSession()
        if let oldRoot, let newRoot = currentRootSyntax {
            vimController.reanchorMarks(
                oldRoot: oldRoot,
                edits: edits,
                newRoot: newRoot
            )
            cstInspector.refresh(
                cursorByteOffset: cstInspector.snapshot.map { Int($0.cursor.byteOffset.rawValue) },
                root: newRoot,
                source: session.source
            )
            treeVersion &+= 1
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
            // The file on disk now matches the buffer — snap this note's
            // vault fingerprint forward so the watcher doesn't mistake
            // our own save for an external edit, then opportunistically
            // flush the warm-tier cache (a no-op when nothing's dirty).
            let entry = VaultRegistry.shared.entry(for: fileURL)
            entry.noteFileWrittenThrough(fileURL, content: session.source)
            Task { await entry.flushCacheIfDirty() }
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

    /// Seed the undo history's initial state: root snapshot = "as
    /// loaded". Required before any forward edits so undo can rewind
    /// back to the initial state.
    @MainActor
    func seedInitialUndoSnapshot() {
        guard let snap = makeUndoSnapshot(cursor: 0) else { return }
        undoHistory.reset(initial: snap)
    }

    @MainActor
    func makeUndoSnapshot(cursor: Int) -> CSTUndoSnapshot? {
        guard let tree = session.currentTree else { return nil }
        return CSTUndoSnapshot(
            tree: tree,
            cursor: cursor,
            marks: vimController.marks
        )
    }

    @MainActor
    func recordTextTransaction(
        before: CSTUndoSnapshot,
        afterCursor: Int,
        edits: [TextEdit]
    ) {
        precondition(!undoHistory.insertSessionActive, "Immediate undo transaction recorded during insert session")
        guard let after = makeUndoSnapshot(cursor: afterCursor) else { return }
        undoHistory.recordTransaction(
            before: before,
            after: after,
            edits: edits
        )
    }

    /// Open an insert-session bracket. Captures the entry-point
    /// snapshot so `commitInsertSession` can decide whether to record
    /// a transaction (text changed) or drop the session as a no-op
    /// (entered insert and pressed Esc without typing).
    @MainActor
    func beginInsertSession(at cursor: Int) {
        guard let entry = makeUndoSnapshot(cursor: cursor) else { return }
        undoHistory.beginInsertSession(at: entry)
    }

    /// Close an insert session, recording one transaction if the
    /// source changed during the session.
    @MainActor
    func commitInsertSession(at cursor: Int) {
        guard let commit = makeUndoSnapshot(cursor: cursor) else { return }
        undoHistory.commitInsertSession(after: commit)
    }

    @MainActor
    func undoStep() -> CSTUndoNavigation? {
        guard let navigation = undoHistory.undoStep() else { return nil }
        applyUndoNavigation(navigation)
        return navigation
    }

    @MainActor
    func redoStep() -> CSTUndoNavigation? {
        guard let navigation = undoHistory.redoStep() else { return nil }
        applyUndoNavigation(navigation)
        return navigation
    }

    @MainActor
    private func applyUndoNavigation(_ navigation: CSTUndoNavigation) {
        do {
            try session.applySourceEditsWithoutParsing(navigation.sourceEdits)
        } catch {
            preconditionFailure("Undo patch application failed: \(error)")
        }
        session.installSnapshot(tree: navigation.target.tree)
        vimController.restoreMarks(navigation.target.marks)

        #if DEBUG
        precondition(
            session.source == navigation.target.tree.sourceText(),
            "Undo source and target CST diverged"
        )
        #endif

        syncFromSession()
        if let root = currentRootSyntax {
            cstInspector.refresh(
                cursorByteOffset: cstInspector.snapshot.map { Int($0.cursor.byteOffset.rawValue) },
                root: root,
                source: session.source
            )
            treeVersion &+= 1
        }
        indexInVault()
        writeThroughIfNeeded()
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
