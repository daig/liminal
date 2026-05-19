import CambiumCore
import Foundation

/// Off-main-thread enumerator + parser for cold-start vault indexing.
/// Walks `.lim` files under a vault root (recursively, so subfolders show
/// up in the navigator), and for each file either **reuses** the matching
/// warm-tier cache entry — when its `(mtime, size)` fingerprint is
/// unchanged — or **parses** it fresh, building a `DocumentIndex`.
///
/// The file watcher takes over from here for incremental updates after
/// the initial scan completes. Open-document indexes remain
/// authoritative — `VaultEntry.absorb` does not clobber them.
enum VaultIndexer {
    /// Begin the cold-start scan. Runs on a detached task so the main
    /// actor stays responsive: loads the warm-tier cache, walks the
    /// vault reusing unchanged entries, and invokes `absorb` on the main
    /// actor with the collected results.
    static func scan(
        rootURL: URL,
        absorb: @escaping @MainActor ([ScanResult]) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            let cache = await VaultCacheStore.shared.load(forRoot: rootURL)
            let results = scanSyncUsingCache(rootURL: rootURL, cache: cache)
            await MainActor.run {
                absorb(results)
            }
        }
    }

    /// Synchronous full-parse variant (no cache) exposed for tests so
    /// they can drive the scan deterministically without spinning the
    /// runloop or touching the on-disk cache.
    static func scanSync(rootURL: URL) -> [ScanResult] {
        scanSyncUsingCache(rootURL: rootURL, cache: nil)
    }

    /// Walk `.lim` files under `rootURL`. For each file, reuse the
    /// matching `cache` entry when its `(fileMtime, fileByteSize)`
    /// fingerprint still matches disk; otherwise parse the file fresh.
    /// Synchronous, with the cache passed in as a parameter, so the
    /// cache-hit / reparse split is directly testable.
    static func scanSyncUsingCache(
        rootURL: URL,
        cache: VaultCacheSnapshot?
    ) -> [ScanResult] {
        let cacheByPath: [String: VaultCacheEntry]
        if let cache {
            cacheByPath = Dictionary(
                cache.entries.map { ($0.relativePath, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            cacheByPath = [:]
        }

        let limURLs = enumerateLimFiles(under: rootURL)
        let parser = LiminalParser()
        var results: [ScanResult] = []
        results.reserveCapacity(limURLs.count)

        for url in limURLs {
            let relativePath = relativePath(of: url, under: rootURL)
            let (mtime, byteSize) = diskFingerprint(at: url)

            // Cache hit: `(mtime, size)` unchanged → reuse the cached
            // `DocumentIndex` verbatim, skipping the parse entirely.
            if let cached = cacheByPath[relativePath],
               cached.fileMtime == mtime,
               cached.fileByteSize == byteSize
            {
                results.append(ScanResult(
                    url: url,
                    fileMtime: cached.fileMtime,
                    fileByteSize: cached.fileByteSize,
                    contentHash: cached.contentHash,
                    index: cached.index,
                    origin: .cached
                ))
                continue
            }

            // Cache miss or changed file: parse fresh. Source is threaded
            // into `DocumentIndex.build` so each `DocumentReference`
            // carries its pre-computed backlink snippet.
            //
            // Coordinated read so we don't race with the iCloud daemon
            // (or any other registered presenter). `presenter: nil` —
            // the scanner is background and doesn't own a presenter
            // for the file. Apple still coordinates with all other
            // registered presenters.
            let content: String
            do {
                content = try CoordinatedFileIO.read(at: url, presenter: nil) { url in
                    try String(contentsOf: url, encoding: .utf8)
                }
            } catch {
                continue
            }
            do {
                let source = CambiumSource(content)
                let parsed = try parser.parse(source)
                let index = DocumentIndex.build(root: parsed.rootSyntax, source: source)
                results.append(ScanResult(
                    url: url,
                    fileMtime: mtime,
                    fileByteSize: byteSize,
                    contentHash: VaultCacheFormat.contentHash(Array(content.utf8)),
                    index: index,
                    origin: .parsed
                ))
            } catch {
                NSLog("VaultIndexer: parse failed for \(url.path): \(error)")
            }
        }
        return results
    }

    /// Read disk modification time + byte size for `url`. Returns
    /// `(.distantPast, 0)` when the file doesn't exist or is unreadable —
    /// both fingerprints then mismatch any future stat, which correctly
    /// forces a reparse on the next scan / watcher pass.
    static func diskFingerprint(at url: URL) -> (mtime: Date, byteSize: UInt32) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
        let rawSize = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return (mtime, UInt32(clamping: rawSize))
    }

    /// Vault-relative path string for a file URL under `rootURL`. Falls
    /// back to the last path component when `fileURL` isn't actually
    /// under the root (shouldn't happen for enumerated files).
    static func relativePath(of fileURL: URL, under rootURL: URL) -> String {
        let rootPath = rootURL.path
        let filePath = fileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    /// Recursively enumerate `.lim` files under `rootURL`. Skips
    /// hidden files/folders (e.g. `.git`) and package contents like
    /// `.app` bundles. Returns a deterministic order (by path) so the
    /// scan is reproducible regardless of filesystem enumeration
    /// ordering.
    private static func enumerateLimFiles(under rootURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "lim" else { continue }
            // Cheap regular-file confirmation; the enumerator can hand
            // back symlinks / special files in unusual setups.
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == false { continue }
            found.append(url)
        }
        found.sort { $0.path < $1.path }
        return found
    }

    /// One enumerated `.lim` file: its disk fingerprint plus the
    /// `DocumentIndex` to fold in, and whether that index was reused from
    /// the cache or freshly parsed this pass.
    struct ScanResult: Sendable {
        /// Whether this result's `index` was reused from the warm-tier
        /// cache or produced by a fresh parse during this scan.
        enum Origin: Sendable, Equatable {
            case cached
            case parsed
        }

        let url: URL
        let fileMtime: Date
        let fileByteSize: UInt32
        let contentHash: UInt64
        let index: DocumentIndex
        let origin: Origin
    }
}
