import CambiumCore
import Testing
@testable import Liminal

@Suite("Highlight dirty spans")
struct HighlightDirtySpanTests {
    @Test("paragraph repaint scope includes its parser halo but not the next paragraph")
    func paragraphScopeIncludesHalo() throws {
        let source = "one\n\ntwo\n"
        let ranges = try expandedRanges(in: source, seed: byteRange(of: "one", in: source))
        let text = joinedSlices(source: source, ranges: ranges)

        #expect(text.contains("one"))
        #expect(!text.contains("two"))
    }

    @Test("blank-line repaint scope includes both neighboring paragraphs")
    func blankLineScopeIncludesNeighbors() throws {
        let source = "one\n\ntwo\n"
        let blankStart = byteOffset(of: "\n\n", in: source) + 1
        let seed = TextRange(
            start: TextSize(UInt32(blankStart)),
            length: TextSize(1)
        )
        let ranges = try expandedRanges(in: source, seed: seed)
        let text = joinedSlices(source: source, ranges: ranges)

        #expect(text.contains("one"))
        #expect(text.contains("two"))
    }

    @Test("self-delimited fenced block repaint does not include neighbor blocks")
    func fencedBlockScopeDoesNotIncludeNeighbors() throws {
        let source = "before\n\n```swift\nlet x = 1\n```\n\nafter\n"
        let ranges = try expandedRanges(in: source, seed: byteRange(of: "let x", in: source))
        let text = joinedSlices(source: source, ranges: ranges)

        #expect(text.contains("let x"))
        #expect(!text.contains("before"))
        #expect(!text.contains("after"))
    }

    @Test("separate repaint seeds stay separate when their expanded scopes do not touch")
    func separateScopesStaySeparate() throws {
        let source = "first\n\n```swift\nlet x = 1\n```\n\nlast\n"
        let firstSeed = byteRange(of: "first", in: source)
        let lastSeed = byteRange(of: "last", in: source)
        let session = LiminalEditorSession(source: CambiumSource(source))
        let parsed = try session.parse()
        let ranges = LiminalDirtySpan.expandedHighlightRanges(
            root: parsed.rootSyntax,
            touching: [firstSeed, lastSeed]
        )

        #expect(ranges.count == 2)
        #expect(joinedSlices(source: source, ranges: ranges).contains("first"))
        #expect(joinedSlices(source: source, ranges: ranges).contains("last"))
    }
}

private func expandedRanges(in source: String, seed: TextRange) throws -> [TextRange] {
    let session = LiminalEditorSession(source: CambiumSource(source))
    let parsed = try session.parse()
    return LiminalDirtySpan.expandedHighlightRanges(
        root: parsed.rootSyntax,
        touching: [seed]
    )
}

private func byteRange(of needle: String, in source: String) -> TextRange {
    let start = byteOffset(of: needle, in: source)
    return TextRange(
        start: TextSize(UInt32(start)),
        length: TextSize(UInt32(needle.utf8.count))
    )
}

private func byteOffset(of needle: String, in source: String) -> Int {
    guard let range = source.range(of: needle) else {
        preconditionFailure("Missing test fixture substring: \(needle)")
    }
    return source[..<range.lowerBound].utf8.count
}

private func joinedSlices(source: String, ranges: [TextRange]) -> String {
    ranges.map { range in
        let start = Int(range.start.rawValue)
        let end = Int(range.end.rawValue)
        let bytes = Array(source.utf8)[start..<end]
        return String(decoding: bytes, as: UTF8.self)
    }.joined(separator: "|")
}
