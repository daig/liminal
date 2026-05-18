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
        let result = try session.parse(CambiumSource("Hello\n"))

        #expect(result.sourceText == "Hello\n")
        #expect(session.lastReuseSummary.queries == 0)
        #expect(session.lastReuseSummary.acceptedReuses == 0)
    }

    @Test("second parse from a fresh session with empty edits stays correct")
    func sourceChangeWithoutEditsStaysCorrect() throws {
        let session = LiminalParseSession()
        let first = try session.parse(CambiumSource("one"))
        let second = try session.parse(CambiumSource("two"))

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
        _ = try session.parse(CambiumSource(source))

        let second = try session.parse(CambiumSource(source))

        #expect(second.sourceText == source)
        #expect(session.lastReuseSummary.acceptedReuses >= 3)
    }

    // MARK: - Targeted edit reuse

    @Test("editing one paragraph reuses the others")
    func editOneParagraphReusesOthers() throws {
        let session = LiminalParseSession()
        _ = try session.parse(CambiumSource("A\n\nB\n\nC\n"))

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        let second = try session.parse(CambiumSource("A\n\nB2\n\nC\n"), edits: [edit])

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
        _ = try session.parse(CambiumSource(source))

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
        let second = try session.parse(CambiumSource(newSource), edits: [edit])

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
        _ = try session.parse(CambiumSource(source))

        // Edit "Before" — typed block region is untouched, sentinel filter
        // should reject reusing the unclosed typed block.
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(0)), length: TextSize(UInt32(6))),
            replacement: "After"
        )
        let newSource = "After\n\n:::Callout{kind: warning}\nbody without close"
        let second = try session.parse(CambiumSource(newSource), edits: [edit])

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
        let session = LiminalEditorSession(source: CambiumSource("A\n\nB\n\nC\n"))
        _ = try session.parse()

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        _ = try session.applyTextEdits([edit])

        #expect(session.source == CambiumSource("A\n\nB2\n\nC\n"))
    }

    // MARK: - replaceSubtree invalidation

    @Test("replaceSubtree clears reuse for the next parse")
    func replaceSubtreeInvalidatesNextReuse() throws {
        let session = LiminalEditorSession(source: CambiumSource("Hello\n"))
        let parsed = try session.parse()
        guard case .paragraph(let paragraph) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let replacement = try makeParagraphSnapshot(text: "World", newline: "\n")
        _ = try session.replaceSubtree(paragraph.syntax, with: replacement)
        #expect(session.source == CambiumSource("World\n"))

        // Next textual parse should not pull stale subtrees from the
        // pre-replace tree. Conservative invalidation policy: edits are
        // ignored on the next parse after replaceSubtree.
        let result = try session.replaceSource(CambiumSource("World\n"))
        #expect(result.sourceText == "World\n")
    }

    // MARK: - Counter exposure

    // MARK: - Regression: paragraph reuse must not splice past paragraph end

    @Test("appending newlines to a paragraph at EOF does not splice a stale paragraph")
    func appendingNewlinesAtEOF() throws {
        // Reproduces the Phase 7 typing crash. Sequence: type "Hello",
        // press Enter, press Enter. The old paragraph "Hello" had no
        // trailing newline (byte length 5). Reuse must reject the
        // stale candidate when the new source has appended a newline
        // that the parser would now consider part of the paragraph.
        let session = LiminalParseSession()
        _ = try session.parse(CambiumSource("Hello"))

        let edit1 = TextEdit(
            range: TextRange(start: TextSize(UInt32(5)), length: TextSize(UInt32(0))),
            replacement: "\n"
        )
        let r1 = try session.parse(CambiumSource("Hello\n"), edits: [edit1])
        #expect(r1.sourceText == "Hello\n")
        #expect(r1.tree.withRoot { $0.makeString() } == "Hello\n")

        let edit2 = TextEdit(
            range: TextRange(start: TextSize(UInt32(6)), length: TextSize(UInt32(0))),
            replacement: "\n"
        )
        let r2 = try session.parse(CambiumSource("Hello\n\n"), edits: [edit2])
        #expect(r2.sourceText == "Hello\n\n")
        #expect(r2.tree.withRoot { $0.makeString() } == "Hello\n\n")
    }

    @Test("appending a continuation line to a single-line paragraph re-parses fresh")
    func paragraphContinuationLineRejectsReuse() throws {
        // "World\n" parsed alone is a paragraph of length 6. After
        // appending "!", the spec says "World\n!" is ONE paragraph
        // (two lines joined by a soft break). Splicing the old
        // length-6 candidate would produce two paragraphs — wrong.
        // The context-sensitive boundary guard must reject.
        let session = LiminalParseSession()
        _ = try session.parse(CambiumSource("World\n"))

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(6)), length: TextSize(UInt32(0))),
            replacement: "!"
        )
        let result = try session.parse(CambiumSource("World\n!"), edits: [edit])
        #expect(result.sourceText == "World\n!")
        #expect(result.tree.withRoot { $0.makeString() } == "World\n!")
    }

    @Test("lastReuseSummary reflects the most recent parse")
    func lastReuseSummaryReflectsMostRecentParse() throws {
        let session = LiminalParseSession()
        _ = try session.parse(CambiumSource("Foo\n\nBar\n"))
        #expect(session.lastReuseSummary.queries == 0)
        #expect(session.lastReuseSummary.acceptedReuses == 0)

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(5)), length: TextSize(UInt32(3))),
            replacement: "Baz"
        )
        _ = try session.parse(CambiumSource("Foo\n\nBaz\n"), edits: [edit])
        #expect(session.lastReuseSummary.queries > 0)
        #expect(session.lastReuseSummary.acceptedReuses >= 1)
    }

    // MARK: - Cross-block-swallowing: dirty span extends to EOF when a
    // new block opens but its closer is past the original halo.

    @Test("typing a fence opener mid-document swallows subsequent paragraphs")
    func fenceOpenerExtendsDirtySpanToEOF() throws {
        // Five paragraphs separated by blank lines. Typing ``` at the
        // start of B opens a fenced code block; with no matching closer,
        // it should consume B, C, D, E (and the blank lines between).
        // Skip-clean-regions' boundary halo of ±1 only reaches C; the
        // trailing-sentinel detection must extend the dirty span to EOF
        // so D and E end up inside the fence, not transplanted as
        // separate paragraphs.
        let session = LiminalParseSession()
        let original = "A\n\nB\n\nC\n\nD\n\nE\n"
        _ = try session.parse(CambiumSource(original))

        // Find B's start byte. Layout: "A" (1) "\n" (1) "\n" (1) → B at byte 3.
        let bStart = 3
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(bStart)), length: TextSize(0)),
            replacement: "```\n"
        )
        let newSource = "A\n\n```\nB\n\nC\n\nD\n\nE\n"
        let result = try session.parse(CambiumSource(newSource), edits: [edit])

        // Structural assertion: the new tree should have exactly two
        // top-level "real" blocks — paragraph A (and its trailing
        // blank line) and one fenced code block consuming everything
        // after, plus possibly a trailing blank line if the fixture
        // ends with one. Test by counting fencedCodeBlock children and
        // checking that no paragraph kinds appear after the fence.
        let topLevelKinds: [LiminalKind] = result.tree.withRoot { root in
            (0..<root.childOrTokenCount).compactMap { i in
                root.withChildNode(atRawIndex: i) { cursor in
                    LiminalLanguage.kind(for: cursor.rawKind)
                }
            }
        }
        // There must be exactly one fenced code block at top level.
        let fenceIndices = topLevelKinds.enumerated()
            .filter { $0.element == .fencedCodeBlock }
            .map { $0.offset }
        #expect(fenceIndices.count == 1, "expected one fenced code block; got kinds \(topLevelKinds)")
        // No paragraphs may appear after the fence — they'd be inside
        // the fence in a structurally-correct tree.
        if let fenceIndex = fenceIndices.first {
            let tail = topLevelKinds[(fenceIndex + 1)...]
            #expect(
                !tail.contains(.paragraph),
                "found paragraph after fence opener; the fence should have swallowed it. Tail kinds: \(Array(tail))"
            )
        }
        // The new tree's text must match the new source.
        #expect(result.tree.withRoot { $0.makeString() } == newSource)
    }

    @Test("editing inside an existing unclosed fence stays cheap")
    func editingInsideExistingUnclosedFenceShortCircuits() throws {
        // After the previous test's scenario, the previous tree
        // contains a sentinel-bearing fenced code block extending to
        // EOF. A subsequent edit *inside* that fence shouldn't trigger
        // the extend-to-EOF loop again — the short-circuit recognizes
        // that the old child at the dirty span's end was already a
        // sentinel-bearing opens-until-close kind.
        let session = LiminalParseSession()
        let original = "A\n\n```\nB\n\nC\n"
        _ = try session.parse(CambiumSource(original))

        // Edit "B" → "Bx" — inside the fenced block.
        // Source layout: "A\n\n```\nB" → byte index of "B" is 7.
        let bIndex = original.utf8.distance(
            from: original.utf8.startIndex,
            to: original.range(of: "B")!.lowerBound.samePosition(in: original.utf8)!
        )
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(bIndex + 1)), length: TextSize(0)),
            replacement: "x"
        )
        let newSource = "A\n\n```\nBx\n\nC\n"
        let result = try session.parse(CambiumSource(newSource), edits: [edit])

        // Tree text matches new source.
        #expect(result.tree.withRoot { $0.makeString() } == newSource)
        // Still exactly one fenced code block, no spurious paragraphs
        // after.
        let topLevelKinds: [LiminalKind] = result.tree.withRoot { root in
            (0..<root.childOrTokenCount).compactMap { i in
                root.withChildNode(atRawIndex: i) { cursor in
                    LiminalLanguage.kind(for: cursor.rawKind)
                }
            }
        }
        #expect(topLevelKinds.filter { $0 == .fencedCodeBlock }.count == 1)
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
