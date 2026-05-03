import CambiumCore
import Testing
@testable import Liminal

@Suite("Syntax")
struct SyntaxTests {
    @Test("syntax kinds use stable Phase 0 raw bands")
    func syntaxKindRawBandsAreStable() {
        #expect(LiminalLanguage.serializationVersion == 3)

        #expect(LiminalKind.whitespace.rawValue == 1)
        #expect(LiminalKind.newline.rawValue == 2)

        #expect(LiminalKind.atSign.rawValue == 10)
        #expect(LiminalKind.semicolon.rawValue == 41)
        #expect(LiminalKind.rawPayloadText.rawValue == 72)
        #expect(LiminalKind.errorText.rawValue == 82)

        #expect(LiminalKind.root.rawValue == 100)
        #expect(LiminalKind.atxHeading.rawValue == 106)
        #expect(LiminalKind.typedBlock.rawValue == 115)

        #expect(LiminalKind.inlineContent.rawValue == 200)
        #expect(LiminalKind.mdLink.rawValue == 209)
        #expect(LiminalKind.wikiEmbed.rawValue == 213)

        #expect(LiminalKind.value.rawValue == 300)
        #expect(LiminalKind.schemaBlock.rawValue == 312)
        #expect(LiminalKind.templateBlock.rawValue == 319)

        #expect(LiminalKind.missing.rawValue == 900)
        #expect(LiminalKind.error.rawValue == 901)
    }

    @Test("syntax kinds satisfy Cambium language classification")
    func kindClassificationUsesCambiumLanguageContract() {
        #expect(LiminalLanguage.isTrivia(.whitespace))
        #expect(LiminalLanguage.isTrivia(.newline))
        #expect(!LiminalLanguage.isTrivia(.commentBlock))
        #expect(!LiminalLanguage.isTrivia(.commentText))

        #expect(LiminalLanguage.isNode(.root))
        #expect(LiminalLanguage.isNode(.paragraph))
        #expect(LiminalLanguage.isNode(.mdLink))
        #expect(LiminalLanguage.isNode(.schemaBlock))
        #expect(LiminalLanguage.isNode(.missing))
        #expect(LiminalLanguage.isNode(.error))

        #expect(LiminalLanguage.isToken(.rawPayloadText))
        #expect(LiminalLanguage.isToken(.errorText))
        #expect(LiminalLanguage.isToken(.qname))
        #expect(LiminalLanguage.isToken(.commentText))
        #expect(!LiminalLanguage.isToken(.root))

        #expect(LiminalLanguage.name(for: .rawPayloadText) == "rawPayloadText")
        #expect(LiminalLanguage.name(for: .errorText) == "errorText")
        #expect(LiminalLanguage.kind(for: RawSyntaxKind(100)) == .root)
        #expect(LiminalLanguage.kind(for: RawSyntaxKind(900)) == .missing)
    }

    @Test("static punctuation and dynamic text token contracts are pinned")
    func staticAndDynamicTokenContractsArePinned() {
        #expect(string(for: LiminalLanguage.staticText(for: .atSign)) == "@")
        #expect(string(for: LiminalLanguage.staticText(for: .leftBracket)) == "[")
        #expect(string(for: LiminalLanguage.staticText(for: .rightParen)) == ")")
        #expect(string(for: LiminalLanguage.staticText(for: .backslash)) == "\\")
        #expect(string(for: LiminalLanguage.staticText(for: .doubleQuote)) == "\"")
        #expect(string(for: LiminalLanguage.staticText(for: .semicolon)) == ";")

        #expect(LiminalLanguage.staticText(for: .whitespace) == nil)
        #expect(LiminalLanguage.staticText(for: .qname) == nil)
        #expect(LiminalLanguage.staticText(for: .rawPayloadText) == nil)
        #expect(LiminalLanguage.staticText(for: .errorText) == nil)
        #expect(LiminalLanguage.staticText(for: .commentText) == nil)
    }

