import XCTest
@testable import liiminal

final class DocumentIndexNavigationTests: XCTestCase {
    func testDocumentIndexMapsSourceOffsetToContainingBlock() {
        let source = """
        # Heading

        Paragraph [[Target]] text
        """

        let blocks = BlockParser.parse(source)
        let document = Document(blocks: blocks)
        let index = DocumentIndex.build(from: document)

        guard blocks.count >= 3 else {
            return XCTFail("Expected heading, blank line, and paragraph blocks")
        }
        guard let reference = index.references.first else {
            return XCTFail("Expected a wiki reference")
        }

        let expectedParagraphOffset = blocks[0].sourceLength + blocks[1].sourceLength
        XCTAssertEqual(
            index.blockOffset(for: .sourceOffset(reference.sourceSpan.location)),
            expectedParagraphOffset
        )
    }
}
