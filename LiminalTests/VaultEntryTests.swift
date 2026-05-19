import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("VaultEntry")
@MainActor
struct VaultEntryTests {
    @Test("empty entry has empty link index")
    func emptyEntryEmptyIndex() {
        let entry = VaultEntry(rootURL: URL(fileURLWithPath: "/tmp/v"))
        #expect(entry.notes.isEmpty)
        #expect(entry.indexes.isEmpty)
        #expect(entry.linkIndex == .empty)
    }

    @Test("indexing a single document populates notes, indexes, and link index")
    func indexSingleDocument() throws {
        let entry = VaultEntry(rootURL: URL(fileURLWithPath: "/tmp/v"))
        let url = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let source = "[[Other]] and [[#Heading]]\n# Heading"
        let parsed = try LiminalParser().parse(CambiumSource(source))

        entry.indexCurrentDocument(url, rootSyntax: parsed.rootSyntax, content: CambiumSource(source))

        #expect(entry.notes.count == 1)
        #expect(entry.notes[url]?.relativePath == "Source.lim")
        #expect(entry.indexes[url]?.references.count == 2)

        // Within-doc heading anchor resolves; cross-doc target unresolved.
        let outgoing = entry.linkIndex.outgoing(for: url)
        #expect(outgoing.count == 2)
        #expect(outgoing.contains { ref in
            ref.target.heading == "Heading" && ref.resolution == .resolved(.heading(url, heading: "Heading"))
        })
        #expect(outgoing.contains { ref in
            ref.target.notePath == "Other" && ref.resolution == .unresolved
        })
    }

    @Test("indexing two documents resolves cross-doc wikilinks")
    func crossDocResolution() throws {
        let entry = VaultEntry(rootURL: URL(fileURLWithPath: "/tmp/v"))
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let targetURL = URL(fileURLWithPath: "/tmp/v/Target.lim")

        let sourceText = "[[Target]]"
        let targetText = "Hello"

        let sourceParsed = try LiminalParser().parse(CambiumSource(sourceText))
        let targetParsed = try LiminalParser().parse(CambiumSource(targetText))

        entry.indexCurrentDocument(sourceURL, rootSyntax: sourceParsed.rootSyntax, content: CambiumSource(sourceText))
        entry.indexCurrentDocument(targetURL, rootSyntax: targetParsed.rootSyntax, content: CambiumSource(targetText))

        let outgoing = entry.linkIndex.outgoing(for: sourceURL)
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.resolution == .resolved(.note(targetURL)))

        let backlinks = entry.linkIndex.backlinks(for: targetURL)
        #expect(backlinks.count == 1)
        #expect(backlinks.first?.sourceNoteID == sourceURL)
    }

    @Test("removing a doc drops it from the link index")
    func removeDoc() throws {
        let entry = VaultEntry(rootURL: URL(fileURLWithPath: "/tmp/v"))
        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        let parsed = try LiminalParser().parse(CambiumSource("# Heading"))
        entry.indexCurrentDocument(url, rootSyntax: parsed.rootSyntax, content: CambiumSource("# Heading"))
        #expect(entry.notes[url] != nil)

        entry.remove(url)

        #expect(entry.notes.isEmpty)
        #expect(entry.indexes.isEmpty)
        #expect(entry.linkIndex == .empty)
    }

    @Test("re-indexing the same URL replaces the previous entry rather than duplicating")
    func reindexReplaces() throws {
        let entry = VaultEntry(rootURL: URL(fileURLWithPath: "/tmp/v"))
        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")

        let firstParsed = try LiminalParser().parse(CambiumSource("# A"))
        entry.indexCurrentDocument(url, rootSyntax: firstParsed.rootSyntax, content: CambiumSource("# A"))
        #expect(entry.indexes[url]?.headings.first?.title == "A")

        let secondParsed = try LiminalParser().parse(CambiumSource("# B"))
        entry.indexCurrentDocument(url, rootSyntax: secondParsed.rootSyntax, content: CambiumSource("# B"))

        #expect(entry.notes.count == 1)
        #expect(entry.indexes[url]?.headings.first?.title == "B")
    }
}

