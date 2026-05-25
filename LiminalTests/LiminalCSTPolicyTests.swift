import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

@Suite("LiminalCSTPolicy")
struct LiminalCSTPolicyTests {

    // MARK: - Wrapper-enum consistency (every wrapper kind is navigable)

    @Test("DocumentItemSyntax cases are all navigable per the policy")
    func documentItemKindsAreNavigable() {
        for kind in Self.documentItemKinds {
            #expect(
                LiminalCSTPolicy.isNavigable(kind),
                "DocumentItemSyntax case \(kind) should be navigable"
            )
        }
    }

    @Test("BlockSyntax cases are all navigable per the policy")
    func blockKindsAreNavigable() {
        for kind in Self.blockKinds {
            #expect(
                LiminalCSTPolicy.isNavigable(kind),
                "BlockSyntax case \(kind) should be navigable"
            )
        }
    }

    @Test("InlineSyntax cases are all navigable per the policy")
    func inlineKindsAreNavigable() {
        for kind in Self.inlineKinds {
            #expect(
                LiminalCSTPolicy.isNavigable(kind),
                "InlineSyntax case \(kind) should be navigable"
            )
        }
    }

    @Test("ValueSyntax cases are all navigable per the policy")
    func valueKindsAreNavigable() {
        for kind in Self.valueKinds {
            #expect(
                LiminalCSTPolicy.isNavigable(kind),
                "ValueSyntax case \(kind) should be navigable"
            )
        }
    }

    // MARK: - Navigation roles

    @Test("Former opaque blocks are now descendable stops")
    func formerOpaqueBlocksAreStops() {
        // `.opaque` is gone: code/math/HTML/comment/frontmatter blocks are
        // navigable stops you can descend into (to their payload token).
        let blocks: [LiminalKind] = [
            .fencedCodeBlock, .mathBlock, .htmlBlock,
            .commentBlock, .frontmatter,
        ]
        for block in blocks {
            #expect(
                LiminalCSTPolicy.navigationRole(block) == .stop,
                "\(block) should be a stop"
            )
        }
        // And their payload bodies are stops a descent can land on.
        for payload in [LiminalKind.codeText, .mathText, .commentText, .frontmatterText] {
            #expect(LiminalCSTPolicy.navigationRole(payload) == .stop)
        }
    }

    @Test("inlineContent is a passThrough wrapper; inline text is a stop")
    func inlineContentIsPassThrough() {
        #expect(LiminalCSTPolicy.navigationRole(.inlineContent) == .passThrough)
        #expect(LiminalCSTPolicy.navigationRole(.inlineText) == .stop)
    }

    @Test("Single-content wrappers are passThrough")
    func soleContentWrappersArePassThrough() {
        for wrapper in [LiminalKind.inlineContent, .scalarValue, .interpolationExpression] {
            #expect(
                LiminalCSTPolicy.navigationRole(wrapper) == .passThrough,
                "\(wrapper) should be passThrough"
            )
        }
    }

    @Test("Typical containers and inline wrappers are stops")
    func typicalContainersAreStops() {
        let stops: [LiminalKind] = [
            .root, .paragraph, .atxHeading, .list, .listItem,
            .blockQuote, .typedBlock, .pipeTable, .pipeTableRow, .pipeTableCell,
            // The inline wrappers that used to be skipped as "glue" are now
            // first-class stops — this is the fix for over-descent.
            .linkLabel, .linkDestination, .wikiTarget,
        ]
        for kind in stops {
            #expect(
                LiminalCSTPolicy.navigationRole(kind) == .stop,
                "\(kind) should be a stop"
            )
        }
    }

    // MARK: - Skip classification

    @Test("Trivia tokens are skipped")
    func triviaIsSkipped() {
        #expect(LiminalCSTPolicy.navigationRole(.whitespace) == .skip)
        #expect(LiminalCSTPolicy.navigationRole(.newline) == .skip)
        #expect(!LiminalCSTPolicy.isNavigable(.whitespace))
    }

    @Test("Punctuation / markers are skipped (framing)")
    func punctuationIsSkipped() {
        let punctuation: [LiminalKind] = [
            .atSign, .bang, .ampersand, .hash, .caret, .dollar,
            .leftBracket, .rightBracket, .leftParen, .rightParen,
            .leftBrace, .rightBrace, .lessThan, .greaterThan,
            .comma, .colon, .pipe, .backtick, .tilde, .star,
            .underscore, .dash, .plus, .dot, .slash, .backslash,
            .percent, .equals, .questionMark, .singleQuote,
            .doubleQuote, .semicolon,
            .hashRun, .colonRun, .fenceRun,
            .listMarker, .orderedListMarker, .taskMarker,
        ]
        for token in punctuation {
            #expect(
                LiminalCSTPolicy.navigationRole(token) == .skip,
                "\(token) should be skipped framing"
            )
        }
    }

    @Test("Breaks, the table delimiter row, and missing holes are skipped")
    func structuralFillerIsSkipped() {
        for kind in [LiminalKind.softBreak, .hardBreak, .pipeTableDelimiter, .missing] {
            #expect(
                LiminalCSTPolicy.navigationRole(kind) == .skip,
                "\(kind) should be skipped"
            )
        }
    }

    @Test("Payload text tokens are navigable stops")
    func payloadTokensAreStops() {
        // These were non-navigable in the old model; they are now the AST-leaf
        // content a descent lands on (a URL, a code body, a scalar).
        let payloads: [LiminalKind] = [
            .codeText, .mathText, .htmlText, .frontmatterText,
            .commentText, .rawPayloadText, .linkDestinationText,
            .wikiTargetText, .identifier, .qname, .integerLiteral,
        ]
        for payload in payloads {
            #expect(
                LiminalCSTPolicy.navigationRole(payload) == .stop,
                "\(payload) should be a stop"
            )
        }
    }

    // MARK: - Exhaustiveness via CaseIterable

    @Test("Every LiminalKind classifies (no compile-time gaps)")
    func everyKindClassifies() {
        // The compile-time exhaustive switch guarantees a result; this is the
        // runtime safety net against future drift.
        for kind in LiminalKind.allCases {
            _ = LiminalCSTPolicy.navigationRole(kind)
        }
    }

    // MARK: - cstVisualEntry

    @Test("cstVisualEntry inside inline text ascends to the block-level container")
    func cstVisualEntryAscendsToBlock() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello, world.\n"))
        let tree = parsed.tree
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: tree)
        )
        // Smallest-stop would have landed on the inline-text run; entry ascends
        // (through the inlineContent passThrough) to the enclosing paragraph.
        #expect(Self.focusedKind(forest) == .paragraph)
    }

    @Test("cstVisualEntry inside a fenced code block lands on the block itself")
    func cstVisualEntryOnFencedCodeBlock() throws {
        let source = "```swift\nlet x = 1\n```\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(10), in: tree)
        )
        // Entry ascends from the code payload to the block (a `.blockItem`).
        #expect(Self.focusedKind(forest) == .fencedCodeBlock)
    }

    @Test("cstVisualEntry at a block start after a blank line targets the downstream block")
    func cstVisualEntryAtBlockStartAfterBlankLineTargetsDownstreamBlock() throws {
        let source = "Paragraph.\n\n- item\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let offset = TextSize(UInt32(byteOffset(of: "- item", in: source)))
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: offset, in: tree)
        )
        #expect(Self.focusedKind(forest) == .listItem)
        #expect(forest.byteRange.start == offset)
    }

    @Test("cstVisualEntry at first list item content character targets paragraph content")
    func cstVisualEntryAtFirstListItemContentCharacterTargetsParagraph() throws {
        let source = "- foo\n  - bar\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let offset = TextSize(UInt32(byteOffset(of: "foo", in: source)))
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: offset, in: tree)
        )
        #expect(Self.focusedKind(forest) == .paragraph)
        #expect(forest.byteRange.start == offset)
    }

    @Test("cstVisualEntry returns nil for an empty document")
    func cstVisualEntryEmptyDocument() throws {
        let parsed = try LiminalParser().parse(CambiumSource(""))
        let tree = parsed.tree
        let forest = LiminalForest.cstVisualEntry(at: .zero, in: tree)
        #expect(forest == nil)
    }

    // MARK: - Helpers / spec sources

    private static func focusedKind(_ forest: LiminalForest) -> LiminalKind {
        forest.parent.withCursor {
            $0.green { green in green.child(at: forest.anchorChildIndex) }.kind
        }
    }

    /// Mirror of `DocumentItemSyntax`'s case list.
    private static let documentItemKinds: [LiminalKind] = [
        .blankLine, .frontmatter, .directive, .schemaBlock,
        .templateBlock, .paragraph, .atxHeading, .thematicBreak,
        .valueDeclaration, .typedBlock, .fencedCodeBlock, .mathBlock,
        .htmlBlock, .commentBlock, .list, .blockQuote, .pipeTable,
        .structuredEmbedBlock, .wikiEmbedBlock,
    ]

    /// Mirror of `BlockSyntax`'s case list.
    private static let blockKinds: [LiminalKind] = [
        .paragraph, .atxHeading, .thematicBreak, .typedBlock,
        .fencedCodeBlock, .mathBlock, .htmlBlock, .commentBlock,
        .list, .blockQuote, .pipeTable,
        .structuredEmbedBlock, .wikiEmbedBlock,
    ]

    /// Mirror of `InlineSyntax`'s case list.
    private static let inlineKinds: [LiminalKind] = [
        .codeSpan, .escapedPunctuation, .emphasis, .strong,
        .strikethrough, .highlight, .mdLink, .mdImage, .autolink,
        .wikilink, .wikiEmbed, .typedInline, .structuredEmbed,
        .mathInline, .interpolation, .inlineComment, .footnoteInline,
    ]

    /// Mirror of `ValueSyntax`'s case list.
    private static let valueKinds: [LiminalKind] = [
        .scalarValue, .listValue, .recordValue, .typedConstructor,
        .inlineLiteral, .blockLiteral, .reference, .structuredEmbedValue,
    ]

    private func byteOffset(of needle: String, in source: String) -> Int {
        guard let range = source.range(of: needle) else {
            Issue.record("Missing substring \(needle)")
            return 0
        }
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
    }
}
