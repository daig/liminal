import Testing
@testable import Liminal

@Suite("Prelude Schema")
struct PreludeSchemaTests {
    @Test("prelude exposes recommended core types in stable order")
    func preludeContainsRecommendedCoreTypesInOrder() {
        let names = LiminalPrelude.schema.types.map(\.name.rawValue)

        #expect(names == [
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

    @Test("heading schema uses inline body as content")
    func headingUsesInlineBodyAsContent() throws {
        let heading = try #require(LiminalPrelude.schema.type(named: "Heading"))
        let fields = try recordFields(in: heading)

        #expect(heading.kind == .block)
        #expect(fields.map(\.name.rawValue) == ["level", "body"])
        #expect(fields[0].type == .int)
        #expect(!fields[0].isOptional)
        #expect(fields[1].type == .inline)
        #expect(fields[1].modifiers == [.content])
    }

    @Test("link and image schemas keep their expected inline shapes")
    func linkAndImageShapes() throws {
        let link = try #require(LiminalPrelude.schema.type(named: "Link"))
        let image = try #require(LiminalPrelude.schema.type(named: "Image"))
        let linkFields = try recordFields(in: link)
        let imageFields = try recordFields(in: image)

        #expect(link.kind == .inline)
        #expect(linkFields.map(\.name.rawValue) == ["href", "title", "body"])
        #expect(linkFields[0].type == .uri)
        #expect(linkFields[1].type == .str)
        #expect(linkFields[1].isOptional)
        #expect(linkFields[2].type == .inline)
        #expect(linkFields[2].modifiers == [.content])

        #expect(image.kind == .inline)
        #expect(imageFields.map(\.name.rawValue) == ["src", "alt", "title"])
        #expect(imageFields[0].type == .uri)
        #expect(imageFields[1].type == .inline)
        #expect(imageFields[2].isOptional)
    }

    @Test("table, column, and row schemas preserve their structural fields")
    func tableColumnAndRowShapes() throws {
        let table = try #require(LiminalPrelude.schema.type(named: "Table"))
        let column = try #require(LiminalPrelude.schema.type(named: "Column"))
        let row = try #require(LiminalPrelude.schema.type(named: "Row"))
        let tableFields = try recordFields(in: table)
        let columnFields = try recordFields(in: column)
        let rowFields = try recordFields(in: row)

        #expect(table.kind == .block)
        #expect(tableFields.map(\.name.rawValue) == ["columns", "rows", "caption"])
        #expect(tableFields[0].type == .list(.named("Column")))
        #expect(tableFields[1].type == .list(.named("Row")))
        #expect(tableFields[2].type == .inline)
        #expect(tableFields[2].isOptional)

        #expect(column.kind == .value)
        #expect(columnFields[0].type == .inline)
        #expect(columnFields[1].type == .enumeration(["left", "center", "right"]))
        #expect(columnFields[1].isOptional)

        #expect(row.kind == .value)
        #expect(rowFields[0].type == .list(.inline))
    }

    @Test("default schema initializer remains empty and named prelude")
    func defaultSchemaInitializerRemainsEmptyAndNamedPrelude() {
        let schema = LiminalSchema()

        #expect(schema.name == "prelude")
        #expect(schema.types.isEmpty)
    }

    private func recordFields(in declaration: SchemaTypeDeclaration) throws -> [SchemaField] {
        guard case .record(let fields) = declaration.definition else {
            throw SchemaTestError.expectedRecord(declaration.name.rawValue)
        }

        return fields
    }

    private enum SchemaTestError: Error, CustomStringConvertible {
        case expectedRecord(String)

        var description: String {
            switch self {
            case .expectedRecord(let name):
                "Expected \(name) to be a record declaration"
            }
        }
    }
}
