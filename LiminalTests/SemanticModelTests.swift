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
        #expect(document.blocks.first?.node?.source?.rawSource == nil)
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
        let link = try #require(inlines.compactMap { inline -> LiminalNode? in
            guard case .node(let node) = inline, node.type.rawValue == "Link" else {
                return nil
            }
            return node
        }.first)
        #expect(link.fields.map(\.name.rawValue) == ["href", "title"])
        #expect(link.fields[0].value == .scalar(.bare("https://example.org")))
        #expect(link.fields[1].value == .scalar(.string("Title")))

        let embedBlock = try #require(document.blocks.last?.node)
        #expect(embedBlock.type.rawValue == "WikiEmbedBlock")
        #expect(embedBlock.fields.map(\.name.rawValue) == ["target", "payload"])
    }

    @Test("paragraph line breaks lower to typed SoftBreak and HardBreak inline nodes")
    func paragraphLineBreaksLowerToTypedSoftAndHardBreakInlineNodes() throws {
        let source = "Soft\nbreak.\nHard\\\nbreak.\n"
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.blocks.count == 1)
        let paragraph = try #require(document.blocks.first?.node)
        guard case .inline(let inlines) = paragraph.content else {
            Issue.record("expected paragraph inline content")
            return
        }

        let breakTypes = inlines.compactMap { inline -> String? in
            guard case .node(let node) = inline,
                  ["SoftBreak", "HardBreak"].contains(node.type.rawValue)
            else {
                return nil
            }
            return node.type.rawValue
        }

        #expect(breakTypes == ["SoftBreak", "SoftBreak", "HardBreak"])

        let textRuns = inlines.compactMap { inline -> String? in
            guard case .text(let text) = inline else { return nil }
            return text
        }
        #expect(textRuns == ["Soft", "break.", "Hard", "break."])
    }

    @Test("escaped punctuation lowers without the escape backslash")
    func escapedPunctuationLowersWithoutEscapeBackslash() throws {
        let source = #"Escaped \*literal\* and \[bracket\]."#
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        let paragraph = try #require(document.blocks.first?.node)
        guard case .inline(let inlines) = paragraph.content else {
            Issue.record("expected paragraph inline content")
            return
        }

        let renderedText = inlines.compactMap { inline -> String? in
            guard case .text(let text) = inline else { return nil }
            return text
        }.joined()
        #expect(renderedText == "Escaped *literal* and [bracket].")
    }

    @Test("Slice 2 lowering maps generic typed value declarations")
    func slice2LoweringMapsGenericTypedValueDeclarations() throws {
        let source = #"@Person#ada{name: "Ada", born: 1815-12-10, tags: [math, true, null], home: &people.ada, bio: @[Writes `code`], card: @{Bio paragraph.}}[Ada]"#
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.items.count == 1)
        guard case .value(let person) = document.items[0] else {
            Issue.record("expected value document item")
            return
        }

        #expect(person.kind == .value)
        #expect(person.type.rawValue == "Person")
        #expect(person.id?.rawValue == "ada")
        #expect(person.fields.map(\.name.rawValue) == ["name", "born", "tags", "home", "bio", "card"])
        #expect(person.fields[0].value == .scalar(.string("Ada")))
        #expect(person.fields[1].value == .scalar(.bare("1815-12-10")))
        #expect(person.fields[2].value == .list([.scalar(.bare("math")), .scalar(.boolean(true)), .scalar(.null)]))
        #expect(person.fields[3].value == .reference(.qualified(namespace: "people", id: "ada")))

        guard case .inlineLiteral(let bio) = person.fields[4].value else {
            Issue.record("expected inline literal")
            return
        }
        #expect(bio.count == 2)

        guard case .blockLiteral(let card) = person.fields[5].value,
              case .node(let cardParagraph) = card.first
        else {
            Issue.record("expected block literal paragraph")
            return
        }
        #expect(cardParagraph.type.rawValue == "Paragraph")
    }

    @Test("multiline block literals close only at opener indentation")
    func multilineBlockLiteralsCloseOnlyAtOpenerIndentation() throws {
        let source = """
        @Doc{
          body: @{
            inner
            }
          }
        }
        """
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        guard case .value(let doc) = document.items.first,
              case .blockLiteral(let blocks) = doc.fields.first?.value,
              case .node(let paragraph) = blocks.first,
              case .inline(let inlines) = paragraph.content
        else {
            Issue.record("expected block literal paragraph")
            return
        }

        let text = inlines.compactMap { inline -> String? in
            guard case .text(let text) = inline else { return nil }
            return text
        }.joined()
        #expect(text.contains("    }"))
    }

    @Test("Slice 2 lowering maps typed blocks and structured embeds")
    func slice2LoweringMapsTypedBlocksAndStructuredEmbeds() throws {
        let source = """
        :::Callout#warning{kind: warning, title: @[Careful]}
        Body
        :::
        !{Person}[Ada](#ada)
        Inline !{Person}[Ada](#ada) and @Badge{tone: success}[OK].
        """
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.blocks.count == 3)

        let callout = try #require(document.blocks[0].node)
        #expect(callout.type.rawValue == "Callout")
        #expect(callout.id?.rawValue == "warning")
        #expect(callout.fields.map(\.name.rawValue) == ["kind", "title"])
        guard case .blocks(let calloutBlocks) = callout.content else {
            Issue.record("expected typed block content")
            return
        }
        #expect(calloutBlocks.count == 1)

        let embedBlock = try #require(document.blocks[1].node)
        #expect(embedBlock.type.rawValue == "EmbedBlock")
        #expect(embedBlock.fields.map(\.name.rawValue) == ["expected", "fallback", "target"])

        let paragraph = try #require(document.blocks[2].node)
        guard case .inline(let inlines) = paragraph.content else {
            Issue.record("expected paragraph inline content")
            return
        }
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "EmbedInline"
        })
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "Badge"
        })
    }

    @Test("Slice 2 lowering maps raw reserved block fences")
    func slice2LoweringMapsRawReservedBlockFences() throws {
        let source = """
        :::MathBlock
        E = mc^2
        :::
        :::HtmlBlock
        <div>raw</div>
        :::
        """
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        let math = try #require(document.blocks.first?.node)
        let html = try #require(document.blocks.dropFirst().first?.node)

        #expect(math.type.rawValue == "MathBlock")
        #expect(math.fields.first?.value == .scalar(.string("E = mc^2\n")))
        #expect(html.type.rawValue == "HtmlBlock")
        #expect(html.fields.first?.value == .scalar(.string("<div>raw</div>\n")))
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