    @Test(
        "parser preserves source bytes in the Cambium root tree",
        arguments: [
            ParseExpectation(description: "empty source", source: "", rootChildKinds: []),
            ParseExpectation(description: "single line ASCII", source: "plain text", rootChildKinds: [.paragraph]),
            ParseExpectation(
                description: "multiline source",
                source: "First paragraph\n\nSecond paragraph\n",
                rootChildKinds: [.paragraph, .blankLine, .paragraph]
            ),
            ParseExpectation(
                description: "unicode source",
                source: "Body with unicode: λ, 文字, and emoji: 🧠\n",
                rootChildKinds: [.paragraph]
            ),
            ParseExpectation(
                description: "markdown-like source",
                source: "# Typed documents\n\n- [[Note#Heading]]\n- `code`\n",
                rootChildKinds: [.atxHeading, .blankLine, .paragraph]
            )
        ]
    )
    func parserBuildsLosslessRootTree(_ expectation: ParseExpectation) throws {
        let result = try LiminalParser().parse(expectation.source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == expectation.source)

        let byteLength = try TextSize(byteCountOf: expectation.source)
        result.tree.withRoot { root in
            #expect(root.kind == .root)
            #expect(root.textLength == byteLength)

            var childKinds: [LiminalKind] = []
            root.forEachChild { child in
                childKinds.append(child.kind)
            }

            #expect(childKinds == expectation.rootChildKinds)
        }
    }

    @Test("typed root overlay wraps the parsed Cambium root")
    func typedRootOverlayWrapsParsedCambiumRoot() throws {
        let source = "# Typed documents\n\nBody with unicode: λ\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax
        let byteLength = try TextSize(byteCountOf: source)

        #expect(RootSyntax.kind == .root)
        #expect(root.sourceText == source)
        #expect(root.range == TextRange(start: .zero, length: byteLength))
        #expect(RootSyntax(result.tree.rootHandle())?.syntax == root.syntax)
    }

    @Test("typed root overlay exposes Slice 1 document items")
    func typedRootOverlayExposesSlice1DocumentItems() throws {
        let source = "plain `code` and [[Target|Alias]]\n![[Embed#Heading|payload]]\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(root.documentItems.count == 2)
        #expect(root.tokens.isEmpty)
        #expect(root.rawPayloadToken == nil)

        guard case .paragraph(let paragraph) = root.documentItems[0] else {
            Issue.record("expected paragraph")
            return
        }
        let inlineContent = try #require(paragraph.inlineContent)
        #expect(inlineContent.inlineNodes.map(\.range).count == 2)

        guard case .wikiEmbedBlock(let embed) = root.documentItems[1] else {
            Issue.record("expected wiki embed block")
            return
        }
        #expect(embed.targetText == "Embed#Heading")
        #expect(embed.payloadText == "payload")
    }

    @Test("markdown links and images expose CST title tokens")
    func markdownLinksAndImagesExposeCSTTitleTokens() throws {
        let source = #"See [site]( https://example.org "Title" ) and ![Alt](image.png 'Caption')."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes,
              inlineNodes.count == 2,
              case .mdLink(let link) = inlineNodes[0],
              case .mdImage(let image) = inlineNodes[1]
        else {
            Issue.record("expected markdown link and image nodes")
            return
        }

        #expect(link.destinationText == "https://example.org")
        #expect(link.titleText == "Title")
        #expect(image.destinationText == "image.png")
        #expect(image.titleText == "Caption")
    }

