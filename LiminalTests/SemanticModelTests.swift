import Testing
@testable import Liminal

@Suite("Semantic Model")
struct SemanticModelTests {
    @Test("qualified names split dotted names while preserving the raw value")
    func qualifiedNameSplitsDottedNames() {
        let name: QualifiedName = "schema.Person"

        #expect(name.parts == ["schema", "Person"])
        #expect(name.rawValue == "schema.Person")
    }

    @Test("typed value nodes preserve identity and field order")
    func typedValueNodePreservesIdentityAndFieldOrder() {
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

        #expect(person.kind == .value)
        #expect(person.type.rawValue == "Person")
        #expect(person.id?.rawValue == "ada")
        #expect(person.fields.map(\.name.rawValue) == ["name", "born", "url"])
        #expect(person.fields[1].value == .scalar(.bare("1815-12-10")))
    }

    @Test("inline content can mix text and typed inline nodes")
    func inlineContentCanMixTextAndTypedInlineNodes() {
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

        #expect(inline == [.text("Build "), .node(badge)])
    }

    @Test("block content literals can carry typed blocks")
    func blockContentLiteralCanCarryTypedBlocks() {
        let paragraph = LiminalNode(
            kind: .block,
            type: "Paragraph",
            content: .inline([.text("Ada Lovelace wrote notes on the Analytical Engine.")])
        )

        let value = LiminalValue.blockLiteral([.node(paragraph)])

        #expect(value == .blockLiteral([.node(paragraph)]))
    }

    @Test("references represent local, qualified, and external targets")
    func referencesRepresentLocalQualifiedAndExternalTargets() {
        let local = LiminalReference.local("ada")
        let qualified = LiminalReference.qualified(namespace: "people", id: "ada")
        let external = LiminalReference.external("./people.lim#ada")

        #expect(local == .local("ada"))
        #expect(qualified == .qualified(namespace: "people", id: "ada"))
        #expect(external == .external("./people.lim#ada"))
    }

    @Test("embeds carry expected type, fallback, and target")
    func embedCarriesExpectedTypeFallbackAndTarget() {
        let embed = LiminalEmbed(
            expectedType: "Person",
            fallback: [.text("Ada Lovelace")],
            target: "#ada"
        )

        #expect(embed.expectedType?.rawValue == "Person")
        #expect(embed.fallback == [.text("Ada Lovelace")])
        #expect(embed.target == "#ada")
    }

    @Test("documents reference syntax trees instead of owning source text")
    func documentReferencesSyntaxTreeInsteadOfOwningSource() throws {
        let source = "# Typed documents\n"
        let parseResult = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parseResult)

        #expect(document.sourceText == source)
        #expect(document.blocks.isEmpty)
        #expect(document.diagnostics.isEmpty)
    }
}
