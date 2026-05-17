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

    /// True while an iCloud download is in progress for the backing
    /// file. Observed by `StatusBar` to render the "Downloading from
    /// iCloud…" indicator.
    @Published private(set) var ubiquityDownloadInProgress: Bool = false

    /// NSFilePresenter helper. Receives external-change notifications
    /// from the iCloud daemon (and any other coordinated writers);
    /// callbacks hop to MainActor and invoke `handleExternalChange`.
    private let filePresenter: DocumentFilePresenter

    /// True while `filePresenter` is currently registered with
    /// `NSFileCoordinator`. Tracked so URL transitions know whether
    /// to remove-then-add vs add-fresh, and `deinit` knows whether
    /// to issue a defensive remove.
    private var isFilePresenterRegistered: Bool = false

    /// Mtime of the file the last time we wrote (or read) it. Used to
    /// distinguish our own coordinated atomic writes — which fire
    /// `presentedItemDidChange` on the presenter as a delete-then-create
    /// — from genuine external changes. When `presentedItemDidChange`
    /// arrives, we stat and compare: if the mtime hasn't advanced past
    /// `lastSeenDiskMtime`, suppress the prompt.
    private var lastSeenDiskMtime: Date?

    /// `true` when the document was opened against an evicted iCloud
    /// placeholder (empty bytes). The eventual download completion
    /// should auto-reload from disk WITHOUT prompting — the user
    /// hasn't typed anything yet, so there's nothing to lose.
    private var pendingInitialDownload: Bool = false

    /// Per-document NSMetadataQuery that observes download progress
    /// for the ubiquitous file currently backing the document. Lives
    /// only while a download is in progress; nil otherwise.
    private var ubiquityMetadataQuery: NSMetadataQuery?
    private var ubiquityMetadataObservers: [NSObjectProtocol] = []

    /// Posted when an external (non-self) change to the backing file
    /// is detected and the user should be prompted to reload. The
    /// Coordinator observes this and presents an `NSAlert` sheet.
    static let externalChangeNotification = Notification.Name(
        "liminal.sourceDocument.externalChange"
    )

    /// Push the current file URL down from the view layer. Idempotent
    /// — no-op when unchanged. On a transition (nil → URL, URL → URL',
    /// URL → nil) updates the `VaultRegistry`: drops us from the old
    /// vault entry and indexes the current document into the new one,
    /// then re-registers the `NSFilePresenter` and kicks off an
    /// ubiquity-status check for the new URL.
    @MainActor
    func setFileURL(_ url: URL?) {
        guard fileURL != url else { return }
        let oldURL = fileURL
        fileURL = url
        if let oldURL {
            VaultRegistry.shared.entry(for: oldURL).remove(oldURL)
        }
        indexInVault()

        // NSFilePresenter lifecycle: remove for the old URL (if any),
        // update the presenter's URL, re-add for the new URL (if any).
        // Apple's coordinator holds presenters weakly, but explicit
        // unregistration ensures no stale dispatches into our queue
        // after the document moves between URLs.
        if isFilePresenterRegistered {
            NSFileCoordinator.removeFilePresenter(filePresenter)
            isFilePresenterRegistered = false
        }
        filePresenter.updatePresentedURL(url)
        if url != nil {
            NSFileCoordinator.addFilePresenter(filePresenter)
            isFilePresenterRegistered = true
        }

        // Initialize lastSeenDiskMtime from the file's current mtime
        // so the first presenter callback that might fire from our own
        // post-load activity has the right baseline.
        lastSeenDiskMtime = currentDiskMtime(for: url)

        // Kick the ubiquity check for the new URL. No-op for local
        // files; for evicted iCloud files it starts a download and
        // surfaces the status-bar indicator.
        beginUbiquityCheckIfNeeded(for: url)
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
        // Defensive presenter unregister. Apple holds presenters
        // weakly, but explicit unregistration prevents any stale
        // dispatches into the presenter's queue after deinit.
        if isFilePresenterRegistered {
            NSFileCoordinator.removeFilePresenter(filePresenter)
        }
        // Tear down any active NSMetadataQuery so it doesn't keep us
        // alive past deinit (the query keeps a strong ref to its
        // observers).
        stopUbiquityMetadataQuery()
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
        self.filePresenter = DocumentFilePresenter(owner: nil)
        // undoHistory is lazy — first access happens
        // on the MainActor in the Coordinator's makeNSView. Don't
        // touch it here.
        syncFromSession()
        // Self isn't fully constructed until all stored props are set;
        // wire the presenter's weak back-ref now that init is complete.
        filePresenter.owner = self
    }

    @MainActor
    convenience init(standaloneFileURL url: URL) throws {
        let data = try CoordinatedFileIO.read(at: url, presenter: nil) {
            try Data(contentsOf: $0)
        }
        guard let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(standaloneSource: source, fileURL: url)
    }

    private init(standaloneSource source: String, fileURL: URL) throws {
        self.session = LiminalEditorSession()
        self.vimController = VimController()
        self.cstInspector = CSTInspector()
        self.writesThroughToFile = true
        self.filePresenter = DocumentFilePresenter(owner: nil)
        try session.replaceSource(source)
        syncFromSession()
        filePresenter.owner = self
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
        self.filePresenter = DocumentFilePresenter(owner: nil)
        try session.replaceSource(source)
        syncFromSession()
        filePresenter.owner = self
        // Seeding deferred to Coordinator.makeNSView.
        // If the empty-byte path fired (evicted iCloud file), mark
        // pendingInitialDownload — the ubiquity machinery in
        // setFileURL (called shortly from the view layer) will see
        // it and trigger an auto-reload when bytes arrive.
        if data.isEmpty { pendingInitialDownload = true }
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
            try CoordinatedFileIO.write(
                Data(session.source.utf8),
                to: fileURL,
                presenter: filePresenter
            )
            // Snap the self-write coalescing mtime forward BEFORE the
            // vault-fingerprint update — `presentedItemDidChange` may
            // already be dispatched on the presenter queue and the
            // race window is short.
            lastSeenDiskMtime = currentDiskMtime(for: fileURL)
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

    // MARK: - File-presenter hooks (called from DocumentFilePresenter on MainActor)

    /// Triggered when the file presenter reports an external change.
    /// First applies the self-write coalescing check (our own atomic
    /// `write(to:options:.atomic)` looks like delete-then-create to
    /// the presenter), then either auto-reloads (pending initial
    /// download) or posts a notification the Coordinator turns into
    /// a sheet prompt.
    @MainActor
    func handleExternalChange() {
        guard let url = fileURL else { return }
        let nowMtime = currentDiskMtime(for: url)
        if let last = lastSeenDiskMtime, let now = nowMtime, last == now {
            // Self-write echo — coordinator saw our own atomic temp-rename.
            return
        }
        // Real external change.
        if pendingInitialDownload {
            // Auto-reload without prompting: the buffer is empty,
            // there's nothing to lose.
            pendingInitialDownload = false
            reloadFromDisk()
            return
        }
        NotificationCenter.default.post(
            name: Self.externalChangeNotification,
            object: self
        )
    }

    /// Triggered when the presenter reports that the backing file
    /// was deleted by another agent. v1: log + keep buffer. The next
    /// `:Write` recreates the file at the same path.
    @MainActor
    func handlePresentedItemDeletion() {
        guard let url = fileURL else { return }
        NSLog("LiminalSourceDocument: backing file deleted externally: \(url.path)")
    }

    /// Re-read the backing file via the coordinator, replace the
    /// session source, reset undo / insert / visual state, and
    /// re-index in the vault. Called both by the external-change
    /// prompt's `Reload` button and by `:Reload`.
    @MainActor
    func reloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            let data = try CoordinatedFileIO.read(at: url, presenter: filePresenter) {
                try Data(contentsOf: $0)
            }
            guard let source = String(data: data, encoding: .utf8) else {
                NSLog("LiminalSourceDocument: reload skipped — file at \(url.path) isn't UTF-8")
                return
            }
            try session.replaceSource(source)
            syncFromSession()
            treeVersion &+= 1
            // Reset undo history to a fresh post-reload baseline so
            // an accidental Cmd-Z doesn't return us to the stale
            // pre-reload buffer. seedInitialUndoSnapshot reuses the
            // makeUndoSnapshot(cursor:) machinery to capture the new
            // tree + zeroed cursor as a fresh root snapshot.
            if let snap = makeUndoSnapshot(cursor: 0) {
                undoHistory.reset(initial: snap)
            }
            // Force normal mode so any pending insert/visual session
            // is discarded along with its (now-stale) buffer.
            vimController.forceNormalMode()
            // Re-index so the vault link index reflects the new content.
            indexInVault()
            lastSeenDiskMtime = currentDiskMtime(for: url)
        } catch {
            NSLog("LiminalSourceDocument: reload failed for \(url.path): \(error)")
        }
    }

    // MARK: - Ubiquity (iCloud Drive) status

    /// Check whether `url` is an ubiquitous (iCloud) file and, if so,
    /// trigger a download when it's evicted / not current. Surfaces
    /// the download via `@Published ubiquityDownloadInProgress` for
    /// the status bar; observes completion via `NSMetadataQuery`.
    @MainActor
    private func beginUbiquityCheckIfNeeded(for url: URL?) {
        stopUbiquityMetadataQuery()
        ubiquityDownloadInProgress = false
        guard let url else { return }
        let keys: [URLResourceKey] = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isUbiquitousItem == true
        else { return }
        let status = values.ubiquitousItemDownloadingStatus
        if status == .current { return }

        // Evicted (placeholder, .notDownloaded) or stale (.downloaded
        // but a newer version exists in iCloud). Trigger a download
        // and observe via NSMetadataQuery.
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            NSLog("LiminalSourceDocument: startDownloadingUbiquitousItem failed for \(url.path): \(error)")
            return
        }
        ubiquityDownloadInProgress = true
        startUbiquityMetadataQuery(for: url)
    }

    @MainActor
    private func startUbiquityMetadataQuery(for url: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            NSMetadataQueryUbiquitousDataScope,
        ]
        query.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemURLKey,
            url as NSURL
        )
        let handler: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateUbiquityProgress()
            }
        }
        let didUpdate = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main,
            using: handler
        )
        let didFinish = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main,
            using: handler
        )
        ubiquityMetadataObservers = [didUpdate, didFinish]
        ubiquityMetadataQuery = query
        query.start()
    }

    /// Nonisolated so `deinit` can call it without an actor hop.
    /// Touches only document-level (non-actor-isolated) properties +
    /// thread-safe Apple APIs (NotificationCenter.removeObserver and
    /// NSMetadataQuery.stop are both safe to invoke off-main).
    private func stopUbiquityMetadataQuery() {
        ubiquityMetadataQuery?.stop()
        for observer in ubiquityMetadataObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        ubiquityMetadataObservers = []
        ubiquityMetadataQuery = nil
    }

    @MainActor
    private func evaluateUbiquityProgress() {
        guard let url = fileURL,
              let values = try? url.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey]
              ),
              values.ubiquitousItemDownloadingStatus == .current
        else { return }
        stopUbiquityMetadataQuery()
        ubiquityDownloadInProgress = false
        // The bytes are now on disk. The presenter's
        // presentedItemDidChange will fire (or already has); when it
        // does, handleExternalChange auto-reloads if the buffer was
        // the empty initial-download placeholder, or prompts the
        // user if they've already typed something. Either way we're
        // done with the metadata query.
    }

    /// Stat the backing file and return its modification date. Used
    /// for self-write coalescing.
    private func currentDiskMtime(for url: URL?) -> Date? {
        guard let url else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
