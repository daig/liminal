import XCTest
import LiminalCore

final class LiminalScaffoldTests: XCTestCase {
    func testParseLowerPrintScaffoldPreservesSource() {
        let source = "# Typed documents\n"
        let parsed = LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed.document)
        let printed = LiminalPrinter().print(document)

        XCTAssertEqual(printed, source)
        XCTAssertTrue(parsed.diagnostics.isEmpty)
    }

    func testPreludeContainsRecommendedCoreTypesInOrder() {
        let names = LiminalPrelude.schema.types.map(\.name.rawValue)

        XCTAssertEqual(names, [
            "Document",
            "Paragraph",
            "Heading",
            "Link",
            "Image",
            "CodeSpan",
            "CodeBlock",
            "Math",
            "Html",
            "Table",
            "Column",
            "Row"
        ])
    }

    func testPreludeHeadingUsesInlineBodyAsContent() throws {
        let heading = try XCTUnwrap(LiminalPrelude.schema.type(named: "Heading"))
        let fields = try recordFields(in: heading)

        XCTAssertEqual(heading.kind, .block)
        XCTAssertEqual(fields.map(\.name.rawValue), ["level", "body"])
        XCTAssertEqual(fields[0].type, .int)
        XCTAssertFalse(fields[0].isOptional)
        XCTAssertEqual(fields[1].type, .inline)
        XCTAssertEqual(fields[1].modifiers, [.content])
    }

    func testPreludeLinkAndImageShapes() throws {
        let link = try XCTUnwrap(LiminalPrelude.schema.type(named: "Link"))
        let image = try XCTUnwrap(LiminalPrelude.schema.type(named: "Image"))
        let linkFields = try recordFields(in: link)
        let imageFields = try recordFields(in: image)

        XCTAssertEqual(link.kind, .inline)
        XCTAssertEqual(linkFields.map(\.name.rawValue), ["href", "title", "body"])
        XCTAssertEqual(linkFields[0].type, .uri)
        XCTAssertEqual(linkFields[1].type, .str)
        XCTAssertTrue(linkFields[1].isOptional)
        XCTAssertEqual(linkFields[2].type, .inline)
        XCTAssertEqual(linkFields[2].modifiers, [.content])

        XCTAssertEqual(image.kind, .inline)
        XCTAssertEqual(imageFields.map(\.name.rawValue), ["src", "alt", "title"])
        XCTAssertEqual(imageFields[0].type, .uri)
        XCTAssertEqual(imageFields[1].type, .inline)
        XCTAssertTrue(imageFields[2].isOptional)
    }

    func testPreludeTableColumnAndRowShapes() throws {
        let table = try XCTUnwrap(LiminalPrelude.schema.type(named: "Table"))
        let column = try XCTUnwrap(LiminalPrelude.schema.type(named: "Column"))
        let row = try XCTUnwrap(LiminalPrelude.schema.type(named: "Row"))
        let tableFields = try recordFields(in: table)
        let columnFields = try recordFields(in: column)
        let rowFields = try recordFields(in: row)

        XCTAssertEqual(table.kind, .block)
        XCTAssertEqual(tableFields.map(\.name.rawValue), ["columns", "rows", "caption"])
        XCTAssertEqual(tableFields[0].type, .list(.named("Column")))
        XCTAssertEqual(tableFields[1].type, .list(.named("Row")))
        XCTAssertEqual(tableFields[2].type, .inline)
        XCTAssertTrue(tableFields[2].isOptional)

        XCTAssertEqual(column.kind, .value)
        XCTAssertEqual(columnFields[0].type, .inline)
        XCTAssertEqual(columnFields[1].type, .enumeration(["left", "center", "right"]))
        XCTAssertTrue(columnFields[1].isOptional)

        XCTAssertEqual(row.kind, .value)
        XCTAssertEqual(rowFields[0].type, .list(.inline))
    }

    func testDefaultSchemaInitializerRemainsEmptyAndNamedPrelude() {
        let schema = LiminalSchema()

        XCTAssertEqual(schema.name, "prelude")
        XCTAssertTrue(schema.types.isEmpty)
    }

    private func recordFields(in declaration: SchemaTypeDeclaration) throws -> [SchemaField] {
        guard case .record(let fields) = declaration.definition else {
            XCTFail("Expected \(declaration.name.rawValue) to be a record declaration")
            return []
        }

        return fields
    }
}
