import CambiumCore
import Combine
import Foundation

/// Singleton holding `VaultEntry`s keyed by canonical vault root URL.
///
/// A "vault" in this build is implicitly the directory containing an
/// open `.lim` document — `documentURL.deletingLastPathComponent()`,
/// resolved through the symlink-canonical URL so two windows that
/// reach the same file via different paths share one entry.
///
/// Untitled (URL-less) documents do not register; they have no vault
/// until first save.
@MainActor
public final class VaultRegistry {
    public static let shared = VaultRegistry()

    private var entries: [URL: VaultEntry] = [:]

    private init() {}

    /// Look up (or lazily create) the entry for the vault containing
    /// `documentURL`.
    public func entry(for documentURL: URL) -> VaultEntry {
        entryForCanonical(Self.canonicalVaultRoot(for: documentURL))
    }

    /// Look up (or lazily create) the entry for a vault root URL
    /// directly (e.g. when a window is keyed on the vault root, not
    /// on a document URL inside it).
    public func entry(forRoot rootURL: URL) -> VaultEntry {
        entryForCanonical(rootURL.resolvingSymlinksInPath().standardizedFileURL)
    }

    private func entryForCanonical(_ root: URL) -> VaultEntry {
        if let existing = entries[root] {
            return existing
        }
        let entry = VaultEntry(rootURL: root)
        entries[root] = entry
        return entry
    }

    /// Synchronously flush every vault entry's warm-tier cache to disk.
    /// Wired into `applicationWillTerminate`, where there is no time to
    /// await the debounced async flush. Each entry's flush is a no-op
    /// when that entry's cache is already clean.
    public func flushAllCachesSynchronously() {
        for entry in entries.values {
            entry.flushCacheToDiskSynchronously()
        }
    }

    /// Visible for tests — drop all entries so the next access starts
    /// fresh.
    func resetForTesting() {
        entries.removeAll()
    }