@Suite("VaultIndexer")
@MainActor
struct VaultIndexerTests {
    @Test("scanSync enumerates .lim files and builds a DocumentIndex per file")
    func scanEnumeratesLimFiles() throws {
        let root = try makeTempVault(files: [
            "Source.lim": "[[Target]]",
            "Target.lim": "# Heading",
            "ignore.txt": "not a lim file",
            "skip.md": "wrong extension"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let results = VaultIndexer.scanSync(rootURL: root)
        let names = Set(results.map { $0.url.lastPathComponent })
        #expect(names == ["Source.lim", "Target.lim"])

        let source = results.first { $0.url.lastPathComponent == "Source.lim" }
        #expect(source?.origin == .parsed)
        #expect(source?.index.references.count == 1)
        #expect(source?.index.references.first?.target.notePath == "Target")

        let target = results.first { $0.url.lastPathComponent == "Target.lim" }
        #expect(target?.index.headings.first?.title == "Heading")
    }

    @Test("scanSync recurses into subdirectories")
    func scanRecursesSubfolders() throws {
        let root = try makeTempVault(files: [
            "Top.lim": "top",
            "subdir/Inner.lim": "inner",
            "subdir/deeper/Deepest.lim": "deepest",
            "subdir/skip.txt": "ignored",
            ".hidden/Hidden.lim": "should not appear (hidden parent)"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let names = Set(VaultIndexer.scanSync(rootURL: root)
            .map { $0.url.lastPathComponent })
        #expect(names == ["Top.lim", "Inner.lim", "Deepest.lim"])
    }

    @Test("scanSync returns empty for a nonexistent directory")
    func scanMissingDirectory() {
        let bogus = URL(fileURLWithPath: "/tmp/no-such-vault-xyz-12345")
        let results = VaultIndexer.scanSync(rootURL: bogus)
        #expect(results.isEmpty)
    }

    @Test("absorb adds scanned notes that aren't already open")
    func absorbAddsNew() throws {
        let root = try makeTempVault(files: [
            "Other.lim": "Hello"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)
        let scan = VaultIndexer.scanSync(rootURL: root)
        entry.absorb(scanResults: scan)

        let canonical = VaultRegistry.canonicalNoteURL(for: root.appendingPathComponent("Other.lim"))
        #expect(entry.notes[canonical] != nil)
        #expect(entry.indexes[canonical] != nil)
    }

    @Test("refresh adds new on-disk notes and leaves open documents untouched")
    func refreshAddsNewNotesAndKeepsOpenDocs() throws {
        let root = try makeTempVault(files: [
            "Existing.lim": "[[DiskTarget]]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)

        // Pre-populate with an open-doc index for "Existing.lim". Use
        // distinguishable wikilink targets so the resulting DocumentIndex
        // proves the open-doc version survived the refresh (metadata no
        // longer carries source bytes).
        let existingURL = root.appendingPathComponent("Existing.lim")
        let canonicalExisting = VaultRegistry.canonicalNoteURL(for: existingURL)
        let openContent = "[[InMemTarget]]"
        let existingParsed = try LiminalParser().parse(CambiumSource(openContent))
        entry.indexCurrentDocument(
            existingURL,
            rootSyntax: existingParsed.rootSyntax,
            content: CambiumSource(openContent)
        )

        // Drop a new file on disk; rescan against the current state.
        let newURL = root.appendingPathComponent("New.lim")
        try "Hello".data(using: .utf8)!.write(to: newURL)
        let rescan = VaultIndexer.scanSyncUsingCache(
            rootURL: root,
            cache: entry.makeCacheSnapshot()
        )
        entry.applyRefresh(results: rescan, openDocumentURLs: [canonicalExisting])

        let canonicalNew = VaultRegistry.canonicalNoteURL(for: newURL)
        // Open doc untouched (its DocumentIndex still references
        // InMemTarget, not DiskTarget); new file picked up.
        #expect(entry.notes[canonicalExisting] != nil)
        #expect(entry.indexes[canonicalExisting]?.references.first?.target.notePath == "InMemTarget")
        #expect(entry.notes[canonicalNew] != nil)
        #expect(entry.indexes[canonicalNew] != nil)
    }

    @Test("refresh keeps an open document even when its file vanishes from disk")
    func refreshKeepsOpenDocsWhoseFileVanished() throws {
        let root = try makeTempVault(files: ["Doc.lim": "hi"])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)
        let docURL = root.appendingPathComponent("Doc.lim")
        let canonical = VaultRegistry.canonicalNoteURL(for: docURL)
        let parsed = try LiminalParser().parse(CambiumSource("hi"))
        entry.indexCurrentDocument(docURL, rootSyntax: parsed.rootSyntax, content: CambiumSource("hi"))

        // Remove the file from disk, then refresh — the open document is
        // authoritative and must not be dropped.
        try FileManager.default.removeItem(at: docURL)
        let rescan = VaultIndexer.scanSyncUsingCache(
            rootURL: root,
            cache: entry.makeCacheSnapshot()
        )
        entry.applyRefresh(results: rescan, openDocumentURLs: [canonical])

        #expect(entry.notes[canonical] != nil)
    }

    @Test("refresh drops a closed note whose file vanished from disk")
    func refreshDropsClosedNotesWhoseFileVanished() throws {
        let root = try makeTempVault(files: [
            "Keep.lim": "kept",
            "Gone.lim": "[[Keep]]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        // Both notes enter the entry as *closed* (cold-start absorb).
        let entry = VaultEntry(rootURL: root)
        entry.absorb(scanResults: VaultIndexer.scanSync(rootURL: root))
        let goneURL = root.appendingPathComponent("Gone.lim")
        let keepURL = root.appendingPathComponent("Keep.lim")
        #expect(entry.notes[VaultRegistry.canonicalNoteURL(for: goneURL)] != nil)

        try FileManager.default.removeItem(at: goneURL)
        let rescan = VaultIndexer.scanSyncUsingCache(
            rootURL: root,
            cache: entry.makeCacheSnapshot()
        )
        entry.applyRefresh(results: rescan, openDocumentURLs: [])

        // The deleted closed note is dropped; the survivor remains.
        #expect(entry.notes[VaultRegistry.canonicalNoteURL(for: goneURL)] == nil)
        #expect(entry.notes[VaultRegistry.canonicalNoteURL(for: keepURL)] != nil)
    }

    @Test("refresh reparses a closed note that changed on disk")
    func refreshReparsesChangedClosedNotes() throws {
        let root = try makeTempVault(files: ["Doc.lim": "[[Before]]"])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)
        entry.absorb(scanResults: VaultIndexer.scanSync(rootURL: root))
        let docURL = root.appendingPathComponent("Doc.lim")
        let canonical = VaultRegistry.canonicalNoteURL(for: docURL)
        #expect(entry.indexes[canonical]?.references.first?.target.notePath == "Before")

        // Edit the file externally (different content AND length), then refresh.
        try "[[After]] with more text".data(using: .utf8)!.write(to: docURL)
        let rescan = VaultIndexer.scanSyncUsingCache(
            rootURL: root,
            cache: entry.makeCacheSnapshot()
        )
        entry.applyRefresh(results: rescan, openDocumentURLs: [])

        #expect(entry.indexes[canonical]?.references.first?.target.notePath == "After")
    }

    @Test("absorb does not clobber an open document's index")
    func absorbPreservesOpenDocs() throws {
        // Disk says one thing; in-memory says another. The in-memory wins.
        // Use distinguishable wikilink targets so we can verify the
        // DocumentIndex (not just metadata identity) is the open-doc one.
        let root = try makeTempVault(files: [
            "Doc.lim": "[[DiskTarget]]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let docURL = root.appendingPathComponent("Doc.lim")
        let entry = VaultEntry(rootURL: root)

        let openContent = "[[OpenDocTarget]]"
        let parsed = try LiminalParser().parse(CambiumSource(openContent))
        entry.indexCurrentDocument(docURL, rootSyntax: parsed.rootSyntax, content: CambiumSource(openContent))

        let scan = VaultIndexer.scanSync(rootURL: root)
        entry.absorb(scanResults: scan)

        let canonical = VaultRegistry.canonicalNoteURL(for: docURL)
        #expect(entry.notes[canonical] != nil)
        #expect(entry.indexes[canonical]?.references.first?.target.notePath == "OpenDocTarget")
    }
}

private func makeTempVault(files: [String: String]) throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("liminal-vault-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, content) in files {
        let url = dir.appendingPathComponent(name)
        // Allow nested paths in the keys (e.g. "subdir/Note.lim").
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)!.write(to: url)
    }
    return dir
}

@Suite("VaultRegistry")
@MainActor
struct VaultRegistryTests {
    @Test("entries are keyed by canonical vault root and shared across documents in the same folder")
    func entrySharing() {
        VaultRegistry.shared.resetForTesting()
        defer { VaultRegistry.shared.resetForTesting() }

        let docA = URL(fileURLWithPath: "/tmp/v1/A.lim")
        let docB = URL(fileURLWithPath: "/tmp/v1/B.lim")
        let docC = URL(fileURLWithPath: "/tmp/v2/C.lim")

        let entryA = VaultRegistry.shared.entry(for: docA)
        let entryB = VaultRegistry.shared.entry(for: docB)
        let entryC = VaultRegistry.shared.entry(for: docC)

        #expect(entryA === entryB)
        #expect(entryA !== entryC)
    }

    @Test("vault root strips the file name from the document URL")
    func vaultRootStripsFileName() {
        let url = URL(fileURLWithPath: "/tmp/foo/bar/Note.lim")
        let root = VaultRegistry.canonicalVaultRoot(for: url)
        #expect(root.path == "/tmp/foo/bar".standardizingPath)
    }
}

private extension String {
    /// Apply the same canonicalization the registry uses for path
    /// comparisons in tests.
    var standardizingPath: String {
        URL(fileURLWithPath: self)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
