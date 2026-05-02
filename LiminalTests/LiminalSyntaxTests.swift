import CambiumCore
import XCTest
@testable import Liminal

final class LiminalSyntaxTests: XCTestCase {
    func testKindClassificationUsesCambiumLanguageContract() {
        XCTAssertTrue(LiminalLanguage.isNode(.root))
        XCTAssertTrue(LiminalLanguage.isToken(.sourceText))
        XCTAssertFalse(LiminalLanguage.isTrivia(.sourceText))
        XCTAssertEqual(LiminalLanguage.name(for: .sourceText), "sourceText")
        XCTAssertEqual(LiminalLanguage.kind(for: RawSyntaxKind(100)), .root)
    }

    func testParserProducesLosslessCambiumTree() throws {
        let source = "# Typed documents\n\nBody with unicode: λ\n"
        let result = try LiminalParser().parse(source)

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.sourceText, source)

        let byteLength = try TextSize(byteCountOf: source)
        result.tree.withRoot { root in
            XCTAssertEqual(root.kind, .root)
            XCTAssertEqual(root.textLength, byteLength)
            XCTAssertEqual(root.childOrTokenCount, 1)
        }
    }

    func testParserHandlesEmptySourceAsEmptyRoot() throws {
        let result = try LiminalParser().parse("")

        XCTAssertEqual(result.sourceText, "")
        result.tree.withRoot { root in
            XCTAssertEqual(root.kind, .root)
            XCTAssertEqual(root.childOrTokenCount, 0)
        }
    }

    func testParseSessionReusesPublicResultShapeAcrossParses() throws {
        let session = LiminalParseSession()

        let first = try session.parse("one")
        let second = try session.parse("two")

        XCTAssertEqual(first.sourceText, "one")
        XCTAssertEqual(second.sourceText, "two")
        XCTAssertEqual(session.currentTree?.treeID, second.tree.treeID)
    }
}
