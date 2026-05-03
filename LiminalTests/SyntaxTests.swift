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
            ParseExpectation(description: "empty source", source: ""),
            ParseExpectation(description: "single line ASCII", source: "plain text"),
            ParseExpectation(
                description: "multiline source",
                source: "First paragraph\n\nSecond paragraph\n"
            ),
            ParseExpectation(
                description: "unicode source",
                source: "Body with unicode: λ, 文字, and emoji: 🧠\n"
            ),
            ParseExpectation(
                description: "markdown-like source",
                source: "# Typed documents\n\n- [[Note#Heading]]\n- `code`\n"
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

            var tokenKinds: [LiminalKind] = []
            var tokenTexts: [String] = []
            root.tokens { token in
                tokenKinds.append(token.kind)
                tokenTexts.append(token.makeString())
            }

            if expectation.source.isEmpty {
                #expect(root.childOrTokenCount == 0)
                #expect(tokenKinds.isEmpty)
                #expect(tokenTexts.isEmpty)
            } else {
                #expect(root.childOrTokenCount == 1)
                #expect(tokenKinds == [.rawPayloadText])
                #expect(tokenTexts == [expectation.source])
            }
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

    @Test("typed root overlay exposes current scaffold tokens")
    func typedRootOverlayExposesCurrentScaffoldTokens() throws {
        let source = "plain text"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax
        let byteLength = try TextSize(byteCountOf: source)

        #expect(root.documentItems.isEmpty)
        #expect(root.tokens.map(\.kind) == [.rawPayloadText])
        #expect(root.tokens(kind: .rawPayloadText).map(\.text) == [source])
        #expect(root.tokens(kind: .inlineText).isEmpty)

        let payload = try #require(root.rawPayloadToken)
        #expect(payload.kind == .rawPayloadText)
        #expect(payload.text == source)
        #expect(payload.range == TextRange(start: .zero, length: byteLength))

        let payloadByteCount = try payload.withTextUTF8 { bytes in
            bytes.count
        }
        #expect(payloadByteCount == source.utf8.count)
    }

    @Test("typed dispatch points reject nodes the scaffold does not emit")
    func typedDispatchPointsRejectNodesTheScaffoldDoesNotEmit() throws {
        let result = try LiminalParser().parse("plain text")
        let rootHandle = result.tree.rootHandle()

        #expect(DocumentItemSyntax(rootHandle) == nil)
        #expect(BlockSyntax(rootHandle) == nil)
        #expect(InlineSyntax(rootHandle) == nil)
        #expect(ValueSyntax(rootHandle) == nil)
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

    var testDescription: String {
        description
    }
}
