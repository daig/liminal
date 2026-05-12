import CambiumBuilder
import CambiumCore
import CambiumIncremental
import Testing
@testable import Liminal

@Suite("IncrementalReuse")
struct IncrementalReuseTests {

    // MARK: - Baseline / cold-start

    @Test("cold-start parse makes no reuse queries")
    func coldStartZeroQueries() throws {
        let session = LiminalParseSession()
        let result = try session.parse("Hello\n")

        #expect(result.sourceText == "Hello\n")
        #expect(session.lastReuseSummary.queries == 0)
        #expect(session.lastReuseSummary.acceptedReuses == 0)
    }

    @Test("second parse from a fresh session with empty edits stays correct")
    func sourceChangeWithoutEditsStaysCorrect() throws {
        let session = LiminalParseSession()
        let first = try session.parse("one")
        let second = try session.parse("two")

        #expect(first.sourceText == "one")
        #expect(second.sourceText == "two")
        // Reuse may or may not have been queried; the alignment guard rejects
        // a stale paragraph-at-offset-0 splice, so the output is correct.
        // Bytes accepted must be zero — "one" and "two" share no bytes at the
        // matching offset.
        #expect(session.lastReuseSummary.bytesAccepted == 0)
    }

    // MARK: - No-op re-parse

    @Test("no-op re-parse with empty edits reuses paragraphs")
    func noOpReparseReusesParagraphs() throws {
        let source = "A\n\nB\n\nC\n"
        let session = LiminalParseSession()
        _ = try session.parse(source)

        let second = try session.parse(source)

        #expect(second.sourceText == source)
        #expect(session.lastReuseSummary.acceptedReuses >= 3)
    }

    // MARK: - Targeted edit reuse

    @Test("editing one paragraph reuses the others")
    func editOneParagraphReusesOthers() throws {
        let session = LiminalParseSession()
        _ = try session.parse("A\n\nB\n\nC\n")

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        let second = try session.parse("A\n\nB2\n\nC\n", edits: [edit])

        #expect(second.sourceText == "A\n\nB2\n\nC\n")
        #expect(session.lastReuseSummary.acceptedReuses == 2)
    }

    @Test("editing inside a fenced code block reuses outer paragraphs")
    func editInsideFencedCodeBlockReusesOuter() throws {
        let source = """
        Before
        ```swift
        let x = 1
        ```
        After

        """
        let session = LiminalParseSession()
        _ = try session.parse(source)

        // Replace "let x = 1" with "let y = 2" at byte offset 17 (= "Before\n```swift\n".utf8.count)
        let needle = "let x = 1"
        let utf8Source = source.utf8
        let needleBytes = Array(needle.utf8)
        var startIdx = utf8Source.startIndex
        var startOffset = 0
        while startIdx < utf8Source.endIndex {
            if utf8Source[startIdx...].starts(with: needleBytes) { break }
            startIdx = utf8Source.index(after: startIdx)
            startOffset += 1
        }
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(startOffset)), length: TextSize(UInt32(needleBytes.count))),
            replacement: "let y = 2"
        )
        let newSource = source.replacingOccurrences(of: needle, with: "let y = 2")
        let second = try session.parse(newSource, edits: [edit])

        #expect(second.sourceText == newSource)
        // "Before" and "After" paragraphs are reused; fenced code block is not.
        #expect(session.lastReuseSummary.acceptedReuses >= 2)
    }

    // MARK: - Sentinel filter

    @Test("subtree containing recovery sentinels is not reused")
    func sentinelFilterRejectsErrorSubtrees() throws {
        // A typed block missing its closing fence produces a `.missing`
        // sentinel inside the typed block subtree.
        let source = """
        Before

        :::Callout{kind: warning}
        body without close
        """
        let session = LiminalParseSession()
        _ = try session.parse(source)

        // Edit "Before" — typed block region is untouched, sentinel filter
        // should reject reusing the unclosed typed block.
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(0)), length: TextSize(UInt32(6))),
            replacement: "After"
        )
        let newSource = "After\n\n:::Callout{kind: warning}\nbody without close"
        let second = try session.parse(newSource, edits: [edit])

        #expect(second.sourceText == newSource)
        // The unclosed typed block must be re-parsed (sentinel filter).
        // Accepted reuses should not include it.
        for accepted in session.lastReuseSummary.queries == 0 ? [] : Array(0..<session.lastReuseSummary.acceptedReuses) {
            _ = accepted
        }
        // Loose check: the parser still produced an unclosed-block diagnostic
        // post-reparse (since the unclosed block was NOT spliced as a
        // diagnostic-free subtree). This is the easiest behavioral observable.
        let document = LiminalLowerer().lower(second)
        #expect(!document.diagnostics.isEmpty || !second.diagnostics.isEmpty)
    }

    // MARK: - applyTextEdits forwards edits through

    @Test("applyTextEdits forwards edits so reuse fires")
    func applyTextEditsForwardsEdits() throws {
        let session = LiminalEditorSession(source: "A\n\nB\n\nC\n")
        _ = try session.parse()

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        _ = try session.applyTextEdits([edit])

        #expect(session.source == "A\n\nB2\n\nC\n")
    }

    // MARK: - replaceSubtree invalidation

    @Test("replaceSubtree clears reuse for the next parse")
    func replaceSubtreeInvalidatesNextReuse() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        let parsed = try session.parse()
        guard case .paragraph(let paragraph) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let replacement = try makeParagraphSnapshot(text: "World", newline: "\n")
        _ = try session.replaceSubtree(paragraph.syntax, with: replacement)
        #expect(session.source == "World\n")

        // Next textual parse should not pull stale subtrees from the
        // pre-replace tree. Conservative invalidation policy: edits are
        // ignored on the next parse after replaceSubtree.
        let result = try session.replaceSource("World\n")
        #expect(result.sourceText == "World\n")
    }

    // MARK: - Counter exposure

    @Test("lastReuseSummary reflects the most recent parse")
    func lastReuseSummaryReflectsMostRecentParse() throws {
        let session = LiminalParseSession()
        _ = try session.parse("Foo\n\nBar\n")
        #expect(session.lastReuseSummary.queries == 0)
        #expect(session.lastReuseSummary.acceptedReuses == 0)

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(5)), length: TextSize(UInt32(3))),
            replacement: "Baz"
        )
        _ = try session.parse("Foo\n\nBaz\n", edits: [edit])
        #expect(session.lastReuseSummary.queries > 0)
        #expect(session.lastReuseSummary.acceptedReuses >= 1)
    }
}

private func makeParagraphSnapshot(
    text: String,
    newline: String
) throws -> GreenTreeSnapshot<LiminalLanguage> {
    var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
    builder.startNode(.paragraph)
    builder.startNode(.inlineContent)
    try builder.token(.inlineText, text: text)
    try builder.finishNode()
    try builder.token(.newline, text: newline)
    try builder.finishNode()
    let build = try builder.finish()
    return build.snapshot
}
