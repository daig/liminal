import CambiumCore
import Testing
@testable import Liminal

@Suite("Syntax")
struct SyntaxTests {
    @Test("syntax kinds use stable Phase 0 raw bands")
    func syntaxKindRawBandsAreStable() {
        #expect(LiminalLanguage.serializationVersion == 2)

        #expect(LiminalKind.whitespace.rawValue == 1)
        #expect(LiminalKind.newline.rawValue == 2)

        #expect(LiminalKind.atSign.rawValue == 10)
        #expect(LiminalKind.rawPayloadText.rawValue == 72)

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
        #expect(LiminalLanguage.isToken(.qname))
        #expect(LiminalLanguage.isToken(.commentText))
        #expect(!LiminalLanguage.isToken(.root))

        #expect(LiminalLanguage.name(for: .rawPayloadText) == "rawPayloadText")
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

        #expect(LiminalLanguage.staticText(for: .whitespace) == nil)
        #expect(LiminalLanguage.staticText(for: .qname) == nil)
        #expect(LiminalLanguage.staticText(for: .rawPayloadText) == nil)
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

struct ParseExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var source: String
    var rootChildKinds: [LiminalKind]

    var testDescription: String {
        description
    }
}
