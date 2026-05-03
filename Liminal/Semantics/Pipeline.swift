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
        case .structuredEmbedBlock(let embed):
            .block(.node(lowerStructuredEmbedBlock(embed)))
        case .wikiEmbedBlock(let embed):
            .block(.node(lowerWikiEmbedBlock(embed)))
        }
    }

    private func lowerParagraph(_ paragraph: ParagraphSyntax) -> LiminalNode? {
        let inlines = lowerInlineContent(paragraph.inlineContent)
        guard !inlines.isEmpty else {
            return nil
        }

        return LiminalNode(
            kind: .block,
            type: "Paragraph",
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
            case .value?, nil:
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