    @Test("reference target accessors expose direct CST tokens and ranges")
    func referenceTargetAccessorsExposeDirectCSTTokensAndRanges() throws {
        let source = #"See [[Target|Alias]] and [site](https://example.org "Title")."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes,
              inlineNodes.count == 2,
              case .wikilink(let wikilink) = inlineNodes[0],
              case .mdLink(let link) = inlineNodes[1]
        else {
            Issue.record("expected wikilink and markdown link nodes")
            return
        }

        #expect(wikilink.targetTextToken?.text == "Target")
        let wikilinkTargetRange = try sourceRange(of: "Target", in: source)
        #expect(wikilink.targetTextToken?.range == wikilinkTargetRange)
        #expect(link.destinationTextToken?.text == "https://example.org")
        let linkDestinationRange = try sourceRange(of: "https://example.org", in: source)
        #expect(link.destinationTextToken?.range == linkDestinationRange)
        #expect(link.titleTextToken?.text == "Title")
    }

    @Test("inline content plaintext projection follows CST inline semantics")
    func inlineContentPlainTextProjectionFollowsCSTInlineSemantics() throws {
        #expect(try paragraphPlainText("Plain text\n") == "Plain text")
        #expect(try paragraphPlainText("Use `code`\n") == "Use code")
        #expect(try paragraphPlainText("a\nb\\\nc\n") == "a b\nc")
        #expect(try paragraphPlainText("[[Target|Alias]] and [[Solo]]\n") == "Alias and Solo")
        #expect(try paragraphPlainText("![Alt](image.png)\n") == "Alt")
        #expect(try paragraphPlainText("See @Badge[Label]\n") == "See Label")
        #expect(try paragraphPlainText("[[Target|See `code`]]\n") == "See code")
    }

    @Test("escaped punctuation is represented by explicit CST nodes")
    func escapedPunctuationIsRepresentedByExplicitCSTNodes() throws {
        let source = #"Escaped \*literal\* and \[bracket\]."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes
        else {
            Issue.record("expected paragraph")
            return
        }

        let escapedText = inlineNodes.compactMap { inline -> String? in
            guard case .escapedPunctuation(let punctuation) = inline else {
                return nil
            }
            return punctuation.escapedText
        }
        #expect(escapedText == ["*", "*", "[", "]"])
    }

    @Test("Slice 2 parser emits generic typed and value document items losslessly")
    func slice2ParserEmitsGenericTypedAndValueDocumentItemsLosslessly() throws {
        let source = """
        @Person#ada{name: "Ada", born: 1815-12-10}[Ada]

        :::Callout#warning{kind: warning}
        Body [[Note]]
        :::

        !{Person}[Ada](#ada)

        :::MathBlock
        E = mc^2
        :::
        :::HtmlBlock
        <div>raw</div>
        :::
        """
        let result = try LiminalParser().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)

