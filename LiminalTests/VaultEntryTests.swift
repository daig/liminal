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
        let parsed = try LiminalParser().parse(source)

        entry.indexCurrentDocument(url, rootSyntax: parsed.rootSyntax, content: source)

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

        let sourceParsed = try LiminalParser().parse(sourceText)
        let targetParsed = try LiminalParser().parse(targetText)

        entry.indexCurrentDocument(sourceURL, rootSyntax: sourceParsed.rootSyntax, content: sourceText)
        entry.indexCurrentDocument(targetURL, rootSyntax: targetParsed.rootSyntax, content: targetText)

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
        let parsed = try LiminalParser().parse("# Heading")
        entry.indexCurrentDocument(url, rootSyntax: parsed.rootSyntax, content: "# Heading")
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

        let firstParsed = try LiminalParser().parse("# A")
        entry.indexCurrentDocument(url, rootSyntax: firstParsed.rootSyntax, content: "# A")
        #expect(entry.indexes[url]?.headings.first?.title == "A")

        let secondParsed = try LiminalParser().parse("# B")
        entry.indexCurrentDocument(url, rootSyntax: secondParsed.rootSyntax, content: "# B")

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
        #expect(source?.content == "[[Target]]")
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

    @Test("applyDiff adds new on-disk notes without dropping existing entries")
    func applyDiffAddsAndPreserves() throws {
        let root = try makeTempVault(files: [
            "Existing.lim": "old"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)

        // Pre-populate with an open-doc index for "Existing.lim".
        let existingURL = root.appendingPathComponent("Existing.lim")
        let existingParsed = try LiminalParser().parse("open content")
        entry.indexCurrentDocument(
            existingURL,
            rootSyntax: existingParsed.rootSyntax,
            content: "open content"
        )

        // Drop a new file on disk; refresh.
        let newURL = root.appendingPathComponent("New.lim")
        try "Hello".data(using: .utf8)!.write(to: newURL)

        let scan = VaultIndexer.scanSync(rootURL: root)
        entry.applyDiff(from: scan)

        let canonicalExisting = VaultRegistry.canonicalNoteURL(for: existingURL)
        let canonicalNew = VaultRegistry.canonicalNoteURL(for: newURL)

        // Open doc untouched; new file picked up.
        #expect(entry.notes[canonicalExisting]?.content == "open content")
        #expect(entry.notes[canonicalNew]?.content == "Hello")
    }

    @Test("applyDiff does not drop notes that disappear from disk")
    func applyDiffPreservesAfterDiskRemoval() throws {
        let root = try makeTempVault(files: [
            "Doc.lim": "hi"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = VaultEntry(rootURL: root)
        let docURL = root.appendingPathComponent("Doc.lim")
        let parsed = try LiminalParser().parse("hi")
        entry.indexCurrentDocument(docURL, rootSyntax: parsed.rootSyntax, content: "hi")

        // Remove the file from disk.
        try FileManager.default.removeItem(at: docURL)

        let scan = VaultIndexer.scanSync(rootURL: root)
        entry.applyDiff(from: scan)

        let canonical = VaultRegistry.canonicalNoteURL(for: docURL)
        #expect(entry.notes[canonical] != nil)
    }

    @Test("absorb does not clobber an open document's index")
    func absorbPreservesOpenDocs() throws {
        // Disk says "old"; in-memory says "new". The in-memory wins.
        let root = try makeTempVault(files: [
            "Doc.lim": "old"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let docURL = root.appendingPathComponent("Doc.lim")
        let entry = VaultEntry(rootURL: root)

        let parsed = try LiminalParser().parse("new")
        entry.indexCurrentDocument(docURL, rootSyntax: parsed.rootSyntax, content: "new")

        let scan = VaultIndexer.scanSync(rootURL: root)
        entry.absorb(scanResults: scan)

        let canonical = VaultRegistry.canonicalNoteURL(for: docURL)
        #expect(entry.notes[canonical]?.content == "new")
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
