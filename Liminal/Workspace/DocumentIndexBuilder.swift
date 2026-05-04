import CambiumCore

struct DocumentIndexBuilder {
    private var blockOffsets: [TextSize] = []
    private var headings: [HeadingAnchor] = []
    private var blocks: [BlockAnchor] = []
    private var references: [DocumentReference] = []

    mutating func build(root: RootSyntax) -> DocumentIndex {
        for item in root.documentItems {
            appendTopLevelItem(item)
        }

        return DocumentIndex(
            blockOffsets: blockOffsets,
            headings: headings,
            blocks: blocks,
            references: references
        )
    }

    private mutating func appendTopLevelItem(_ item: DocumentItemSyntax) {
        if case .blankLine = item {
            return
        }

        blockOffsets.append(item.range.start)

        // Heading anchors are the document outline: only top-level headings
        // populate the heading anchor space. Nested headings inside typed
        // block bodies, block literal values, etc. are content; the spec'd
        // way to anchor inside those constructs is a block ID (^id, slice 3).
        if case .atxHeading(let heading) = item {
            let title = heading.inlineContent?.plainText ?? ""
            if !WikiLinkNormalizer.headingLookupKey(title).isEmpty {
                headings.append(HeadingAnchor(title: title, sourceOffset: heading.range.start))
            }
        }

        walkItemForReferences(item)
    }

    private mutating func walkItemForReferences(_ item: DocumentItemSyntax) {
        switch item {
        case .blankLine, .frontmatter:
            break
        case .paragraph(let paragraph):
            appendBlockIDAnchor(token: paragraph.blockIdToken, sourceOffset: paragraph.range.start)
            walkInlineContent(paragraph.inlineContent)
        case .atxHeading(let heading):
            appendBlockIDAnchor(token: heading.blockIdToken, sourceOffset: heading.range.start)
            walkInlineContent(heading.inlineContent)
        case .wikiEmbedBlock(let embed):
            appendWikiEmbedReference(
                targetToken: embed.targetTextToken,
                alias: embed.payloadToken?.text,
                sourceRange: embed.range
            )
        case .structuredEmbedBlock(let embed):
            walkInlineContent(embed.fallbackContent)
        case .list(let list):
            for item in list.items {
                walkListItem(item)
            }
        case .blockQuote(let quote):
            for item in quote.documentItems {
                walkItemForReferences(item)
            }
        case .pipeTable(let table):
            walkPipeTable(table)
        case .valueDeclaration(let declaration):
            if let constructor = declaration.constructor {
                walkSyntaxChildren(of: constructor.syntax)
            }
        case .typedBlock(let block):
            walkSyntaxChildren(of: block.syntax)
        case .fencedCodeBlock, .mathBlock, .htmlBlock, .commentBlock:
            break
        }
    }

    private mutating func walkPipeTable(_ table: PipeTableSyntax) {
        for cell in table.headerCells {
            walkInlineContent(cell.inlineContent)
        }
        for row in table.bodyRows {
            for cell in row {
                walkInlineContent(cell.inlineContent)
            }
        }
    }

    private mutating func walkListItem(_ item: ListItemSyntax) {
        appendBlockIDAnchor(token: item.blockIdToken, sourceOffset: item.range.start)
        for child in item.documentItems {
            walkItemForReferences(child)
        }
    }

    private mutating func walkInlineContent(_ content: InlineContentSyntax?) {
        guard let content else {
            return
        }

        for inline in content.inlineNodes {
            walkInline(inline)
        }
    }

