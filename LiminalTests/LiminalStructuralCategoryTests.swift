import CambiumCore
import Testing
@testable import Liminal

@Suite("LiminalStructuralCategory")
struct LiminalStructuralCategoryTests {

    // MARK: - Exhaustiveness

    @Test("Every LiminalKind classifies without crashing")
    func everyKindClassifies() {
        // The compile-time switch enforces totality; this is the runtime
        // safety net against a future drift to a default-arm classification.
        for kind in LiminalKind.allCases {
            _ = LiminalStructuralCategory.categories(of: kind)
        }
    }

    // MARK: - Token-level classifications

    @Test("Trivia tokens are exactly `.trivia`")
    func triviaKinds() {
        for kind in Self.triviaKinds {
            #expect(kind.categories == .trivia, "\(kind) should be exactly .trivia")
        }
    }

    @Test("Punctuation / marker tokens are exactly `.punctuation`")
    func punctuationKinds() {
        for kind in Self.punctuationKinds {
            #expect(kind.categories == .punctuation, "\(kind) should be exactly .punctuation")
        }
    }

    @Test("Payload text tokens are exactly `.payloadText`")
    func payloadTextKinds() {
        for kind in Self.payloadTextKinds {
            #expect(kind.categories == .payloadText, "\(kind) should be exactly .payloadText")
        }
    }

    @Test("Identifier / literal sub-tokens have no category")
    func subTokenKindsAreEmpty() {
        let subTokens: [LiminalKind] = [
            .identifier, .qname, .anchor, .fieldName,
            .quotedStringLiteral, .integerLiteral, .numberLiteral,
            .booleanLiteral, .nullLiteral, .bareScalarLiteral,
        ]
        for kind in subTokens {
            #expect(kind.categories.isEmpty, "\(kind) should have an empty category set")
        }
    }

    @Test("inlineText is exactly `.inlineUnit`")
    func inlineTextIsInlineUnit() {
        #expect(LiminalKind.inlineText.categories == .inlineUnit)
    }

    // MARK: - Heading / listy / table / emphasis

    @Test("Heading kinds")
    func headingKinds() {
        #expect(LiminalKind.atxHeading.categories == [.blockItem, .heading])
    }

    @Test("Listy kinds")
    func listyKinds() {
        #expect(LiminalKind.list.categories == [.blockItem, .listy])
        #expect(LiminalKind.listItem.categories == [.blockItem, .blockContainer, .listy])
    }

    @Test("Block-container overlap with blockItem")
    func blockContainerOverlap() {
        // root is a container only — not a sibling of anything.
        #expect(LiminalKind.root.categories == .blockContainer)
        // listItem / blockQuote / typedBlock are BOTH sibling and container.
        for kind in [LiminalKind.listItem, .blockQuote, .typedBlock] {
            let cats = kind.categories
            #expect(cats.contains(.blockItem), "\(kind) should be .blockItem")
            #expect(cats.contains(.blockContainer), "\(kind) should be .blockContainer")
        }
    }

    @Test("Table family — pipeTable is blockItem, inner kinds are table-only")
    func tableFamilyMembership() {
        #expect(LiminalKind.pipeTable.categories == [.blockItem, .table])
        let inner: [LiminalKind] = [
            .pipeTableHeader, .pipeTableDelimiter, .pipeTableRow, .pipeTableCell,
        ]
        for kind in inner {
            #expect(kind.categories == .table, "\(kind) should be exactly .table (not .blockItem)")
        }
    }

