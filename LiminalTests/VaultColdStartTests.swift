import CambiumCore
import Foundation
import Testing
@testable import Liminal

/// Cold-start integration: `VaultIndexer.scanSyncUsingCache` must reuse
/// the warm-tier cache for files whose `(mtime, size)` fingerprint is
/// unchanged and reparse only the rest, and the `VaultCacheStore`
/// round-trip through disk must preserve that behaviour.
@Suite("Vault cold-start cache integration")
struct VaultColdStartTests {
    // MARK: Helpers

    private func makeTempVault(files: [String: String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("liminal-coldstart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.data(using: .utf8)!.write(to: url)
        }
        return dir
    }

    /// Build a cache snapshot from a set of scan results — exactly what
    /// the write-through path (phase 7) will do from a `VaultEntry`.
    private func snapshot(
        from results: [VaultIndexer.ScanResult],
        root: URL
    ) -> VaultCacheSnapshot {
        VaultCacheSnapshot(entries: results.map { result in
            VaultCacheEntry(
                relativePath: VaultIndexer.relativePath(of: result.url, under: root),
                title: result.url.deletingPathExtension().lastPathComponent,
                fileMtime: result.fileMtime,
                fileByteSize: result.fileByteSize,
                contentHash: result.contentHash,
                index: result.index
            )
        })
    }

    // MARK: Tests

    @Test("no cache: every file is freshly parsed")
    func noCacheParsesEverything() throws {
        let root = try makeTempVault(files: [
            "A.lim": "[[B]]",
            "Sub/B.lim": "# Heading"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let results = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.origin == .parsed })
    }

    @Test("warm cache: unchanged files are reused, none reparsed")
    func warmCacheReusesUnchangedFiles() throws {
        let root = try makeTempVault(files: [
            "A.lim": "[[B]]",
            "Sub/B.lim": "# Heading"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        // First scan populates a cache; second scan against it should be
        // an all-cache-hit, zero-reparse pass.
        let firstPass = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil)
        let cache = snapshot(from: firstPass, root: root)

        let secondPass = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: cache)
        #expect(secondPass.count == 2)
        #expect(secondPass.allSatisfy { $0.origin == .cached })
        // The reused indexes are identical to the originally parsed ones.
        for result in secondPass {
            let original = firstPass.first { $0.url == result.url }
            #expect(original?.index == result.index)
        }
    }

    @Test("changed file is reparsed while its unchanged siblings stay cached")
    func changedFileReparsedSiblingsCached() throws {
        let root = try makeTempVault(files: [
            "A.lim": "[[B]]",
            "B.lim": "# Heading",
            "C.lim": "plain"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = snapshot(
            from: VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil),
            root: root
        )

        // Mutate B.lim — different content AND length, so the
        // `(mtime, size)` fingerprint mismatches even if the filesystem
        // mtime resolution were coarse.
        let bURL = root.appendingPathComponent("B.lim")
        try "# Heading\n\nnow much longer body text".data(using: .utf8)!.write(to: bURL)

        let rescan = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: cache)
        let byName = Dictionary(
            uniqueKeysWithValues: rescan.map { ($0.url.lastPathComponent, $0) }
        )
        #expect(byName["B.lim"]?.origin == .parsed)
        #expect(byName["A.lim"]?.origin == .cached)
        #expect(byName["C.lim"]?.origin == .cached)
    }

    @Test("a file absent from the cache is parsed fresh")
    func fileAbsentFromCacheIsParsed() throws {
        let root = try makeTempVault(files: ["A.lim": "[[B]]"])
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = snapshot(
            from: VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil),
            root: root
        )

        // Add a brand-new file the cache has never seen.
        try "fresh note".data(using: .utf8)!
            .write(to: root.appendingPathComponent("New.lim"))

        let rescan = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: cache)
        let byName = Dictionary(
            uniqueKeysWithValues: rescan.map { ($0.url.lastPathComponent, $0) }
        )
        #expect(byName["A.lim"]?.origin == .cached)
        #expect(byName["New.lim"]?.origin == .parsed)
    }

    @Test("cache entries for deleted files simply don't appear in results")
    func cacheEntriesForDeletedFilesDropped() throws {
        let root = try makeTempVault(files: [
            "Keep.lim": "kept",
            "Gone.lim": "[[Keep]]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = snapshot(
            from: VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil),
            root: root
        )

        try FileManager.default.removeItem(at: root.appendingPathComponent("Gone.lim"))

        let rescan = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: cache)
        // Results are keyed off enumerated *disk* files, so the deleted
        // note's stale cache entry is silently ignored.
        #expect(rescan.map { $0.url.lastPathComponent } == ["Keep.lim"])
        #expect(rescan.first?.origin == .cached)
    }

    @Test("VaultCacheStore round-trips a snapshot through disk and stays all-cached")
    func cacheStoreRoundTripStaysCached() async throws {
        let root = try makeTempVault(files: [
            "A.lim": "[[B]]",
            "Sub/B.lim": "# Heading ^anchor"
        ])
        let store = VaultCacheStore.shared
        let cacheFile = VaultCacheStore.cacheFileURL(forRoot: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheFile)
        }

        // Parse cold, persist via the store, then reload and re-scan.
        let coldResults = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: nil)
        await store.write(snapshot(from: coldResults, root: root), forRoot: root)

        let reloaded = try #require(await store.load(forRoot: root))
        let warmResults = VaultIndexer.scanSyncUsingCache(rootURL: root, cache: reloaded)
        #expect(warmResults.count == 2)
        #expect(warmResults.allSatisfy { $0.origin == .cached })
        for result in warmResults {
            #expect(coldResults.first { $0.url == result.url }?.index == result.index)
        }
    }

    // MARK: Write-through

    @Test("makeCacheSnapshot(excludingOpenDocuments:) drops open documents")
    @MainActor
    func makeCacheSnapshotExcludesOpenDocuments() throws {
        let root = try makeTempVault(files: [
            "Open.lim": "[[X]]",
            "Closed.lim": "[[Y]]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)
        let openURL = VaultRegistry.canonicalNoteURL(
            for: root.appendingPathComponent("Open.lim")
        )
        let closedURL = VaultRegistry.canonicalNoteURL(
            for: root.appendingPathComponent("Closed.lim")
        )
        // Track both via `indexCurrentDocument` (no cache-dirty side
        // effect), then register one as an open document.
        let openParsed = try LiminalParser().parse(CambiumSource("[[X]]"))
        entry.indexCurrentDocument(openURL, rootSyntax: openParsed.rootSyntax, content: CambiumSource("[[X]]"))
        let closedParsed = try LiminalParser().parse(CambiumSource("[[Y]]"))
        entry.indexCurrentDocument(closedURL, rootSyntax: closedParsed.rootSyntax, content: CambiumSource("[[Y]]"))
        entry.registerOpenDocument(openURL)

        #expect(
            Set(entry.makeCacheSnapshot().entries.map(\.relativePath))
                == ["Open.lim", "Closed.lim"]
        )
        #expect(
            entry.makeCacheSnapshot(excludingOpenDocuments: true).entries.map(\.relativePath)
                == ["Closed.lim"]
        )
    }

    @Test("a dirty entry flushed to disk reloads with its closed-note state")
    @MainActor
    func flushPersistsClosedNotesAndReloads() async throws {
        let root = try makeTempVault(files: [
            "A.lim": "[[B]]",
            "B.lim": "# Heading"
        ])
        let cacheFile = VaultCacheStore.cacheFileURL(forRoot: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheFile)
        }

        let entry = VaultEntry(rootURL: root)
        entry.absorb(scanResults: VaultIndexer.scanSync(rootURL: root)) // marks dirty
        await entry.flushCacheIfDirty()

        let reloaded = try #require(await VaultCacheStore.shared.load(forRoot: root))
        #expect(Set(reloaded.entries.map(\.relativePath)) == ["A.lim", "B.lim"])
        let aEntry = try #require(reloaded.entries.first { $0.relativePath == "A.lim" })
        #expect(aEntry.index.references.first?.target.notePath == "B")
    }

    @Test("the flushed cache on disk excludes open documents")
    @MainActor
    func flushExcludesOpenDocumentsFromDisk() async throws {
        let root = try makeTempVault(files: [
            "Open.lim": "[[X]]",
            "Closed.lim": "[[Y]]"
        ])
        let cacheFile = VaultCacheStore.cacheFileURL(forRoot: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheFile)
        }

        let entry = VaultEntry(rootURL: root)
        entry.absorb(scanResults: VaultIndexer.scanSync(rootURL: root))
        entry.registerOpenDocument(
            VaultRegistry.canonicalNoteURL(for: root.appendingPathComponent("Open.lim"))
        )
        await entry.flushCacheIfDirty()

        let reloaded = try #require(await VaultCacheStore.shared.load(forRoot: root))
        #expect(reloaded.entries.map(\.relativePath) == ["Closed.lim"])
    }

    @Test("flushCacheToDiskSynchronously writes the cache (termination path)")
    @MainActor
    func synchronousFlushWritesCache() async throws {
        let root = try makeTempVault(files: ["Note.lim": "body"])
        let cacheFile = VaultCacheStore.cacheFileURL(forRoot: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cacheFile)
        }

        let entry = VaultEntry(rootURL: root)
        entry.absorb(scanResults: VaultIndexer.scanSync(rootURL: root)) // marks dirty
        entry.flushCacheToDiskSynchronously()

        #expect(FileManager.default.fileExists(atPath: cacheFile.path))
        let reloaded = try #require(await VaultCacheStore.shared.load(forRoot: root))
        #expect(reloaded.entries.map(\.relativePath) == ["Note.lim"])
    }
}