        result.tree.withRoot { root in
            var childKinds: [LiminalKind] = []
            root.forEachChild { child in
                childKinds.append(child.kind)
            }

            #expect(childKinds == [
                .valueDeclaration,
                .blankLine,
                .typedBlock,
                .blankLine,
                .structuredEmbedBlock,
                .blankLine,
                .mathBlock,
                .htmlBlock
            ])
        }
    }

    @Test("typed root overlay exposes Slice 2 constructs")
    func typedRootOverlayExposesSlice2Constructs() throws {
        let source = """
        @Person#ada{name: "Ada"}[Ada]
        :::Callout#warning{kind: warning}
        Body
        :::
        !{Person}[Ada](#ada)
        """
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .valueDeclaration(let declaration) = root.documentItems[0],
              let constructor = declaration.constructor
        else {
            Issue.record("expected value declaration")
            return
        }
        #expect(constructor.typeName == "Person")
        #expect(constructor.idText == "ada")
        #expect(constructor.fields?.fields.map(\.name) == ["name"])
        #expect(constructor.inlineContent?.sourceText == "Ada")

        guard case .typedBlock(let block) = root.documentItems[1] else {
            Issue.record("expected typed block")
            return
        }
        #expect(block.typeName == "Callout")
        #expect(block.idText == "warning")
        #expect(block.fields?.fields.map(\.name) == ["kind"])
        #expect(block.documentItems.count == 1)

        guard case .structuredEmbedBlock(let embed) = root.documentItems[2] else {
            Issue.record("expected structured embed block")
            return
        }
        #expect(embed.expectedType == "Person")
        #expect(embed.fallbackContent?.sourceText == "Ada")
        #expect(embed.targetText == "#ada")
    }

    @Test("typed dispatch points accept emitted Slice 1 nodes and reject root")
    func typedDispatchPointsAcceptEmittedSlice1NodesAndRejectRoot() throws {
        let result = try LiminalParser().parse("# Heading\n\nBody with [link](target)\n")
        let rootHandle = result.tree.rootHandle()

        #expect(DocumentItemSyntax(rootHandle) == nil)
        #expect(BlockSyntax(rootHandle) == nil)
        #expect(InlineSyntax(rootHandle) == nil)
        #expect(ValueSyntax(rootHandle) == nil)

        guard case .atxHeading(let heading) = result.rootSyntax.documentItems[0] else {
            Issue.record("expected heading")
            return
        }
        #expect(DocumentItemSyntax(heading.syntax) != nil)
        #expect(BlockSyntax(heading.syntax) != nil)
        #expect(heading.level == 1)

        guard case .paragraph(let paragraph) = result.rootSyntax.documentItems[2],
              let linkNode = paragraph.inlineContent?.inlineNodes.first
        else {
            Issue.record("expected paragraph link")
            return
        }
        #expect(InlineSyntax(linkNode.syntax) != nil)
    }

    @Test("Slice 1 parser emits recoverable diagnostics for incomplete inline constructs")
    func slice1ParserEmitsRecoverableDiagnosticsForIncompleteInlineConstructs() throws {
        let source = "Broken [[wikilink\nand `code\n"
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.severity) == [.error, .error])
        #expect(result.diagnostics.map(\.message) == [
            "missing closing wikilink",
            "missing closing code span delimiter"
        ])
    }

    @Test("Slice 2 parser recovers inside incomplete typed value syntax")
    func slice2ParserRecoversInsideIncompleteTypedValueSyntax() throws {
        let source = "@Person{name \"Ada\""
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.severity).allSatisfy { $0 == .error })
        #expect(result.diagnostics.map(\.message).contains("missing field colon"))
        #expect(result.diagnostics.map(\.message).contains("missing closing fields delimiter"))
    }

    @Test("structured syntax errors use error text instead of raw payload text")
    func structuredSyntaxErrorsUseErrorTextInsteadOfRawPayloadText() throws {
        let source = "@Person{=bad}"
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.message).contains("expected field"))
        #expect(result.rootSyntax.firstDescendantToken(kind: .errorText)?.text == "=bad")
        #expect(result.rootSyntax.firstDescendantToken(kind: .rawPayloadText) == nil)
    }

    @Test("parse session exposes the most recently parsed tree")
    func parseSessionKeepsCurrentTreeAcrossParses() throws {
        let session = LiminalParseSession()

        let first = try session.parse("one")
        let second = try session.parse("two")

        #expect(first.sourceText == "one")
        #expect(second.sourceText == "two")
        #expect(session.currentTree?.treeID == second.tree.treeID)
    }
}

private func string(for text: StaticString?) -> String? {
    text?.withUTF8Buffer { bytes in
        String(decoding: bytes, as: UTF8.self)
    }
}

private func paragraphPlainText(_ source: String) throws -> String {
    let root = try LiminalParser().parse(source).rootSyntax
    guard case .paragraph(let paragraph) = root.documentItems.first,
          let inlineContent = paragraph.inlineContent
    else {
        Issue.record("expected paragraph")
        return ""
    }
    return inlineContent.plainText
}

private func sourceRange(of needle: String, in source: String) throws -> TextRange {
    let range = try #require(source.range(of: needle))
    let start = source[..<range.lowerBound].utf8.count
    return TextRange(
        start: TextSize(UInt32(start)),
        length: TextSize(UInt32(needle.utf8.count))
    )
}

struct ParseExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var source: String
    var rootChildKinds: [LiminalKind]

    var testDescription: String {
        description
    }
}
