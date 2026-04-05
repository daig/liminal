import XCTest
@testable import liiminal

final class LinkParsingTests: XCTestCase {
    func testInlineParserCapturesTypedWikiTargets() {
        let nodes = InlineParser.parse("[[Folder/Note#Heading|Alias]] and [[#^block-id]]")

        guard nodes.count == 3 else {
            return XCTFail("Expected 3 nodes, got \(nodes.count)")
        }

        guard case .wikilink(let headingTarget, let alias) = nodes[0] else {
            return XCTFail("Expected first node to be a wikilink")
        }
        XCTAssertEqual(headingTarget.notePath, "Folder/Note")
        XCTAssertEqual(headingTarget.heading, "Heading")
        XCTAssertNil(headingTarget.blockID)
        XCTAssertEqual(alias, "Alias")

        guard case .wikilink(let blockTarget, let secondAlias) = nodes[2] else {
            return XCTFail("Expected third node to be a wikilink")
        }
        XCTAssertNil(blockTarget.notePath)
        XCTAssertNil(blockTarget.heading)
        XCTAssertEqual(blockTarget.blockID, "block-id")
        XCTAssertNil(secondAlias)
    }

    func testBlockParserExtractsTrailingBlockIDs() {
        let source = """
        # Heading ^heading-id
        Paragraph body ^paragraph-id
        - List item ^list-id

        """

        let blocks = BlockParser.parse(source)
        guard blocks.count >= 3 else {
            return XCTFail("Expected at least 3 blocks, got \(blocks.count)")
        }

        guard case .heading(let heading) = blocks[0] else {
            return XCTFail("Expected heading block")
        }
        XCTAssertEqual(heading.blockID, "heading-id")
        XCTAssertEqual(heading.content.plainText, "Heading")

        guard case .paragraph(let paragraph) = blocks[1] else {
            return XCTFail("Expected paragraph block")
        }
        XCTAssertEqual(paragraph.blockID, "paragraph-id")
        XCTAssertEqual(paragraph.content.plainText, "Paragraph body")

        guard case .list(let list) = blocks[2], let item = list.items.first else {
            return XCTFail("Expected list block with one item")
        }
        XCTAssertEqual(item.blockID, "list-id")
        XCTAssertEqual(item.content.plainText, "List item")
    }
}
