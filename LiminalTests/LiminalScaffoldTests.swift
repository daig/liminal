import XCTest
@testable import Liminal

final class LiminalScaffoldTests: XCTestCase {
    func testParseLowerPrintPipelinePreservesSourceThroughCambiumTree() throws {
        let source = "# Typed documents\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let printed = LiminalPrinter().print(document)

        XCTAssertEqual(printed, source)
        XCTAssertTrue(parsed.diagnostics.isEmpty)
    }

    func testEditorSessionOwnsParseSessionBoundary() throws {
        let session = LiminalEditorSession(source: "hello")
        let parsed = try session.parse()
        let document = try session.lowerCurrentDocument()

        XCTAssertEqual(parsed.sourceText, "hello")
        XCTAssertEqual(document.sourceText, "hello")
    }

    func testRenderDocumentUsesSemanticDocumentWithoutOwningSource() throws {
        let parsed = try LiminalParser().parse("preview")
        let document = LiminalLowerer().lower(parsed)
        let renderDocument = RenderDocument(document: document)

        XCTAssertEqual(renderDocument.sourceText, "preview")
        XCTAssertTrue(renderDocument.blocks.isEmpty)
    }
}