    @Test("Emphasis family")
    func emphasisFamilyMembership() {
        for kind in [LiminalKind.emphasis, .strong, .strikethrough, .highlight] {
            #expect(
                kind.categories == [.inlineUnit, .emphasis],
                "\(kind) should be exactly [.inlineUnit, .emphasis]"
            )
        }
    }

    // MARK: - Reference family

    @Test("Reference-family kinds get the right link/embed/wikilink split")
    func referenceFamilyMembership() {
        // mdLink: link, not embed
        #expect(LiminalKind.mdLink.categories == [.inlineUnit, .reference, .link])
        // mdImage: embed, NOT link (despite the markdown-syntactic similarity)
        #expect(LiminalKind.mdImage.categories == [.inlineUnit, .reference, .embed])
        // autolink: link
        #expect(LiminalKind.autolink.categories == [.inlineUnit, .reference, .link])
        // wikilink: its own atom, NOT in .link
        #expect(LiminalKind.wikilink.categories == [.inlineUnit, .reference, .wikilinkRef])
        // wikiEmbed (inline) and structuredEmbed (inline): embed
        #expect(LiminalKind.wikiEmbed.categories == [.inlineUnit, .reference, .embed])
        #expect(LiminalKind.structuredEmbed.categories == [.inlineUnit, .reference, .embed])
        // Block-level embeds: also blockItem + blockContainer
        #expect(
            LiminalKind.wikiEmbedBlock.categories ==
                [.blockItem, .blockContainer, .reference, .embed]
        )
        #expect(
            LiminalKind.structuredEmbedBlock.categories ==
                [.blockItem, .blockContainer, .reference, .embed]
        )
        // footnoteInline: reference + footnote
        #expect(
            LiminalKind.footnoteInline.categories ==
                [.inlineUnit, .reference, .footnote]
        )
        // interpolation: reference (binding-like), no link/embed atoms
        #expect(LiminalKind.interpolation.categories == [.inlineUnit, .reference])
        // value-level reference / externalReference: pure reference
        #expect(LiminalKind.reference.categories == .reference)
        #expect(LiminalKind.externalReference.categories == .reference)
    }

    // MARK: - Typed / literal family

    @Test("Typed-family kinds")
    func typedFamilyMembership() {
        #expect(LiminalKind.typedBlock.categories == [.blockItem, .blockContainer, .typed])
        #expect(LiminalKind.typedInline.categories == [.inlineUnit, .typed])
        #expect(LiminalKind.valueDeclaration.categories == [.blockItem, .typed])
        #expect(LiminalKind.useDirective.categories == [.blockItem, .directive, .typed])
        #expect(LiminalKind.inlineLiteral.categories == [.literal, .typed, .inlineUnit])
        #expect(LiminalKind.blockLiteral.categories == [.literal, .typed, .blockItem])
        // field is a real declaration, not glue
        #expect(LiminalKind.field.categories == .typed)
    }

    // MARK: - Schema / template family

    @Test("Schema / template family")
    func schemaTemplateMembership() {
        #expect(
            LiminalKind.schemaBlock.categories ==
                [.blockItem, .blockContainer, .typed, .schema]
        )
        #expect(LiminalKind.schemaBody.categories == [.glueWrapper, .schema])
        // schemaModifier is a real declaration — NOT a glue wrapper
        #expect(LiminalKind.schemaModifier.categories == [.schema, .typed])
        #expect(
            LiminalKind.templateBlock.categories ==
                [.blockItem, .blockContainer, .typed, .template]
        )
        #expect(LiminalKind.templateBody.categories == [.glueWrapper, .template])
        // templateSignature wraps signature glue — both .template and .glueWrapper
        #expect(
            LiminalKind.templateSignature.categories ==
                [.template, .typed, .glueWrapper]
        )
    }

    // MARK: - Recovery sentinels

    @Test("Recovery sentinels")
    func recoverySentinels() {
        #expect(LiminalKind.missing.categories == .recovery)
        #expect(LiminalKind.error.categories == .recovery)
    }

    // MARK: - Parity with existing classifiers

    @Test("`.glueWrapper` is a superset of the existing cstVisualEntry glue set")
    func glueWrapperParity() {
        // Every kind in the existing isCSTStructuralGlueWrapper set must
        // also be in `.glueWrapper`. (The new set is intentionally wider —
        // it adds link/wiki/template inner wrappers — so this is a one-way
        // parity check, not equality.)
        for kind in Self.existingGlueWrapperKinds {
            #expect(
                kind.categories.contains(.glueWrapper),
                "\(kind) was in isCSTStructuralGlueWrapper; must be in .glueWrapper"
            )
        }
    }

    @Test("Every DocumentItemSyntax kind is `.blockItem`")
    func documentItemKindParity() {
        for kind in Self.documentItemKinds {
            #expect(
                kind.categories.contains(.blockItem),
                "DocumentItemSyntax case \(kind) should be .blockItem"
            )
        }
    }

    @Test("Every InlineSyntax kind is `.inlineUnit`")
    func inlineSyntaxKindParity() {
        for kind in Self.inlineKinds {
            #expect(
                kind.categories.contains(.inlineUnit),
                "InlineSyntax case \(kind) should be .inlineUnit"
            )
        }
    }

    // MARK: - Task-list-item predicate

    @Test("isTaskListItem distinguishes task items from plain list items")
    func taskListItemPredicate() throws {
        let parsed = try LiminalParser().parse(CambiumSource("- [ ] todo\n- regular\n"))
        let tree = parsed.tree

        var listItemHandles: [SyntaxNodeHandle<LiminalLanguage>] = []
        tree.withRoot { root in
            _ = root.visitPreorder { node in
                if node.kind == .listItem {
                    listItemHandles.append(node.makeHandle())
                }
                return .continue
            }
        }

        try #require(listItemHandles.count == 2)
        #expect(
            LiminalStructuralCategory.isTaskListItem(listItemHandles[0]),
            "First list item is a task; predicate should return true"
        )
        #expect(
            !LiminalStructuralCategory.isTaskListItem(listItemHandles[1]),
            "Second list item is plain; predicate should return false"
        )
    }

    @Test("isTaskListItem returns false for non-listItem handles")
    func taskListItemPredicateRejectsOtherKinds() throws {
        let parsed = try LiminalParser().parse(CambiumSource("# Heading\n"))
        let tree = parsed.tree

        var headingHandle: SyntaxNodeHandle<LiminalLanguage>?
        tree.withRoot { root in
            _ = root.visitPreorder { node in
                if node.kind == .atxHeading {
                    headingHandle = node.makeHandle()
                    return .stop
                }
                return .continue
            }
        }
        let handle = try #require(headingHandle)
        #expect(!LiminalStructuralCategory.isTaskListItem(handle))
    }

    // MARK: - Mirror kind lists

    /// Mirror of LiminalCSTPolicy's first non-navigable stanza (trivia).
    private static let triviaKinds: [LiminalKind] = [.whitespace, .newline]

    /// Mirror of LiminalCSTPolicy's punctuation stanza (the 32 @StaticText
    /// tokens plus structural markers).
    private static let punctuationKinds: [LiminalKind] = [
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

    /// Mirror of LiminalCSTPolicy's payload-text stanza.
    private static let payloadTextKinds: [LiminalKind] = [
        .codeText, .mathText, .htmlText, .frontmatterText,
        .commentText, .rawPayloadText,
        .linkDestinationText, .linkTitleText,
        .wikiTargetText, .embedTargetText,
        .interpolationText, .externalReferenceText,
        .schemaText, .templateText, .directiveText, .errorText,
    ]

    /// Mirror of the existing `isCSTStructuralGlueWrapper` set in
    /// LiminalCSTPolicy.swift. Parity-test target: the new `.glueWrapper`
    /// category must include every member of this set.
    private static let existingGlueWrapperKinds: [LiminalKind] = [
        .inlineContent, .fields, .value,
        .listValue, .recordValue, .scalarValue,
        .schemaBody, .templateBody, .typedConstructor,
    ]

    /// Mirror of `DocumentItemSyntax`'s case list (copied from
    /// `LiminalCSTPolicyTests` for consistency).
    private static let documentItemKinds: [LiminalKind] = [
        .blankLine, .frontmatter, .directive, .schemaBlock,
        .templateBlock, .paragraph, .atxHeading, .thematicBreak,
        .valueDeclaration, .typedBlock, .fencedCodeBlock, .mathBlock,
        .htmlBlock, .commentBlock, .list, .blockQuote, .pipeTable,
        .structuredEmbedBlock, .wikiEmbedBlock,
    ]

    /// Mirror of `InlineSyntax`'s case list.
    private static let inlineKinds: [LiminalKind] = [
        .codeSpan, .escapedPunctuation, .emphasis, .strong,
        .strikethrough, .highlight, .mdLink, .mdImage, .autolink,
        .wikilink, .wikiEmbed, .typedInline, .structuredEmbed,
        .mathInline, .interpolation, .inlineComment, .footnoteInline,
    ]
}
