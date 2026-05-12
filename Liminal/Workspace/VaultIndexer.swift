import CambiumCore
import Foundation

/// Off-main-thread enumerator + parser for one-shot cold-start vault
/// indexing. Walks `.lim` files in a vault root (non-recursive in v1
/// — matches the prototype's flat scan), parses each via a per-file
/// `LiminalParser`, builds a `DocumentIndex`, and hands the bundle
/// back to the caller on the main actor.
///
/// The slice 6 file watcher takes over from here for incremental
/// updates after the initial scan completes. Open-document indexes
/// remain authoritative — `VaultEntry.absorb` does not clobber them.
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
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        let limURLs = urls.filter { $0.pathExtension.lowercased() == "lim" }

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

    struct ScanResult: Sendable {
        let url: URL
        let content: String
        let index: DocumentIndex
    }
}
