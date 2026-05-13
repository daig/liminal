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
    @Published public private(set) var notes: [URL: LiminalNote] = [:]

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

    public init(rootURL: URL) {
        self.rootURL = rootURL
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

    /// Re-scan the vault directory off-main and diff the result
    /// against the in-memory state. Open documents win — notes
    /// already in `notes` are not clobbered by what's on disk, and
    /// we don't drop a note we already track even if disk says it's
    /// gone (the open document is authoritative; the next edit will
    /// re-register it). New on-disk files get added; nothing else
    /// changes. Visible to tests for direct invocation.
    func refreshFromDisk() {
        Task.detached(priority: .userInitiated) { [rootURL] in
            let scanResults = VaultIndexer.scanSync(rootURL: rootURL)
            await MainActor.run { [weak self] in
                self?.applyDiff(from: scanResults)
            }
        }
    }

    /// Apply a fresh disk scan to the entry. Pure additions only —
    /// see `refreshFromDisk` for the rationale on not dropping
    /// existing entries.
    func applyDiff(from scanResults: [VaultIndexer.ScanResult]) {
        var changed = false
        for result in scanResults {
            let canonical = VaultRegistry.canonicalNoteURL(for: result.url)
            if notes[canonical] != nil { continue }
            notes[canonical] = LiminalNote(
                url: canonical,
                relativePath: relativePath(of: canonical),
                content: result.content
            )
            indexes[canonical] = result.index
            changed = true
        }
        if changed { rebuildLinkIndex() }
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
        var changed = false
        for result in scanResults {
            let canonical = VaultRegistry.canonicalNoteURL(for: result.url)
            if notes[canonical] != nil { continue }
            notes[canonical] = LiminalNote(
                url: canonical,
                relativePath: relativePath(of: canonical),
                content: result.content
            )
            indexes[canonical] = result.index
            changed = true
        }
        if changed { rebuildLinkIndex() }
    }

    /// Update the cache for one note from a fresh CST root + current
    /// content, then refold `linkIndex`. Cheap (one CST walk +
    /// dictionary rebuild). Caller passes the canonical URL — see
    /// `VaultRegistry.canonicalNoteURL(for:)`.
    public func indexCurrentDocument(
        _ url: URL,
        rootSyntax: RootSyntax,
        content: String
    ) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        let note = LiminalNote(
            url: canonical,
            relativePath: relativePath(of: canonical),
            content: content
        )
        notes[canonical] = note
        indexes[canonical] = DocumentIndex.build(root: rootSyntax)
        rebuildLinkIndex()
    }

    /// Drop a note from the cache (e.g., file removed externally, or
    /// the document moved on Save As).
    public func remove(_ url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        let removedNote = notes.removeValue(forKey: canonical)
        let removedIndex = indexes.removeValue(forKey: canonical)
        guard removedNote != nil || removedIndex != nil else { return }
        rebuildLinkIndex()
    }

    private func rebuildLinkIndex() {
        linkIndex = VaultLinkIndex.build(
            notes: Array(notes.values),
            documentIndexes: indexes
        )
        fileTree = FileTreeBuilder.build(
            noteURLs: Array(notes.keys),
            vaultRoot: rootURL
        )
    }

    /// Compute a vault-relative path string for a canonical file URL.
    /// Falls back to the last path component if the file isn't actually
    /// under the vault root (rare; shouldn't happen for documents that
    /// reached us through `VaultRegistry.entry(for:)`).
    private func relativePath(of fileURL: URL) -> String {
        let rootPath = rootURL.path
        let filePath = fileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }
}
