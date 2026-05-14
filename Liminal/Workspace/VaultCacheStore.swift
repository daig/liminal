import CryptoKit
import Foundation

/// Owns the on-disk vault cache file: a single binary snapshot of every
/// tracked note's metadata + `DocumentIndex`, living in the user caches
/// directory (never inside the vault tree — see plan: avoids sync / git
/// friction, and the cache is always rebuildable from source).
///
/// The cache is a pure cold-start optimization. Every read path is
/// best-effort: a missing, unreadable, or version-mismatched cache simply
/// yields `nil` and the caller falls back to a fresh `VaultIndexer` scan.
/// Every write path is best-effort too: a failed write just means the
/// next launch re-scans.
///
/// An `actor` so concurrent vault entries (and the debounced write path
/// added later) serialize their file I/O without a lock.
actor VaultCacheStore {
    static let shared = VaultCacheStore()

    /// Load the cached snapshot for `rootURL`, or `nil` when there is no
    /// usable cache (absent file, I/O error, or a format / language /
    /// index-schema version mismatch). Never throws — failure is normal
    /// and recoverable.
    func load(forRoot rootURL: URL) -> VaultCacheSnapshot? {
        let path = Self.cacheFileURL(forRoot: rootURL)
        guard let data = try? Data(contentsOf: path) else { return nil }
        do {
            return try VaultCacheFormat.decode(Array(data))
        } catch {
            NSLog("VaultCacheStore: ignoring unusable cache at \(path.path): \(error)")
            return nil
        }
    }

    /// Write `snapshot` for `rootURL` from the actor's executor — the
    /// debounced-flush path. Delegates to `writeSnapshot`.
    func write(_ snapshot: VaultCacheSnapshot, forRoot rootURL: URL) {
        Self.writeSnapshot(snapshot, forRoot: rootURL)
    }

    /// Encode `snapshot` and write it for `rootURL` atomically (temp file
    /// + rename via `Data.write(options: .atomic)`). Best-effort: logs
    /// and returns on failure. Creates the `Liminal` caches subdirectory
    /// on first write.
    ///
    /// `nonisolated` and synchronous so it can also be called directly
    /// from `applicationWillTerminate`, where there is no time to await
    /// an actor hop. Concurrent writers are not a concern in practice —
    /// each vault's file is only ever written from that vault's
    /// `@MainActor` entry — and `.atomic` makes any concurrent *reader*
    /// see either the whole old file or the whole new one.
    nonisolated static func writeSnapshot(
        _ snapshot: VaultCacheSnapshot,
        forRoot rootURL: URL
    ) {
        let path = cacheFileURL(forRoot: rootURL)
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let bytes = VaultCacheFormat.encode(snapshot, vaultRootHint: rootURL.path)
            try Data(bytes).write(to: path, options: .atomic)
        } catch {
            NSLog("VaultCacheStore: write failed for \(path.path): \(error)")
        }
    }

    /// `~/Library/Caches/Liminal/<sha1-hex-of-canonical-root-path>.lcb`.
    ///
    /// Keyed by a hash of the canonical (symlink-resolved, standardized)
    /// vault root path: moving the vault re-keys to a fresh cache file
    /// rather than reusing a stale one. `nonisolated` so tests and the
    /// loader can compute the path without entering the actor.
    nonisolated static func cacheFileURL(forRoot rootURL: URL) -> URL {
        let canonicalPath = rootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let digest = Insecure.SHA1.hash(data: Data(canonicalPath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        return caches
            .appendingPathComponent("Liminal", isDirectory: true)
            .appendingPathComponent("\(hex).lcb")
    }
}