    private mutating func walkInline(_ inline: InlineSyntax) {
        switch inline {
        case .wikilink(let wikilink):
            appendWikiReference(
                targetToken: wikilink.targetTextToken,
                alias: wikilink.aliasContent?.plainText,
                sourceRange: wikilink.range
            )
        case .wikiEmbed(let embed):
            appendWikiEmbedReference(
                targetToken: embed.targetTextToken,
                alias: embed.payloadToken?.text,
                sourceRange: embed.range
            )
        case .structuredEmbed(let embed):
            walkInlineContent(embed.fallbackContent)
        case .typedInline(let typedInline):
            if let constructor = typedInline.constructor {
                walkSyntaxChildren(of: constructor.syntax)
            }
        case .strikethrough(let strikethrough):
            walkInlineContent(strikethrough.inlineContent)
        case .highlight(let highlight):
            walkInlineContent(highlight.inlineContent)
        case .footnoteInline(let footnote):
            walkInlineContent(footnote.inlineContent)
        case .mdLink(let link):
            walkInlineContent(link.labelContent)
        case .mdImage(let image):
            walkInlineContent(image.altContent)
        case .codeSpan, .escapedPunctuation, .mathInline, .inlineComment:
            break
        }
    }

    private mutating func walkValueNode(_ value: ValueNodeSyntax?) {
        guard let payload = value?.payload else {
            return
        }
        walkValue(payload)
    }

    private mutating func walkValue(_ value: ValueSyntax) {
        switch value {
        case .scalar, .reference:
            break
        case .list(let list):
            for nested in list.values {
                walkValueNode(nested)
            }
        case .record(let record):
            walkFields(record.fields)
        case .typedConstructor(let constructor):
            walkSyntaxChildren(of: constructor.syntax)
        case .inlineLiteral(let literal):
            walkInlineContent(literal.inlineContent)
        case .blockLiteral(let literal):
            for item in literal.documentItems {
                walkItemForReferences(item)
            }
        case .structuredEmbedValue(let embed):
            walkInlineContent(embed.fallbackContent)
        }
    }

    private mutating func walkFields(_ fields: FieldsSyntax?) {
        for field in fields?.fields ?? [] {
            walkValueNode(field.value)
        }
    }

    private mutating func walkSyntaxChildren(of syntax: SyntaxNodeHandle<LiminalLanguage>) {
        let children = syntax.withCursor { node in
            var result: [SyntaxNodeHandle<LiminalLanguage>] = []
            node.forEachChild { child in
                result.append(child.makeHandle())
            }
            return result
        }

        for child in children {
            walkSyntaxNode(child)
        }
    }

    private mutating func walkSyntaxNode(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        if let item = DocumentItemSyntax(syntax) {
            walkItemForReferences(item)
            return
        }

        if let inline = InlineSyntax(syntax) {
            walkInline(inline)
            return
        }

        if let value = ValueSyntax(syntax) {
            walkValue(value)
            return
        }

        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .listItem:
            walkListItem(ListItemSyntax(unchecked: syntax))
        case .inlineContent:
            walkInlineContent(InlineContentSyntax(unchecked: syntax))
        case .fields:
            walkFields(FieldsSyntax(unchecked: syntax))
        case .field:
            walkValueNode(FieldSyntax(unchecked: syntax).value)
        case .value:
            walkValueNode(ValueNodeSyntax(unchecked: syntax))
        default:
            walkSyntaxChildren(of: syntax)
        }
    }

    private mutating func appendWikiReference(
        targetToken: LiminalTokenSyntax?,
        alias: String?,
        sourceRange: LiminalSourceRange
    ) {
        guard let targetToken else {
            return
        }

        references.append(DocumentReference(
            kind: .link,
            target: WikiTarget.parse(targetToken.text),
            alias: alias,
            sourceRange: sourceRange,
            targetRange: targetToken.range
        ))
    }

    private mutating func appendWikiEmbedReference(
        targetToken: LiminalTokenSyntax?,
        alias: String?,
        sourceRange: LiminalSourceRange
    ) {
        guard let targetToken else {
            return
        }

        references.append(DocumentReference(
            kind: .embed,
            target: WikiTarget.parse(targetToken.text),
            alias: alias,
            sourceRange: sourceRange,
            targetRange: targetToken.range
        ))
    }

    private mutating func appendBlockIDAnchor(
        token: LiminalTokenSyntax?,
        sourceOffset: TextSize
    ) {
        guard let token else {
            return
        }

        blocks.append(BlockAnchor(blockID: token.text, sourceOffset: sourceOffset))
    }
}
