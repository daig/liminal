import CambiumCore
import Foundation

/// Off-main-thread enumerator + parser for one-shot cold-start vault
/// indexing. Walks `.lim` files under a vault root (recursively, so
/// subfolders show up in the navigator), parses each via a per-file
/// `LiminalParser`, builds a `DocumentIndex`, and hands the bundle
/// back to the caller on the main actor.
///
/// The file watcher takes over from here for incremental updates after
/// the initial scan completes. Open-document indexes remain
/// authoritative — `VaultEntry.absorb` does not clobber them.
enum VaultIndexer {
    /// Begin the cold-start scan. The work runs on a detached task
    /// so the main actor stays responsive; the `absorb` callback is
    /// invoked on the main actor with the collected results.
    static func scan(
        rootURL: URL,
        absorb: @escaping @MainActor ([ScanResult]) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            let results = collectScanResults(rootURL: rootURL)
            await MainActor.run {
                absorb(results)
            }
        }
    }

    /// Synchronous variant exposed for tests so they can drive the
    /// scan deterministically without spinning the runloop.
    static func scanSync(rootURL: URL) -> [ScanResult] {
        collectScanResults(rootURL: rootURL)
    }

    private static func collectScanResults(rootURL: URL) -> [ScanResult] {
        let limURLs = enumerateLimFiles(under: rootURL)
        let parser = LiminalParser()
        var results: [ScanResult] = []
        results.reserveCapacity(limURLs.count)

        for url in limURLs {
            guard let content = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            do {
                let parsed = try parser.parse(content)
                let index = DocumentIndex.build(root: parsed.rootSyntax)
                results.append(ScanResult(url: url, content: content, index: index))
            } catch {
                NSLog("VaultIndexer: parse failed for \(url.path): \(error)")
            }
        }
        return results
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

    struct ScanResult: Sendable {
        let url: URL
        let content: String
        let index: DocumentIndex
    }
}
