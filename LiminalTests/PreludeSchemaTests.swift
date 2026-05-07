import Testing
@testable import Liminal

@Suite("Prelude Schema")
struct PreludeSchemaTests {
    @Test("prelude exposes v0.2 §11 types in stable order")
    func preludeContainsV02TypesInStableOrder() {
        let names = LiminalPrelude.schema.types.map(\.name.rawValue)

        #expect(names == [
            "Document",
            "DocumentItem",
            "Frontmatter",
            "Paragraph",
            "Heading",
            "ThematicBreak",
            "BlockQuote",
            "List",
            "ListItem",
            "CodeBlock",
            "MathBlock",
            "HtmlBlock",
            "CommentBlock",
            "Table",
            "Column",
            "Row",
            "EmbedBlock",
            "WikiEmbedBlock",
            "SoftBreak",
            "HardBreak",
            "Emphasis",
            "Strong",
            "Strikethrough",
            "Highlight",
            "CodeSpan",
            "Link",
            "Image",
            "WikiLink",
            "EmbedInline",
            "WikiEmbedInline",
            "MathInline",
            "HtmlInline",
            "CommentInline",
            "FootnoteInline",
            "Interpolation",
            "EmbedValue",
            "if",
            "for"
        ])
    }

    @Test("Document type targets ordered items, not blocks")
    func documentTargetsOrderedItems() throws {
        let document = try #require(LiminalPrelude.schema.type(named: "Document"))
        let fields = try recordFields(in: document)

        #expect(document.kind == .document)
        #expect(fields.map(\.name.rawValue) == ["items"])
        #expect(fields[0].type == .list(.named("DocumentItem")))
    }

    @Test("DocumentItem is a variant by kind with five cases")
    func documentItemIsAVariantWithFiveCases() throws {
        let item = try #require(LiminalPrelude.schema.type(named: "DocumentItem"))

        #expect(item.kind == .value)

        guard case .variant(let discriminator, let cases) = item.definition else {
            Issue.record("expected DocumentItem to be a variant")
            return
        }

        #expect(discriminator == "kind")
        #expect(cases.map(\.name) == ["block", "value", "schema", "template", "directive"])

        let blockCase = cases[0]
        #expect(blockCase.fields.map(\.name.rawValue) == ["block"])
        #expect(blockCase.fields[0].type == .block)

        let valueCase = cases[1]
        #expect(valueCase.fields.map(\.name.rawValue) == ["value"])
        #expect(valueCase.fields[0].type == .value)

        let schemaCase = cases[2]
        #expect(schemaCase.fields.map(\.name.rawValue) == ["name", "raw"])
        #expect(schemaCase.fields[0].type == .str)
        #expect(schemaCase.fields[0].isOptional)
        #expect(schemaCase.fields[1].type == .str)
        #expect(!schemaCase.fields[1].isOptional)

        let templateCase = cases[3]
        #expect(templateCase.fields.map(\.name.rawValue) == ["template"])
        #expect(templateCase.fields[0].type == .template)

        let directiveCase = cases[4]
        #expect(directiveCase.fields.map(\.name.rawValue) == ["raw"])
        #expect(directiveCase.fields[0].type == .str)
    }

    @Test("frontmatter schema captures yaml format and raw payload")
    func frontmatterSchemaShape() throws {
        let frontmatter = try #require(LiminalPrelude.schema.type(named: "Frontmatter"))
        let fields = try recordFields(in: frontmatter)

        #expect(frontmatter.kind == .value)
        #expect(fields.map(\.name.rawValue) == ["format", "raw"])
        #expect(fields[0].type == .enumeration(["yaml"]))
        #expect(fields[1].type == .str)
    }

    @Test("paragraph and heading schemas use inline body as content")
    func paragraphAndHeadingShapes() throws {
        let paragraph = try #require(LiminalPrelude.schema.type(named: "Paragraph"))
        let pFields = try recordFields(in: paragraph)
        #expect(paragraph.kind == .block)
        #expect(pFields.map(\.name.rawValue) == ["body"])
        #expect(pFields[0].type == .inline)
        #expect(pFields[0].modifiers == [.content])

        let heading = try #require(LiminalPrelude.schema.type(named: "Heading"))
        let hFields = try recordFields(in: heading)
        #expect(heading.kind == .block)
        #expect(hFields.map(\.name.rawValue) == ["level", "body"])
        #expect(hFields[0].type == .int)
        #expect(!hFields[0].isOptional)
        #expect(hFields[1].type == .inline)
        #expect(hFields[1].modifiers == [.content])
    }

    @Test("thematic break, soft break, and hard break carry no fields")
    func emptyBlockAndInlineShapes() throws {
        let thematicBreak = try #require(LiminalPrelude.schema.type(named: "ThematicBreak"))
        #expect(thematicBreak.kind == .block)
        #expect(try recordFields(in: thematicBreak).isEmpty)

        let softBreak = try #require(LiminalPrelude.schema.type(named: "SoftBreak"))
        #expect(softBreak.kind == .inline)
        #expect(try recordFields(in: softBreak).isEmpty)

        let hardBreak = try #require(LiminalPrelude.schema.type(named: "HardBreak"))
        #expect(hardBreak.kind == .inline)
        #expect(try recordFields(in: hardBreak).isEmpty)
    }

    @Test("blockquote uses blocks content")
    func blockquoteUsesBlocksContent() throws {
        let blockquote = try #require(LiminalPrelude.schema.type(named: "BlockQuote"))
        let fields = try recordFields(in: blockquote)
        #expect(blockquote.kind == .block)
        #expect(fields.map(\.name.rawValue) == ["body"])
        #expect(fields[0].type == .blocks)
        #expect(fields[0].modifiers == [.content])
    }

    @Test("list and list item shapes carry marker family and task state")
    func listAndListItemShapes() throws {
        let list = try #require(LiminalPrelude.schema.type(named: "List"))
        let listFields = try recordFields(in: list)
        #expect(list.kind == .block)
        #expect(listFields.map(\.name.rawValue) == ["ordered", "marker", "start", "items"])
        #expect(listFields[0].type == .bool)
        #expect(listFields[1].type == .enumeration(["dash", "asterisk", "plus", "decimal_dot"]))
        #expect(listFields[2].type == .int)
        #expect(listFields[2].isOptional)
        #expect(listFields[3].type == .list(.named("ListItem")))

        let item = try #require(LiminalPrelude.schema.type(named: "ListItem"))
        let itemFields = try recordFields(in: item)
        #expect(item.kind == .value)
        #expect(itemFields.map(\.name.rawValue) == ["task", "body"])
        #expect(itemFields[0].type == .enumeration(["unchecked", "checked"]))
        #expect(itemFields[0].isOptional)
        #expect(itemFields[1].type == .blocks)
        #expect(itemFields[1].modifiers == [.content])
    }

    @Test("code block schema includes optional info alongside language and text")
    func codeBlockIncludesInfoField() throws {
        let codeBlock = try #require(LiminalPrelude.schema.type(named: "CodeBlock"))
        let fields = try recordFields(in: codeBlock)
        #expect(codeBlock.kind == .block)
        #expect(fields.map(\.name.rawValue) == ["language", "info", "text"])
        #expect(fields[0].type == .str)
        #expect(fields[0].isOptional)
        #expect(fields[1].type == .str)
        #expect(fields[1].isOptional)
        #expect(fields[2].type == .str)
        #expect(!fields[2].isOptional)
    }

    @Test("math and html types split into block and inline variants")
    func mathAndHtmlSplitIntoBlockAndInlineVariants() throws {
        let mathBlock = try #require(LiminalPrelude.schema.type(named: "MathBlock"))
        let mathBlockFields = try recordFields(in: mathBlock)
        #expect(mathBlock.kind == .block)
        #expect(mathBlockFields.map(\.name.rawValue) == ["tex"])
        #expect(mathBlockFields[0].type == .str)

        let mathInline = try #require(LiminalPrelude.schema.type(named: "MathInline"))
        let mathInlineFields = try recordFields(in: mathInline)
        #expect(mathInline.kind == .inline)
        #expect(mathInlineFields.map(\.name.rawValue) == ["tex"])
        #expect(mathInlineFields[0].type == .str)

        let htmlBlock = try #require(LiminalPrelude.schema.type(named: "HtmlBlock"))
        let htmlBlockFields = try recordFields(in: htmlBlock)
        #expect(htmlBlock.kind == .block)
        #expect(htmlBlockFields.map(\.name.rawValue) == ["raw"])
        #expect(htmlBlockFields[0].type == .str)

        let htmlInline = try #require(LiminalPrelude.schema.type(named: "HtmlInline"))
        let htmlInlineFields = try recordFields(in: htmlInline)
        #expect(htmlInline.kind == .inline)
        #expect(htmlInlineFields.map(\.name.rawValue) == ["raw"])
        #expect(htmlInlineFields[0].type == .str)

        // Old combined Math/Html types are gone.
        #expect(LiminalPrelude.schema.type(named: "Math") == nil)
        #expect(LiminalPrelude.schema.type(named: "Html") == nil)
    }

    @Test("comment block and inline both carry raw text")
    func commentShapes() throws {
        let commentBlock = try #require(LiminalPrelude.schema.type(named: "CommentBlock"))
        let commentInline = try #require(LiminalPrelude.schema.type(named: "CommentInline"))
        #expect(commentBlock.kind == .block)
        #expect(commentInline.kind == .inline)

        let cbFields = try recordFields(in: commentBlock)
        let ciFields = try recordFields(in: commentInline)
        #expect(cbFields.map(\.name.rawValue) == ["raw"])
        #expect(ciFields.map(\.name.rawValue) == ["raw"])
        #expect(cbFields[0].type == .str)
        #expect(ciFields[0].type == .str)
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

    @Test("structured embed types share expected/fallback/target shape")
    func structuredEmbedShapes() throws {
        for name in ["EmbedBlock", "EmbedInline", "EmbedValue"] {
            let embed = try #require(LiminalPrelude.schema.type(named: QualifiedName(name)))
            let fields = try recordFields(in: embed)
            #expect(fields.map(\.name.rawValue) == ["expected", "fallback", "target"])
            #expect(fields[0].type == .type)
            #expect(fields[0].isOptional)
            #expect(fields[1].type == .inline)
            #expect(fields[1].isOptional)
            #expect(fields[2].type == .target)
            #expect(!fields[2].isOptional)
        }
    }

    @Test("wiki types use target plus optional alias or payload")
    func wikiTypeShapes() throws {
        let wikiLink = try #require(LiminalPrelude.schema.type(named: "WikiLink"))
        let wikiLinkFields = try recordFields(in: wikiLink)
        #expect(wikiLink.kind == .inline)
        #expect(wikiLinkFields.map(\.name.rawValue) == ["target", "body"])
        #expect(wikiLinkFields[0].type == .target)
        #expect(wikiLinkFields[1].type == .inline)
        #expect(wikiLinkFields[1].isOptional)
        #expect(wikiLinkFields[1].modifiers == [.content])

        for name in ["WikiEmbedBlock", "WikiEmbedInline"] {
            let embed = try #require(LiminalPrelude.schema.type(named: QualifiedName(name)))
            let fields = try recordFields(in: embed)
            #expect(fields.map(\.name.rawValue) == ["target", "payload"])
            #expect(fields[0].type == .target)
            #expect(fields[1].type == .str)
            #expect(fields[1].isOptional)
        }
    }

    @Test("inline content containers carry inline @content body")
    func inlineContentContainerShapes() throws {
        for name in ["Emphasis", "Strong", "Strikethrough", "Highlight", "FootnoteInline"] {
            let node = try #require(LiminalPrelude.schema.type(named: QualifiedName(name)))
            let fields = try recordFields(in: node)
            #expect(node.kind == .inline)
            #expect(fields.map(\.name.rawValue) == ["body"])
            #expect(fields[0].type == .inline)
            #expect(fields[0].modifiers == [.content])
        }
    }

    @Test("code span and interpolation expose their string payload")
    func codeSpanAndInterpolationShapes() throws {
        let codeSpan = try #require(LiminalPrelude.schema.type(named: "CodeSpan"))
        let codeSpanFields = try recordFields(in: codeSpan)
        #expect(codeSpan.kind == .inline)
        #expect(codeSpanFields.map(\.name.rawValue) == ["text"])
        #expect(codeSpanFields[0].type == .str)

        let interpolation = try #require(LiminalPrelude.schema.type(named: "Interpolation"))
        let interpolationFields = try recordFields(in: interpolation)
        #expect(interpolation.kind == .inline)
        #expect(interpolationFields.map(\.name.rawValue) == ["expr"])
        #expect(interpolationFields[0].type == .str)
    }

    @Test("default schema initializer remains empty and named prelude")
    func defaultSchemaInitializerRemainsEmptyAndNamedPrelude() {
        let schema = LiminalSchema()

        #expect(schema.name == "prelude")
        #expect(schema.types.isEmpty)
    }

    @Test("Phase 3c.4 prelude declares if/for template control structures")
    func phase3c4TemplateControlShapesArePresent() throws {
        let ifType = try #require(LiminalPrelude.schema.type(named: "if"))
        #expect(ifType.kind == .block)
        let ifFields = try recordFields(in: ifType)
        #expect(ifFields.map(\.name.rawValue) == ["test", "body"])
        // Expression slot uses the .unknown sentinel; body is @content of blocks.
        #expect(ifFields[0].type == .unknown)
        #expect(ifFields[0].isOptional == false)
        #expect(ifFields[1].type == .blocks)
        #expect(ifFields[1].modifiers.contains(.content))

        let forType = try #require(LiminalPrelude.schema.type(named: "for"))
        #expect(forType.kind == .block)
        let forFields = try recordFields(in: forType)
        #expect(forFields.map(\.name.rawValue) == ["item", "in", "body"])
        #expect(forFields[0].type == .unknown)
        #expect(forFields[1].type == .unknown)
        #expect(forFields[2].type == .blocks)
        #expect(forFields[2].modifiers.contains(.content))
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
