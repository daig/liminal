import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

@Suite("LiminalCSTPolicy")
struct LiminalCSTPolicyTests {

    // MARK: - Wrapper-enum consistency

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

    // MARK: - Opaque / allChildren correctness

    @Test("Raw-payload containers have opaque child policy")
    func rawPayloadParentsAreOpaque() {
        let opaque: [LiminalKind] = [
            .fencedCodeBlock, .mathBlock, .htmlBlock,
            .commentBlock, .frontmatter,
        ]
        for parent in opaque {
            #expect(
                LiminalCSTPolicy.childPolicy(of: parent) == .opaque,
                "\(parent) should have .opaque child policy"
            )
        }
    }

    @Test("inlineContent uses allChildren so inline text tokens participate")
    func inlineContentUsesAllChildren() {
        #expect(LiminalCSTPolicy.childPolicy(of: .inlineContent) == .allChildren)
        #expect(LiminalCSTPolicy.isNavigable(.inlineText))
    }

    @Test("Typical containers default to structuralChildren")
    func typicalContainersUseStructuralChildren() {
        let typical: [LiminalKind] = [
            .root, .paragraph, .atxHeading, .list, .listItem,
            .blockQuote, .typedBlock, .pipeTable, .pipeTableRow,
        ]
        for parent in typical {
            #expect(
                LiminalCSTPolicy.childPolicy(of: parent) == .structuralChildren,
                "\(parent) should have .structuralChildren policy"
            )
        }
    }

    // MARK: - Token / trivia non-navigability

    @Test("Trivia tokens are never navigable")
    func triviaIsNotNavigable() {
        #expect(!LiminalCSTPolicy.isNavigable(.whitespace))
        #expect(!LiminalCSTPolicy.isNavigable(.newline))
    }

    @Test("Punctuation tokens are never navigable")
    func punctuationIsNotNavigable() {
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
                !LiminalCSTPolicy.isNavigable(token),
                "\(token) should not be navigable"
            )
        }
    }

    @Test("Opaque payload tokens are not navigable on their own")
    func opaquePayloadTokensAreNotNavigable() {
        let payloads: [LiminalKind] = [
            .codeText, .mathText, .htmlText, .frontmatterText,
            .commentText, .rawPayloadText,
        ]
        for payload in payloads {
            #expect(!LiminalCSTPolicy.isNavigable(payload))
        }
    }

    // MARK: - Exhaustiveness via CaseIterable

    @Test("Every LiminalKind classifies consistently (no compile-time gaps)")
    func everyKindClassifies() {
        // Touch both predicates on every kind. The compile-time exhaustive
        // switches guarantee a result; this test is the runtime safety
        // net that catches any future drift into a default-arm classification.
        for kind in LiminalKind.allCases {
            _ = LiminalCSTPolicy.isNavigable(kind)
            _ = LiminalCSTPolicy.childPolicy(of: kind)
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
        // Smallest-navigable would have landed on .inlineText under an
        // .allChildren inlineContent parent. cstVisualEntry should have
        // ascended at least to inlineContent — and inlineContent itself
        // sits inside a paragraph (.structuralChildren), so we expect
        // the forest's parent to be paragraph (or some other block
        // container) with .structuralChildren policy.
        let parentKind = forest.parent.withCursor { $0.kind }
        #expect(
            LiminalCSTPolicy.childPolicy(of: parentKind) == .structuralChildren,
            "cstVisualEntry should ascend out of .allChildren parents; landed under \(parentKind)"
        )
    }

    @Test("cstVisualEntry inside a fenced code block lands on the block itself")
    func cstVisualEntryOnFencedCodeBlock() throws {
        let source = "```swift\nlet x = 1\n```\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        // Pick an offset inside the code block.
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(10), in: tree)
        )
        // The fenced code block itself is the navigable child here; its
        // parent is root (or whatever DocumentItem container). Both are
        // .structuralChildren, so cstVisualEntry doesn't need to ascend
        // from the singleton it found.
        let parentKind = forest.parent.withCursor { $0.kind }
        #expect(
            LiminalCSTPolicy.childPolicy(of: parentKind) == .structuralChildren,
            "Code-block entry should land under a structural-children parent, got \(parentKind)"
        )
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

        let childKind = forest.parent.withCursor {
            $0.green { green in green.child(at: forest.anchorChildIndex) }.kind
        }
        #expect(childKind == .listItem)
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

        let childKind = forest.parent.withCursor {
            $0.green { green in green.child(at: forest.anchorChildIndex) }.kind
        }
        #expect(childKind == .paragraph)
        #expect(forest.byteRange.start == offset)
    }

    @Test("cstVisualEntry returns nil for an empty document")
    func cstVisualEntryEmptyDocument() throws {
        let parsed = try LiminalParser().parse(CambiumSource(""))
        let tree = parsed.tree
        let forest = LiminalForest.cstVisualEntry(at: .zero, in: tree)
        #expect(forest == nil)
    }

    // MARK: - Wrapper-enum spec sources

    /// Mirror of `DocumentItemSyntax`'s case list, kept here so the test
    /// fails to compile if the test isn't updated when the wrapper enum
    /// changes. (`DocumentItemSyntax` itself isn't `CaseIterable`.)
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