    /// Vault root for a document URL, normalized so equivalent URLs
    /// (symlinked, trailing slash differences) map to the same key.
    static func canonicalVaultRoot(for documentURL: URL) -> URL {
        documentURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    /// Canonical key for an in-vault file URL. Symlink-resolved so the
    /// per-note dictionaries don't double-key the same file.
    static func canonicalNoteURL(for documentURL: URL) -> URL {
        documentURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}

/// Per-vault state: known notes, per-note `DocumentIndex` cache, and
/// the aggregated `VaultLinkIndex`. Updated incrementally when an open
/// document parses (slice 2). Augmented by the cold-start vault scan
/// (slice 4) and refreshed by file-system events (slice 6).
@MainActor
public final class VaultEntry: ObservableObject {
    public let rootURL: URL

    /// Currently-tracked notes. In slice 2 these are open documents
    /// only; the cold-start scan absorbs on-disk ones in slice 4.
    @Published public private(set) var notes: [URL: LiminalNoteMetadata] = [:]

    /// Per-note `DocumentIndex` cache. The unit of future on-disk
    /// caching — every entry here is fully reconstructible from the
    /// note's bytes via `LiminalParseSession.parse(_:)` +
    /// `DocumentIndex.build(root:)`.
    @Published public private(set) var indexes: [URL: DocumentIndex] = [:]

    /// Aggregated index. Refolded on every per-note change.
    @Published public private(set) var linkIndex: VaultLinkIndex = .empty

    /// Hierarchical view of `notes.keys`, sorted folders-first /
    /// alphabetical. Recomputed alongside `linkIndex` so the
    /// navigator sidebar can observe it directly without rebuilding
    /// on every SwiftUI render.
    @Published public private(set) var fileTree: [FileTreeNode] = []

    /// One-shot cold-start latch. The scan runs at most once per
    /// entry lifetime; `beginColdStartScanIfNeeded()` is idempotent.
    private var hasStartedColdStartScan = false

    /// Live file-system watcher. Created alongside the cold-start
    /// scan; lives for the entry's lifetime (which, in v1, is the
    /// app's lifetime via `VaultRegistry.shared`).
    private var watcher: FileSystemWatcher?

    /// Canonical URLs of notes currently backed by a live editor.
    /// `refreshFromDisk` never reparses these from disk — an open
    /// document owns its buffer, and conflict resolution for an
    /// externally-modified open document is deferred (see plan).
    /// Maintained by `LiminalSourceDocument` via
    /// `registerOpenDocument` / `unregisterOpenDocument`.
    private var openDocumentURLs: Set<URL> = []

    /// True when in-memory state has diverged from the on-disk warm-tier
    /// cache and a flush is pending. Set by `markCacheDirty()`, cleared
    /// by a flush.
    private var isCacheDirty = false

    /// The pending debounced flush. Re-armed on every `markCacheDirty()`
    /// so the write only lands after a quiet period; cancelled when a
    /// flush runs.
    private var cacheFlushTask: Task<Void, Never>?

    /// Quiet period before a debounced cache flush. A burst of edits
    /// keeps re-arming the timer; the write lands once edits settle.
    private static let cacheFlushDebounceSeconds: UInt64 = 30

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Mark `url` as backed by a live editor. Idempotent. Called by
    /// `LiminalSourceDocument` whenever it (re)indexes itself.
    public func registerOpenDocument(_ url: URL) {
        openDocumentURLs.insert(VaultRegistry.canonicalNoteURL(for: url))
    }

    /// Clear `url`'s open-document registration (document closed, or its
    /// URL changed). Idempotent.
    public func unregisterOpenDocument(_ url: URL) {
        openDocumentURLs.remove(VaultRegistry.canonicalNoteURL(for: url))
    }

    /// Kick off the cold-start vault scan if it hasn't run yet.
    /// Idempotent. The scan runs off-main; results are folded in via
    /// `absorb(scanResults:)` when complete. Triggered from
    /// `LiminalSourceDocument` after the first per-doc indexing — by
    /// that point we know the entry corresponds to a real vault, so
    /// we don't pay scan cost for tests that hold a `VaultEntry`
    /// directly.
    ///
    /// Also starts the directory watcher so out-of-band file
    /// additions / removals / renames keep the link index live.
    public func beginColdStartScanIfNeeded() {
        guard !hasStartedColdStartScan else { return }
        hasStartedColdStartScan = true
        VaultIndexer.scan(rootURL: rootURL) { [weak self] results in
            self?.absorb(scanResults: results)
        }
        let watcher = FileSystemWatcher(rootURL: rootURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFromDisk()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Re-scan the vault off-main in response to a file-system event,
    /// then fold the diff into the entry via `applyRefresh`.
    ///
    /// The current in-memory state is handed to the scanner *as the
    /// cache*: files whose `(mtime, size)` fingerprint is unchanged come
    /// back `.cached` and are skipped, so a watcher fire only reparses
    /// the files that actually changed — not the whole vault.
    func refreshFromDisk() {
        let snapshot = makeCacheSnapshot()
        let openURLs = openDocumentURLs
        Task.detached(priority: .userInitiated) { [rootURL] in
            let results = VaultIndexer.scanSyncUsingCache(
                rootURL: rootURL,
                cache: snapshot
            )
            await MainActor.run { [weak self] in
                self?.applyRefresh(results: results, openDocumentURLs: openURLs)
            }
        }
    }

    /// Fold a watcher-driven rescan into the entry:
    ///
    /// - `.parsed` results for **closed** notes (changed on disk or
    ///   newly created) are reindexed via `applying(documentChange:)`.
    /// - `.parsed` results for **open** notes are skipped — the editor
    ///   owns the buffer; reconciling an externally-modified open
    ///   document is deferred.
    /// - `.cached` results are unchanged and need no work.
    /// - **Closed** notes whose files vanished from disk are dropped;
    ///   open notes are kept even if their file is gone (the editor
    ///   still owns the buffer).
    ///
    /// `openDocumentURLs` is passed in (rather than read from `self`) so
    /// the watcher captures it at scan-dispatch time and tests can drive
    /// the diff deterministically.
    func applyRefresh(
        results: [VaultIndexer.ScanResult],
        openDocumentURLs openURLs: Set<URL>
    ) {
        var urlSetChanged = false
        var persistedCacheStale = false
        var seen: Set<URL> = []

        for result in results {
            let canonical = VaultRegistry.canonicalNoteURL(for: result.url)
            seen.insert(canonical)
            guard result.origin == .parsed else { continue }
            if openURLs.contains(canonical) { continue }

            let isNewNote = notes[canonical] == nil
            let metadata = LiminalNoteMetadata(
                url: canonical,
                relativePath: relativePath(of: canonical),
                fileMtime: result.fileMtime,
                fileByteSize: result.fileByteSize,
                contentHash: result.contentHash
            )
            notes[canonical] = metadata
            indexes[canonical] = result.index
            linkIndex = linkIndex.applying(
                documentChange: canonical,
                metadata: metadata,
                index: result.index
            )
            if isNewNote { urlSetChanged = true }
            persistedCacheStale = true
        }

        // Drop closed notes whose files disappeared from disk. Open
        // documents are retained even when their file is gone.
        for canonical in notes.keys where !seen.contains(canonical) {
            if openURLs.contains(canonical) { continue }
            notes[canonical] = nil
            indexes[canonical] = nil
            linkIndex = linkIndex.applying(removalOf: canonical)
            urlSetChanged = true
            persistedCacheStale = true
        }

        if urlSetChanged { rebuildFileTree() }
        if persistedCacheStale { markCacheDirty() }
    }

    /// Snapshot the entry's current per-note state into the warm-tier
    /// cache shape.
    ///
    /// `excludingOpenDocuments` controls the two use sites:
    /// - The watcher-refresh path includes open documents — their
    ///   on-disk fingerprint lets the scanner skip them when unchanged.
    /// - The **persistence** path excludes them: an open document's
    ///   `index` reflects the in-memory buffer while its fingerprint
    ///   reflects disk, so persisting it could let a later cold start
    ///   reuse an index that doesn't match the file. Excluded notes are
    ///   simply reparsed on the next cold start — cheap, and always
    ///   correct.
    func makeCacheSnapshot(excludingOpenDocuments: Bool = false) -> VaultCacheSnapshot {
        VaultCacheSnapshot(entries: notes.values.compactMap { metadata in
            if excludingOpenDocuments, openDocumentURLs.contains(metadata.id) {
                return nil
            }
            return VaultCacheEntry(
                relativePath: metadata.relativePath,
                title: metadata.title,
                fileMtime: metadata.fileMtime,
                fileByteSize: metadata.fileByteSize,
                contentHash: metadata.contentHash,
                index: indexes[metadata.id] ?? .empty
            )
        })
    }

    /// Mark the warm-tier cache stale and (re)arm the debounced flush.
    /// Called from every path that mutates `notes` / `indexes` /
    /// `linkIndex`. A burst of edits keeps re-arming the timer; the
    /// write lands once edits settle for `cacheFlushDebounceSeconds`.
    private func markCacheDirty() {
        isCacheDirty = true
        cacheFlushTask?.cancel()
        cacheFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.cacheFlushDebounceSeconds))
            guard !Task.isCancelled else { return }
            await self?.flushCacheIfDirty()
        }
    }

    /// Write the warm-tier cache to disk if it's stale, off the main
    /// actor via `VaultCacheStore`. The debounced timer's target; also
    /// invoked opportunistically on document save. No-op when clean.
    public func flushCacheIfDirty() async {
        guard isCacheDirty else { return }
        isCacheDirty = false
        cacheFlushTask?.cancel()
        cacheFlushTask = nil
        let snapshot = makeCacheSnapshot(excludingOpenDocuments: true)
        await VaultCacheStore.shared.write(snapshot, forRoot: rootURL)
    }

    /// Synchronous flush for `applicationWillTerminate`, where there is
    /// no time to await an actor hop. No-op when clean.
    public func flushCacheToDiskSynchronously() {
        guard isCacheDirty else { return }
        isCacheDirty = false
        cacheFlushTask?.cancel()
        cacheFlushTask = nil
        let snapshot = makeCacheSnapshot(excludingOpenDocuments: true)
        VaultCacheStore.writeSnapshot(snapshot, forRoot: rootURL)
    }

    /// Fold one-shot scan results into the entry. Open documents win
    /// — if a note already lives in `notes` (because a
    /// `LiminalSourceDocument` registered it), the on-disk version
    /// from the scan is dropped. This is how unsaved edits in an
    /// open editor remain authoritative.
    ///
    /// Internal because `VaultIndexer.ScanResult` is implementation
    /// detail; tests reach this through `@testable import`.
    func absorb(scanResults: [VaultIndexer.ScanResult]) {
        absorbNewScanResults(scanResults)
    }

    /// Shared body for `absorb` / `applyDiff`: add scan results for notes
    /// not already tracked, folding each into `linkIndex` incrementally.
    /// `fileTree` is rebuilt once at the end iff the URL set grew.
    ///
    /// The scan result already carries the note's disk fingerprint
    /// (`fileMtime` / `fileByteSize` / `contentHash`) — captured during
    /// enumeration or reused from the warm-tier cache — so there is no
    /// redundant `stat` here.
    private func absorbNewScanResults(_ scanResults: [VaultIndexer.ScanResult]) {
        var urlSetChanged = false
        var persistedCacheStale = false
        for result in scanResults {
            let canonical = VaultRegistry.canonicalNoteURL(for: result.url)
            if notes[canonical] != nil { continue }
            let metadata = LiminalNoteMetadata(
                url: canonical,
                relativePath: relativePath(of: canonical),
                fileMtime: result.fileMtime,
                fileByteSize: result.fileByteSize,
                contentHash: result.contentHash
            )
            notes[canonical] = metadata
            indexes[canonical] = result.index
            linkIndex = linkIndex.applying(
                documentChange: canonical,
                metadata: metadata,
                index: result.index
            )
            urlSetChanged = true
            // A `.cached` result is already on disk in the warm-tier
            // cache — only a freshly `.parsed` note makes it stale.
            if result.origin == .parsed { persistedCacheStale = true }
        }
        if urlSetChanged { rebuildFileTree() }
        if persistedCacheStale { markCacheDirty() }
    }

    /// Update the cache for one note from a fresh CST root + current
    /// content, then refold `linkIndex`. Cheap (one CST walk +
    /// dictionary rebuild). Caller passes the canonical URL — see
    /// `VaultRegistry.canonicalNoteURL(for:)`.
    ///
    /// `content` is the in-memory source for the doc (open-doc buffer or
    /// just-read file bytes). It feeds `DocumentIndex.build(root:source:)`
    /// so the resulting index carries pre-computed backlink snippets.
    ///
    /// The disk fingerprint (`fileMtime` / `fileByteSize` / `contentHash`)
    /// describes the file *on disk*, so it is preserved across in-memory
    /// reindexes of an already-tracked note — it only advances when the
    /// note is first read from disk or written back to it (see
    /// `noteFileWrittenThrough(_:content:)`). For a not-yet-tracked note,
    /// the first index runs before any edit, so `content` equals the
    /// file's bytes and the freshly-computed fingerprint is the disk one.
    public func indexCurrentDocument(
        _ url: URL,
        rootSyntax: RootSyntax,
        content: String
    ) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        let fileMtime: Date
        let fileByteSize: UInt32
        let contentHash: UInt64
        if let existing = notes[canonical] {
            fileMtime = existing.fileMtime
            fileByteSize = existing.fileByteSize
            contentHash = existing.contentHash
        } else {
            let (mtime, byteSize) = VaultIndexer.diskFingerprint(at: canonical)
            fileMtime = mtime
            fileByteSize = byteSize
            contentHash = VaultCacheFormat.contentHash(Array(content.utf8))
        }
        let metadata = LiminalNoteMetadata(
            url: canonical,
            relativePath: relativePath(of: canonical),
            fileMtime: fileMtime,
            fileByteSize: fileByteSize,
            contentHash: contentHash
        )
        let isNewNote = notes[canonical] == nil
        let newIndex = DocumentIndex.build(root: rootSyntax, source: content)
        notes[canonical] = metadata
        indexes[canonical] = newIndex
        linkIndex = linkIndex.applying(
            documentChange: canonical,
            metadata: metadata,
            index: newIndex
        )
        // The file tree depends only on the URL set, not document content,
        // so it only needs rebuilding when a note is first tracked.
        if isNewNote { rebuildFileTree() }
    }

