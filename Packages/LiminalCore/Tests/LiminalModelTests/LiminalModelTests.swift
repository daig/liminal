import XCTest
import LiminalModel

final class LiminalModelTests: XCTestCase {
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

    func testDocumentRemainsSourceBackedAndCanCarryBlocks() {
        let sourceOnly = LiminalDocument(source: "# Typed documents\n")
        let heading = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.integer("1")))
            ],
            content: .inline([.text("Typed documents")])
        )
        let semantic = LiminalDocument(source: "# Typed documents\n", blocks: [.node(heading)])

        XCTAssertEqual(sourceOnly.source, "# Typed documents\n")
        XCTAssertTrue(sourceOnly.blocks.isEmpty)
        XCTAssertEqual(semantic.blocks, [.node(heading)])
    }
}
