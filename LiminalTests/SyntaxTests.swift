import CambiumCore
import Testing
@testable import Liminal

@Suite("Syntax")
struct SyntaxTests {
    @Test("syntax kinds satisfy Cambium language classification")
    func kindClassificationUsesCambiumLanguageContract() {
        #expect(LiminalLanguage.isNode(.root))
        #expect(LiminalLanguage.isToken(.sourceText))
        #expect(!LiminalLanguage.isTrivia(.sourceText))
        #expect(LiminalLanguage.name(for: .sourceText) == "sourceText")
        #expect(LiminalLanguage.kind(for: RawSyntaxKind(100)) == .root)
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
        }
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

struct ParseExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var source: String

    var testDescription: String {
        description
    }
}
