import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("DocumentIndex incremental")
struct DocumentIndexIncrementalTests {
    /// Core correctness guard: an incremental build (reusing the previous
    /// memo) must produce a `DocumentIndex` byte-identical to a fresh full
    /// build of the same tree. Only the work differs.
    private func assertIncrementalMatchesFull(
        _ before: String,
        _ after: String,
        _ label: String
    ) throws {
        let beforeSrc = CambiumSource(before)
        let beforeRoot = try LiminalParser().parse(beforeSrc).rootSyntax
        let (_, memo) = DocumentIndex.build(root: beforeRoot, source: beforeSrc, reusing: nil)

        let afterSrc = CambiumSource(after)
        let afterRoot = try LiminalParser().parse(afterSrc).rootSyntax
        let (incremental, _) = DocumentIndex.build(root: afterRoot, source: afterSrc, reusing: memo)
        let full = DocumentIndex.build(root: afterRoot, source: afterSrc)

        #expect(incremental == full, "incremental != full for: \(label)")
    }

    @Test("incremental equals full across localized paragraph edits")
    func paragraphEdits() throws {
        let base = "alpha sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n"
        try assertIncrementalMatchesFull(base, base, "no-op")
        try assertIncrementalMatchesFull(base, "alpha EDITED sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n", "edit first")
        try assertIncrementalMatchesFull(base, "alpha sentence linking [[A]] here\n\nbeta CHANGED sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n", "edit middle")
        try assertIncrementalMatchesFull(base, "alpha sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here tail\n", "edit last")
        try assertIncrementalMatchesFull(base, "alpha sentence linking [[A]] here\n\nNEW sentence linking [[N]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n", "insert paragraph")
        try assertIncrementalMatchesFull(base, "alpha sentence linking [[A]] here\n\ngamma sentence linking [[C]] here\n", "delete paragraph")
        try assertIncrementalMatchesFull(base, "# alpha sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n", "paragraph to heading boundary change")
    }

    @Test("incremental equals full across headings, lists, and tables")
    func structuredEdits() throws {
        let headings = "# One\n\nbody text linking [[X]] here\n\n## Two\n\nmore body linking [[Y]] here\n"
        try assertIncrementalMatchesFull(headings, "# One\n\nbody text linking [[X]] here edited\n\n## Two\n\nmore body linking [[Y]] here\n", "edit under first heading")
        try assertIncrementalMatchesFull(headings, "# One renamed\n\nbody text linking [[X]] here\n\n## Two\n\nmore body linking [[Y]] here\n", "rename first heading")

        let list = "- item linking [[A]] one\n- item linking [[B]] two\n- item linking [[C]] three\n"
        try assertIncrementalMatchesFull(list, "- item linking [[A]] one\n- item EDITED linking [[B]] two\n- item linking [[C]] three\n", "edit a list item")

        let table = "| h1 | h2 |\n| --- | --- |\n| [[A]] | [[B]] |\n| [[C]] | [[D]] |\n"
        try assertIncrementalMatchesFull(table, "| h1 | h2 |\n| --- | --- |\n| [[A]] | [[EDITED]] |\n| [[C]] | [[D]] |\n", "edit one table cell")
    }

    @Test("reuse actually occurs: unchanged blocks hit the memo")
    func reuseOccurs() throws {
        let before = "alpha sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n"
        let after = "alpha EDITED sentence linking [[A]] here\n\nbeta sentence linking [[B]] here\n\ngamma sentence linking [[C]] here\n"

        let beforeSrc = CambiumSource(before)
        let (_, memo) = DocumentIndex.build(
            root: try LiminalParser().parse(beforeSrc).rootSyntax,
            source: beforeSrc,
            reusing: nil
        )

        let afterSrc = CambiumSource(after)
        let afterRoot = try LiminalParser().parse(afterSrc).rootSyntax
        var builder = DocumentIndexBuilder(source: afterSrc, previousMemo: memo)
        _ = builder.build(root: afterRoot)

        // The unchanged beta + gamma paragraphs (and their subtrees) should
        // reuse cached contributions rather than re-fold.
        #expect(builder.reuseHits > 0)
    }

    @Test("snippet is the enclosing block's text, with reference markers")
    func snippetIsEnclosingBlockText() throws {
        let source = "Intro line.\n\nThis paragraph mentions [[Target]] partway through a longer sentence that keeps going.\n\nOutro line.\n"
        let src = CambiumSource(source)
        let index = DocumentIndex.build(root: try LiminalParser().parse(src).rootSyntax, source: src)

        let ref = try #require(index.references.first { $0.target.rawTargetString == "Target" })
        // Snippet text is the whole containing paragraph (newlines collapsed,
        // trimmed) — not a fixed ±N-byte window.
        #expect(ref.snippet.text == "This paragraph mentions [[Target]] partway through a longer sentence that keeps going.")

        // The reference markers index into the snippet text and bracket the link.
        let bytes = Array(ref.snippet.text.utf8)
        let lo = Int(ref.snippet.referenceOffset)
        let hi = lo + Int(ref.snippet.referenceLength)
        #expect(lo >= 0 && hi <= bytes.count)
        #expect(String(decoding: bytes[lo..<hi], as: UTF8.self) == "[[Target]]")
    }

    @Test("table-cell snippet scopes to the cell, not the whole table")
    func tableCellSnippetScopesToCell() throws {
        let source = "| left | right |\n| --- | --- |\n| see [[Target]] here | other |\n"
        let src = CambiumSource(source)
        let index = DocumentIndex.build(root: try LiminalParser().parse(src).rootSyntax, source: src)

        let ref = try #require(index.references.first { $0.target.rawTargetString == "Target" })
        // The snippet is the cell's content, not the entire table.
        #expect(ref.snippet.text.contains("[[Target]]"))
        #expect(!ref.snippet.text.contains("other"))
        #expect(!ref.snippet.text.contains("---"))
    }
}