    /// Snap this note's disk fingerprint forward after a successful
    /// write-through to disk. Called by `LiminalSourceDocument` after a
    /// save completes so the watcher's `disk mtime > recorded mtime`
    /// check correctly distinguishes our own save from a subsequent
    /// external edit. `content` is the just-written buffer — its hash
    /// becomes the note's new `contentHash`.
    @MainActor
    public func noteFileWrittenThrough(_ url: URL, content: String) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        guard var metadata = notes[canonical] else { return }
        let (mtime, byteSize) = VaultIndexer.diskFingerprint(at: canonical)
        metadata.fileMtime = mtime
        metadata.fileByteSize = byteSize
        metadata.contentHash = VaultCacheFormat.contentHash(Array(content.utf8))
        notes[canonical] = metadata
    }

    /// Drop a note from the entry (e.g., the document moved on Save As,
    /// or its tab closed). Also clears any open-document registration so
    /// the watcher treats the URL as closed from here on.
    public func remove(_ url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        openDocumentURLs.remove(canonical)
        let removedNote = notes.removeValue(forKey: canonical)
        let removedIndex = indexes.removeValue(forKey: canonical)
        guard removedNote != nil || removedIndex != nil else { return }
        linkIndex = linkIndex.applying(removalOf: canonical)
        rebuildFileTree()
        markCacheDirty()
    }

    /// Rebuild the hierarchical file tree from the current note URL set.
    /// Independent of `linkIndex` — the tree depends only on which notes
    /// exist, not on their content — so it's rebuilt only when the URL
    /// set changes (add / remove), not on every content reindex.
    private func rebuildFileTree() {
        fileTree = FileTreeBuilder.build(
            noteURLs: Array(notes.keys),
            vaultRoot: rootURL
        )
    }

    /// Vault-relative path string for a canonical file URL, computed
    /// against this entry's root. Thin wrapper over
    /// `VaultIndexer.relativePath(of:under:)`.
    private func relativePath(of fileURL: URL) -> String {
        VaultIndexer.relativePath(of: fileURL, under: rootURL)
    }
}
