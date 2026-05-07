import CambiumCore
import Foundation

public struct LiminalLowerer: Sendable {
    public init() {}

    public func lower(_ parseResult: LiminalParseResult) -> LiminalDocument {
        let items = parseResult.rootSyntax.documentItems.compactMap(lowerDocumentItem)
        return LiminalDocument(
            syntaxTree: parseResult.tree,
            items: items,
            diagnostics: parseResult.diagnostics
        )
    }

    private func lowerDocumentItem(_ item: DocumentItemSyntax) -> LiminalDocumentItem? {
        switch item {
        case .blankLine:
            nil
        case .frontmatter(let frontmatter):
            .value(LiminalNode(
                kind: .value,
                type: "Frontmatter",
                fields: [
                    field("format", .scalar(.bare("yaml"))),
                    field("raw", .scalar(.string(frontmatter.rawYamlText)))
                ],
                source: surface("frontmatter", frontmatter.syntax)
            ))
        case .directive(let directive):
            .directive(lowerDirective(directive))
        case .schemaBlock(let schema):
            .schema(lowerSchemaBlock(schema))
        case .templateBlock(let template):
            .template(LiminalTemplateBlock(
                signature: template.signatureText,
                rawBodyText: template.rawBodyText,
                items: template.documentItems.compactMap(lowerDocumentItem),
                source: surface("templateBlock", template.syntax)
            ))
        case .paragraph(let paragraph):
            lowerParagraph(paragraph).map { .block(.node($0)) }
        case .atxHeading(let heading):
            lowerHeading(heading).map { .block(.node($0)) }
        case .valueDeclaration(let declaration):
            // Syntactic classification only. Phase 3 schema resolution can
            // reclassify generic constructors once their type kind is known.
            declaration.constructor.map { .value(lowerTypedConstructor($0, kind: .value)) }
        case .typedBlock(let block):
            // Syntactic classification only; schema validation owns final type
            // resolution and context checks.
            .block(.node(lowerTypedBlock(block)))
        case .fencedCodeBlock(let block):
            .block(.node(lowerFencedCodeBlock(block)))
        case .mathBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "MathBlock",
                fields: [
                    field("tex", .scalar(.string(block.texText)))
                ],
                source: surface("mathBlock", block.syntax)
            )))
        case .htmlBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "HtmlBlock",
                fields: [
                    field("raw", .scalar(.string(block.rawText)))
                ],
                source: surface("htmlBlock", block.syntax)
            )))
        case .commentBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "CommentBlock",
                fields: [
                    field("raw", .scalar(.string(block.rawText)))
                ],
                source: surface("commentBlock", block.syntax)
            )))
        case .list(let list):
            .block(.node(lowerList(list)))
        case .blockQuote(let quote):
            .block(.node(lowerBlockQuote(quote)))
        case .pipeTable(let table):
            .block(.node(lowerPipeTable(table)))
        case .structuredEmbedBlock(let embed):
            .block(.node(lowerStructuredEmbedBlock(embed)))
        case .wikiEmbedBlock(let embed):
            .block(.node(lowerWikiEmbedBlock(embed)))
        }
    }

    private func lowerDirective(_ directive: DirectiveSyntax) -> LiminalDirective {
        let useDirective = directive.useDirective
        let useKind = useDirective?.kindText.flatMap(LiminalUseKind.init(rawValue:))
        let targetText = useDirective?.targetText ?? ""
        let targetIsQuoted = useDirective?.targetIsQuoted ?? false
        let filterQNames: [QualifiedName]?
        if let useDirective, useDirective.hasFilter {
            filterQNames = useDirective.filterQNames.map { QualifiedName($0) }
        } else {
            filterQNames = nil
        }
        let alias = useDirective?.aliasText
        return LiminalDirective(
            name: directive.keywordText,
            rawText: directive.bodyText,
            useKind: useKind,
            targetText: targetText,
            targetIsQuoted: targetIsQuoted,
            filterQNames: filterQNames,
            alias: alias,
            source: surface("directive", directive.syntax)
        )
    }

    private func lowerSchemaBlock(_ schema: SchemaBlockSyntax) -> LiminalSchemaBlock {
        var declarations: [LiminalUserSchemaTypeDeclaration] = []
        for decl in schema.declarations {
            declarations.append(LiminalUserSchemaTypeDeclaration(
                name: QualifiedName(decl.qnameText),
                kind: NodeKind(rawValue: decl.nodeKindText),
                rawRHS: decl.rhsText
            ))
        }
        for decl in schema.templateDeclarations {
            declarations.append(LiminalUserSchemaTypeDeclaration(
                name: QualifiedName(decl.qnameText),
                kind: .template,
                rawRHS: decl.signatureText
            ))
        }
        return LiminalSchemaBlock(
            name: schema.nameText,
            rawText: schema.rawText,
            declarations: declarations,
            source: surface("schemaBlock", schema.syntax)
        )
    }

    private func lowerParagraph(_ paragraph: ParagraphSyntax) -> LiminalNode? {
        let inlines = lowerInlineContent(paragraph.inlineContent)
        guard !inlines.isEmpty || paragraph.blockIdToken != nil else {
            return nil
        }

        return LiminalNode(
            kind: .block,
            type: "Paragraph",
            id: paragraph.blockIdToken.map { Anchor($0.text) },
            content: .inline(inlines),
            source: surface("paragraph", paragraph.syntax)
        )
    }

    private func lowerHeading(_ heading: AtxHeadingSyntax) -> LiminalNode? {
        guard (1...6).contains(heading.level) else {
            return nil
        }

        return LiminalNode(
            kind: .block,
            type: "Heading",
            id: heading.blockIdToken.map { Anchor($0.text) },
            fields: [
                field("level", .scalar(.integer(String(heading.level))))
            ],
            content: .inline(lowerInlineContent(heading.inlineContent)),
            source: surface("atxHeading", heading.syntax)
        )
    }

    private func lowerWikiEmbedBlock(_ embed: WikiEmbedBlockSyntax) -> LiminalNode {
        var fields = [
            field("target", .scalar(.string(embed.targetText)))
        ]
        if let payload = embed.payloadText {
            fields.append(field("payload", .scalar(.string(payload))))
        }

        return LiminalNode(
            kind: .block,
            type: "WikiEmbedBlock",
            fields: fields,
            source: surface("wikiEmbedBlock", embed.syntax)
        )
    }

    private func lowerFencedCodeBlock(_ block: FencedCodeBlockSyntax) -> LiminalNode {
        var fields: [LiminalField] = []
        if let language = block.languageText {
            fields.append(field("language", .scalar(.bare(language))))
        }
        // Per spec §6.6 the `info` field carries the raw info string;
        // only `language` is trimmed. Gate emission on the normalized
        // form so a whitespace-only info string doesn't produce a field.
        if !block.normalizedInfoText.isEmpty {
            fields.append(field("info", .scalar(.string(block.infoText))))
        }
        fields.append(field("text", .scalar(.string(block.codeText))))

        return LiminalNode(
            kind: .block,
            type: "CodeBlock",
            fields: fields,
            source: surface("fencedCodeBlock", block.syntax)
        )
    }

    private func lowerList(_ list: ListSyntax) -> LiminalNode {
        var fields = [
            field("ordered", .scalar(.boolean(list.isOrdered))),
            field("marker", .scalar(.bare(listMarkerName(for: list)))),
            field("items", .list(list.items.map { .node(lowerListItem($0)) }))
        ]
        if let startNumber = list.startNumber {
            fields.insert(
                field("start", .scalar(.integer(String(startNumber)))),
                at: 2
            )
        }

        return LiminalNode(
            kind: .block,
            type: "List",
            fields: fields,
            source: surface("list", list.syntax)
        )
    }

    private func lowerListItem(_ item: ListItemSyntax) -> LiminalNode {
        var fields: [LiminalField] = []
        if let taskState = item.taskState {
            fields.append(field("task", .scalar(.bare(taskState == .checked ? "checked" : "unchecked"))))
        }

        return LiminalNode(
            kind: .value,
            type: "ListItem",
            id: item.blockIdToken.map { Anchor($0.text) },
            fields: fields,
            content: .blocks(lowerDocumentItemsToBlocks(item.documentItems)),
            source: surface("listItem", item.syntax)
        )
    }

    private func lowerBlockQuote(_ quote: BlockQuoteSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: "BlockQuote",
            content: .blocks(lowerDocumentItemsToBlocks(quote.documentItems)),
            source: surface("blockQuote", quote.syntax)
        )
    }

    private func lowerPipeTable(_ table: PipeTableSyntax) -> LiminalNode {
        let alignments = table.alignments
        let columns = table.headerCells.enumerated().map { index, cell in
            var fields = [
                field("label", .inlineLiteral(lowerInlineContent(cell.inlineContent)))
            ]
            if index < alignments.count, let alignment = alignments[index] {
                fields.append(field("align", .scalar(.bare(alignment.rawValue))))
            }
            return LiminalValue.node(LiminalNode(
                kind: .value,
                type: "Column",
                fields: fields,
                source: surface("pipeTableCell", cell.syntax)
            ))
        }

        let rows = table.rows.map { row in
            LiminalValue.node(LiminalNode(
                kind: .value,
                type: "Row",
                fields: [
                    field("cells", .list(row.cells.map { cell in
                        .inlineLiteral(lowerInlineContent(cell.inlineContent))
                    }))
                ],
                source: surface("pipeTableRow", row.syntax)
            ))
        }

        return LiminalNode(
            kind: .block,
            type: "Table",
            fields: [
                field("columns", .list(columns)),
                field("rows", .list(rows))
            ],
            source: surface("pipeTable", table.syntax)
        )
    }

    private func listMarkerName(for list: ListSyntax) -> String {
        if list.isOrdered {
            return "decimal_dot"
        }

        switch list.markerText {
        case "-":
            return "dash"
        case "*":
            return "asterisk"
        case "+":
            return "plus"
        default:
            return "unknown"
        }
    }

    private func lowerInlineContent(_ content: InlineContentSyntax?) -> [LiminalInline] {
        guard let content else {
            return []
        }

        return content.syntax.withCursor { node in
            var result: [LiminalInline] = []
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where token.kind == .inlineText:
                    result.append(.text(token.makeString()))
                case .node(let child) where child.kind == .softBreak:
                    result.append(.node(LiminalNode(
                        kind: .inline,
                        type: "SoftBreak",
                        source: surface("softBreak", child.makeHandle())
                    )))
                case .node(let child) where child.kind == .hardBreak:
                    result.append(.node(LiminalNode(
                        kind: .inline,
                        type: "HardBreak",
                        source: surface("hardBreak", child.makeHandle())
                    )))
                case .node(let child):
                    if let inline = lowerInlineNode(child.makeHandle()) {
                        result.append(inline)
                    }
                default:
                    break
                }
            }
            return result
        }
    }

    private func lowerInlineNode(_ syntax: SyntaxNodeHandle<LiminalLanguage>) -> LiminalInline? {
        switch InlineSyntax(syntax) {
        case .codeSpan(let codeSpan):
            .node(LiminalNode(
                kind: .inline,
                type: "CodeSpan",
                fields: [
                    field("text", .scalar(.string(codeSpan.codeText)))
                ],
                source: surface("codeSpan", codeSpan.syntax)
            ))
        case .escapedPunctuation(let punctuation):
            .text(punctuation.escapedText)
        case .strikethrough(let strikethrough):
            strikethrough.isIncomplete
                ? .text(strikethrough.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "Strikethrough",
                    content: .inline(lowerInlineContent(strikethrough.inlineContent)),
                    source: surface("strikethrough", strikethrough.syntax)
                ))
        case .highlight(let highlight):
            highlight.isIncomplete
                ? .text(highlight.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "Highlight",
                    content: .inline(lowerInlineContent(highlight.inlineContent)),
                    source: surface("highlight", highlight.syntax)
                ))
        case .mdLink(let link):
            lowerMarkdownLink(link)
        case .mdImage(let image):
            lowerMarkdownImage(image)
        case .wikilink(let wikilink):
            lowerWikilink(wikilink)
        case .wikiEmbed(let embed):
            lowerWikiEmbed(embed)
        case .typedInline(let typedInline):
            typedInline.constructor.map { constructor in
                .node(lowerTypedConstructor(constructor, kind: .inline))
            }
        case .structuredEmbed(let embed):
            lowerStructuredEmbedInline(embed)
        case .mathInline(let math):
            .node(LiminalNode(
                kind: .inline,
                type: "MathInline",
                fields: [
                    field("tex", .scalar(.string(math.texText)))
                ],
                source: surface("mathInline", math.syntax)
            ))
        case .interpolation(let interpolation):
            .interpolation(LiminalTemplateExpression(interpolation.expressionText))
        case .inlineComment(let comment):
            .node(LiminalNode(
                kind: .inline,
                type: "CommentInline",
                fields: [
                    field("raw", .scalar(.string(comment.rawText)))
                ],
                source: surface("inlineComment", comment.syntax)
            ))
        case .footnoteInline(let footnote):
            footnote.isIncomplete
                ? .text(footnote.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "FootnoteInline",
                    content: .inline(lowerInlineContent(footnote.inlineContent)),
                    source: surface("footnoteInline", footnote.syntax)
                ))
        case nil:
            nil
        }
    }

    private func lowerMarkdownLink(_ link: MdLinkSyntax) -> LiminalInline {
        var fields = [
            field("href", .scalar(.bare(link.destinationText)))
        ]
        if let title = link.titleText {
            fields.append(field("title", .scalar(.string(title))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "Link",
            fields: fields,
            content: .inline(lowerInlineContent(link.labelContent)),
            source: surface("mdLink", link.syntax)
        ))
    }

    private func lowerMarkdownImage(_ image: MdImageSyntax) -> LiminalInline {
        var fields = [
            field("src", .scalar(.bare(image.destinationText))),
            field("alt", .inlineLiteral(lowerInlineContent(image.altContent)))
        ]
        if let title = image.titleText {
            fields.append(field("title", .scalar(.string(title))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "Image",
            fields: fields,
            source: surface("mdImage", image.syntax)
        ))
    }

    private func lowerWikilink(_ wikilink: WikilinkSyntax) -> LiminalInline {
        let alias = wikilink.aliasContent.map(lowerInlineContent)
        return .node(LiminalNode(
            kind: .inline,
            type: "WikiLink",
            fields: [
                field("target", .scalar(.string(wikilink.targetText)))
            ],
            content: alias.map(LiminalContent.inline),
            source: surface("wikilink", wikilink.syntax)
        ))
    }

    private func lowerWikiEmbed(_ embed: WikiEmbedSyntax) -> LiminalInline {
        var fields = [
            field("target", .scalar(.string(embed.targetText)))
        ]
        if let payload = embed.payloadText {
            fields.append(field("payload", .scalar(.string(payload))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "WikiEmbedInline",
            fields: fields,
            source: surface("wikiEmbed", embed.syntax)
        ))
    }

    private func lowerTypedBlock(_ block: TypedBlockSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: QualifiedName(block.typeName),
            id: block.idText.map { Anchor($0) },
            fields: lowerFields(block.fields),
            content: .blocks(lowerDocumentItemsToBlocks(block.documentItems)),
            source: surface("typedBlock", block.syntax)
        )
    }

    private func lowerTypedConstructor(
        _ constructor: TypedConstructorSyntax,
        kind: NodeKind
    ) -> LiminalNode {
        LiminalNode(
            kind: kind,
            type: QualifiedName(constructor.typeName),
            id: constructor.idText.map { Anchor($0) },
            fields: lowerFields(constructor.fields),
            content: constructor.inlineContent.map { .inline(lowerInlineContent($0)) },
            source: surface("typedConstructor", constructor.syntax)
        )
    }

    private func lowerStructuredEmbedBlock(_ embed: StructuredEmbedBlockSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: "EmbedBlock",
            fields: structuredEmbedFields(
                expectedType: embed.expectedType,
                fallbackContent: embed.fallbackContent,
                targetText: embed.targetText
            ),
            source: surface("structuredEmbedBlock", embed.syntax)
        )
    }

    private func lowerStructuredEmbedInline(_ embed: StructuredEmbedSyntax) -> LiminalInline {
        .node(LiminalNode(
            kind: .inline,
            type: "EmbedInline",
            fields: structuredEmbedFields(
                expectedType: embed.expectedType,
                fallbackContent: embed.fallbackContent,
                targetText: embed.targetText
            ),
            source: surface("structuredEmbed", embed.syntax)
        ))
    }

    private func lowerStructuredEmbedValue(_ embed: StructuredEmbedValueSyntax) -> LiminalValue {
        .embed(LiminalEmbed(
            expectedType: embed.expectedType.map { QualifiedName($0) },
            fallback: lowerInlineContent(embed.fallbackContent),
            target: embed.targetText
        ))
    }

    private func structuredEmbedFields(
        expectedType: String?,
        fallbackContent: InlineContentSyntax?,
        targetText: String
    ) -> [LiminalField] {
        var result: [LiminalField] = []
        if let expectedType {
            result.append(field("expected", .scalar(.bare(expectedType))))
        }
        if let fallbackContent {
            result.append(field("fallback", .inlineLiteral(lowerInlineContent(fallbackContent))))
        }
        result.append(field("target", .scalar(.string(targetText))))
        return result
    }

    private func lowerFields(_ fields: FieldsSyntax?) -> [LiminalField] {
        fields?.fields.map { fieldSyntax in
            field(
                FieldName(fieldSyntax.name),
                fieldSyntax.value.map(lowerValue) ?? .scalar(.null)
            )
        } ?? []
    }

    private func lowerValue(_ value: ValueNodeSyntax) -> LiminalValue {
        guard let payload = value.payload else {
            return .scalar(.null)
        }

        switch payload {
        case .scalar(let scalar):
            return lowerScalarValue(scalar)
        case .list(let list):
            return .list(list.values.map(lowerValue))
        case .record(let record):
            return .record(lowerFields(record.fields))
        case .typedConstructor(let constructor):
            return .node(lowerTypedConstructor(constructor, kind: .value))
        case .inlineLiteral(let literal):
            return .inlineLiteral(lowerInlineContent(literal.inlineContent))
        case .blockLiteral(let literal):
            return .blockLiteral(lowerDocumentItemsToBlocks(literal.documentItems))
        case .reference(let reference):
            return .reference(lowerReference(reference))
        case .structuredEmbedValue(let embed):
            return lowerStructuredEmbedValue(embed)
        }
    }

    private func lowerScalarValue(_ scalar: ScalarValueSyntax) -> LiminalValue {
        guard let token = scalar.token else {
            return .scalar(.null)
        }

        switch token.kind {
        case .quotedStringLiteral:
            return .scalar(.string(decodeQuotedString(token.text)))
        case .integerLiteral:
            return .scalar(.integer(token.text))
        case .numberLiteral:
            return .scalar(.number(token.text))
        case .booleanLiteral:
            return .scalar(.boolean(token.text == "true"))
        case .nullLiteral:
            return .scalar(.null)
        default:
            return .scalar(.bare(token.text))
        }
    }

    private func lowerReference(_ reference: ReferenceSyntax) -> LiminalReference {
        if let externalTargetText = reference.externalTargetText {
            return .external(externalTargetText)
        }

        let qname = QualifiedName(reference.qnameText ?? "")
        guard qname.parts.count > 1 else {
            return .local(Anchor(qname.rawValue))
        }

        let namespace = QualifiedName(parts: Array(qname.parts.dropLast()))
        return .qualified(namespace: namespace, id: Anchor(qname.parts.last ?? ""))
    }

    private func lowerDocumentItemsToBlocks(_ items: [DocumentItemSyntax]) -> [LiminalBlock] {
        items.compactMap { item in
            switch lowerDocumentItem(item) {
            case .block(let block)?:
                block
            case .value?, .schema?, .template?, .directive?, nil:
                nil
            }
        }
    }

    private func decodeQuotedString(_ text: String) -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else {
            return text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        var result = ""
        var cursor = text.index(after: text.startIndex)
        let end = text.index(before: text.endIndex)
        while cursor < end {
            let character = text[cursor]
            if character == "\\", text.index(after: cursor) < end {
                cursor = text.index(after: cursor)
                switch text[cursor] {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    result.append(text[cursor])
                }
            } else {
                result.append(character)
            }
            cursor = text.index(after: cursor)
        }
        return result
    }

    private func field(_ name: FieldName, _ value: LiminalValue) -> LiminalField {
        LiminalField(name: name, value: value)
    }

    private func surface(
        _ name: String,
        _ syntax: SyntaxNodeHandle<LiminalLanguage>
    ) -> SurfaceForm {
        SurfaceForm(
            name: name,
            range: syntax.textRange
        )
    }
}

public enum PrintMode: Sendable {
    case lossless
    case canonical
}

public struct LiminalPrinter: Sendable {
    public init() {}

    public func print(_ document: LiminalDocument, mode: PrintMode = .lossless) -> String {
        switch mode {
        case .lossless:
            document.sourceText ?? ""
        case .canonical:
            document.sourceText ?? ""
        }
    }
}

public struct SurfaceIdentifier: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public protocol SurfaceReader: Sendable {
    var identifier: SurfaceIdentifier { get }
}

public protocol SurfacePrinter: Sendable {
    var identifier: SurfaceIdentifier { get }
}
