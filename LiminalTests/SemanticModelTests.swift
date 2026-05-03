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
        #expect(document.items.count == 1)
        #expect(document.blocks.count == 1)
        #expect(document.diagnostics.isEmpty)
    }

    @Test("Slice 1 lowering maps surface forms to typed semantic nodes")
    func slice1LoweringMapsSurfaceFormsToTypedSemanticNodes() throws {
        let source = "# Heading with `code`\n\nSee [[Note#Heading|Alias]] and [site](https://example.org \"Title\") plus ![Alt](image.png).\n![[Embed#^block|payload]]\n"
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.blocks.count == 3)

        let heading = try #require(document.blocks.first?.node)
        #expect(heading.type.rawValue == "Heading")
        #expect(heading.fields.first?.value == .scalar(.integer("1")))

        let paragraph = try #require(document.blocks.dropFirst().first?.node)
        guard case .inline(let inlines) = paragraph.content else {
            Issue.record("expected paragraph inline content")
            return
        }

        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "WikiLink"
        })
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "Link"
        })
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "Image"
        })

        let embedBlock = try #require(document.blocks.last?.node)
        #expect(embedBlock.type.rawValue == "WikiEmbedBlock")
        #expect(embedBlock.fields.map(\.name.rawValue) == ["target", "payload"])
    }
}

private extension LiminalBlock {
    var node: LiminalNode? {
        guard case .node(let node) = self else {
            return nil
        }
        return node
    }
}
