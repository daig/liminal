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
        case .mdLink(let link):
            lowerMarkdownLink(link)
        case .mdImage(let image):
            lowerMarkdownImage(image)
        case .wikilink(let wikilink):
            lowerWikilink(wikilink)
        case .wikiEmbed(let embed):
            lowerWikiEmbed(embed)
        case nil:
            nil
        }
    }

    private func lowerMarkdownLink(_ link: MdLinkSyntax) -> LiminalInline {
        let destination = parseLinkDestination(link.destinationText)
        var fields = [
            field("href", .scalar(.bare(destination.target)))
        ]
        if let title = destination.title {
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
        let destination = parseLinkDestination(image.destinationText)
        var fields = [
            field("src", .scalar(.bare(destination.target))),
            field("alt", .inlineLiteral(lowerInlineContent(image.altContent)))
        ]
        if let title = destination.title {
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

    private func parseLinkDestination(_ raw: String) -> (target: String, title: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quote = trimmed.last, quote == "\"" || quote == "'" else {
            return (trimmed, nil)
        }

        var cursor = trimmed.index(before: trimmed.endIndex)
        while cursor > trimmed.startIndex {
            cursor = trimmed.index(before: cursor)
            if trimmed[cursor] == quote {
                let titleStart = trimmed.index(after: cursor)
                let beforeTitle = String(trimmed[..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !beforeTitle.isEmpty else {
                    break
                }
                return (beforeTitle, String(trimmed[titleStart..<trimmed.index(before: trimmed.endIndex)]))
            }
        }

        return (trimmed, nil)
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
            range: syntax.textRange,
            rawSource: syntax.withCursor { node in
                node.makeString()
            }
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
