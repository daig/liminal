import XCTest
import LiminalSemantics
import LiminalSyntax

final class LiminalSemanticsTests: XCTestCase {
    func testQualifiedNameSplitsDottedNames() {
        let name: QualifiedName = "schema.Person"

        XCTAssertEqual(name.parts, ["schema", "Person"])
        XCTAssertEqual(name.rawValue, "schema.Person")
    }

    func testTypedValueNodePreservesIdentityAndFieldOrder() {
        let person = LiminalNode(
            kind: .value,
            type: "Person",
            id: "ada",
            fields: [
                LiminalField(name: "name", value: .scalar(.string("Ada Lovelace"))),
                LiminalField(name: "born", value: .scalar(.bare("1815-12-10"))),
                LiminalField(name: "url", value: .scalar(.bare("https://example.org/ada")))
            ]
        )

        XCTAssertEqual(person.kind, .value)
        XCTAssertEqual(person.type.rawValue, "Person")
        XCTAssertEqual(person.id?.rawValue, "ada")
        XCTAssertEqual(person.fields.map(\.name.rawValue), ["name", "born", "url"])
        XCTAssertEqual(person.fields[1].value, .scalar(.bare("1815-12-10")))
    }

    func testInlineContentCanMixTextAndTypedInlineNodes() {
        let badge = LiminalNode(
            kind: .inline,
            type: "Badge",
            fields: [
                LiminalField(name: "status", value: .scalar(.bare("success")))
            ],
            content: .inline([.text("passing")])
        )

        let inline: [LiminalInline] = [
            .text("Build "),
            .node(badge)
        ]

        XCTAssertEqual(inline, [.text("Build "), .node(badge)])
    }

    func testBlockContentLiteralCanCarryTypedBlocks() {
        let paragraph = LiminalNode(
            kind: .block,
            type: "Paragraph",
            content: .inline([.text("Ada Lovelace wrote notes on the Analytical Engine.")])
        )

        let value = LiminalValue.blockLiteral([.node(paragraph)])

        XCTAssertEqual(value, .blockLiteral([.node(paragraph)]))
    }

    func testReferencesRepresentLocalQualifiedAndExternalTargets() {
        let local = LiminalReference.local("ada")
        let qualified = LiminalReference.qualified(namespace: "people", id: "ada")
        let external = LiminalReference.external("./people.lim#ada")

        XCTAssertEqual(local, .local("ada"))
        XCTAssertEqual(qualified, .qualified(namespace: "people", id: "ada"))
        XCTAssertEqual(external, .external("./people.lim#ada"))
    }

    func testEmbedCarriesExpectedTypeFallbackAndTarget() {
        let embed = LiminalEmbed(
            expectedType: "Person",
            fallback: [.text("Ada Lovelace")],
            target: "#ada"
        )

        XCTAssertEqual(embed.expectedType?.rawValue, "Person")
        XCTAssertEqual(embed.fallback, [.text("Ada Lovelace")])
        XCTAssertEqual(embed.target, "#ada")
    }

    func testDocumentReferencesSyntaxTreeInsteadOfOwningSource() throws {
        let source = "# Typed documents\n"
        let parseResult = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parseResult)

        XCTAssertEqual(document.sourceText, source)
        XCTAssertTrue(document.blocks.isEmpty)
        XCTAssertTrue(document.diagnostics.isEmpty)
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
