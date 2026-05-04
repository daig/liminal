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

    @Test("Slice 3 lowering maps block ID suffixes to semantic node IDs")
    func slice3LoweringMapsBlockIDSuffixesToSemanticNodeIDs() throws {
        let source = "# Heading ^heading-id\n\nParagraph `body` ^para-id\n"
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.blocks.count == 2)

        let heading = try #require(document.blocks.first?.node)
        #expect(heading.id?.rawValue == "heading-id")
        guard case .inline(let headingInlines) = heading.content else {
            Issue.record("expected heading inline content")
            return
        }
        #expect(headingInlines == [.text("Heading")])

        let paragraph = try #require(document.blocks.dropFirst().first?.node)
        #expect(paragraph.id?.rawValue == "para-id")
        guard case .inline(let paragraphInlines) = paragraph.content else {
            Issue.record("expected paragraph inline content")
            return
        }
        #expect(paragraphInlines.contains(.text("Paragraph ")))
        #expect(!paragraphInlines.contains(.text("^para-id")))
    }

    @Test("Slice 4 lowering maps lists, tasks, and list item IDs")
    func slice4LoweringMapsListsTasksAndListItemIDs() throws {
        let source = """
        - [x] Done [[Target]]
              continuation ^done-id
        2. Ordered
        """
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        #expect(document.blocks.count == 2)

        let unordered = try #require(document.blocks.first?.node)
        #expect(unordered.type.rawValue == "List")
        #expect(unordered.fields.map(\.name.rawValue) == ["ordered", "marker", "items"])
        #expect(unordered.fields[0].value == .scalar(.boolean(false)))
        #expect(unordered.fields[1].value == .scalar(.bare("dash")))

        guard case .list(let itemValues) = unordered.fields[2].value,
              case .node(let item) = itemValues.first
        else {
            Issue.record("expected list item value")
            return
        }

        #expect(item.type.rawValue == "ListItem")
        #expect(item.id?.rawValue == "done-id")
        #expect(item.fields.map(\.name.rawValue) == ["task"])
        #expect(item.fields[0].value == .scalar(.bare("checked")))
        guard case .blocks(let itemBlocks) = item.content,
              case .node(let openingParagraph) = itemBlocks.first,
              case .inline(let inlines) = openingParagraph.content
        else {
            Issue.record("expected list item block body")
            return
        }
        #expect(itemBlocks.count == 1)
        #expect(inlines.contains(.text("Done ")))
        #expect(inlines.contains(.text("continuation")))
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "SoftBreak"
        })
        #expect(!inlines.contains(.text("^done-id")))

        let ordered = try #require(document.blocks.dropFirst().first?.node)
        #expect(ordered.fields.map(\.name.rawValue) == ["ordered", "marker", "start", "items"])
        #expect(ordered.fields[0].value == .scalar(.boolean(true)))
        #expect(ordered.fields[1].value == .scalar(.bare("decimal_dot")))
        #expect(ordered.fields[2].value == .scalar(.integer("2")))
    }

    @Test("Slice 4 lowering maps unordered list marker families explicitly")
    func slice4LoweringMapsUnorderedListMarkerFamiliesExplicitly() throws {
        let document = LiminalLowerer().lower(try LiminalParser().parse("""
        - Dash
        * Star
        + Plus
        """))

        let markers = document.blocks.compactMap(\.node).compactMap { list in
            list.fields.first { $0.name.rawValue == "marker" }?.value
        }

        #expect(markers == [
            .scalar(.bare("dash")),
            .scalar(.bare("asterisk")),
            .scalar(.bare("plus"))
        ])
    }

    @Test("Slice 4 ordered list marker overflow stays lossless and omits start")
    func slice4OrderedListMarkerOverflowStaysLosslessAndOmitsStart() throws {
        let source = "12345678901234567890. Huge\n"
        let parsed = try LiminalParser().parse(source)

        #expect(parsed.sourceText == source)
        #expect(parsed.diagnostics.map(\.message) == [
            "ordered list marker start number is too large"
        ])

        guard case .list(let list) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected ordered list")
            return
        }
        #expect(list.isOrdered)
        #expect(list.startNumber == nil)

        let document = LiminalLowerer().lower(parsed)
        let loweredList = try #require(document.blocks.first?.node)
        #expect(loweredList.fields.map(\.name.rawValue) == ["ordered", "marker", "items"])
        #expect(loweredList.fields[0].value == .scalar(.boolean(true)))
        #expect(loweredList.fields[1].value == .scalar(.bare("decimal_dot")))
    }

    @Test("Slice 4 lowering maps blockquotes to block content")
    func slice4LoweringMapsBlockquotesToBlockContent() throws {
        let source = """
        > Foo
        > Bar
        > - Item
        """
        let document = LiminalLowerer().lower(try LiminalParser().parse(source))

        let quote = try #require(document.blocks.first?.node)
        #expect(quote.type.rawValue == "BlockQuote")
        guard case .blocks(let blocks) = quote.content else {
            Issue.record("expected blockquote block content")
            return
        }
        #expect(blocks.count == 2)
        #expect(blocks.compactMap(\.node).map(\.type.rawValue) == ["Paragraph", "List"])

        let paragraph = try #require(blocks.first?.node)
        guard case .inline(let inlines) = paragraph.content else {
            Issue.record("expected quoted paragraph inline content")
            return
        }
        #expect(inlines.contains(.text("Foo")))
        #expect(inlines.contains(.text("Bar")))
        #expect(inlines.contains { inline in
            guard case .node(let node) = inline else { return false }
            return node.type.rawValue == "SoftBreak"
        })
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
