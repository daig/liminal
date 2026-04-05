import Foundation

struct HeadingAnchor: Equatable, Hashable, Sendable {
    let title: String
    let normalizedKey: String
    let sourceOffset: Int
}

struct BlockAnchor: Equatable, Hashable, Sendable {
    let blockID: String
    let normalizedKey: String
    let sourceOffset: Int
}

struct DocumentReference: Equatable, Hashable, Sendable {
    let kind: ReferenceKind
    let target: WikiTarget
    let alias: String?
    let sourceSpan: SourceSpan
}

struct DocumentIndex: Equatable, Sendable {
    let blockOffsets: [Int]
    let headings: [HeadingAnchor]
    let blocks: [BlockAnchor]
    let references: [DocumentReference]

    static let empty = DocumentIndex(blockOffsets: [], headings: [], blocks: [], references: [])

    static func build(from document: Document) -> DocumentIndex {
        var builder = Builder()

        var offset = 0
        for block in document.blocks {
            builder.append(block: block, at: offset)
            offset += block.sourceLength
        }

        return builder.build()
    }

    func reference(containing offset: Int) -> DocumentReference? {
        references.first { $0.sourceSpan.contains(offset) }
    }

    func blockOffset(for anchor: LinkNavigationAnchor) -> Int? {
        switch anchor {
        case .heading(let heading):
            let key = WikiLinkNormalizer.headingLookupKey(heading)
            return headings.first { $0.normalizedKey == key }?.sourceOffset
        case .block(let blockID):
            let key = WikiLinkNormalizer.blockLookupKey(blockID)
            return blocks.first { $0.normalizedKey == key }?.sourceOffset
        case .sourceOffset(let sourceOffset):
            return blockOffsets.last { $0 <= sourceOffset }
        }
    }
}

private struct Builder {
    var blockOffsets: [Int] = []
    var headings: [HeadingAnchor] = []
    var blocks: [BlockAnchor] = []
    var references: [DocumentReference] = []

    mutating func append(block: BlockNode, at offset: Int) {
        blockOffsets.append(offset)

        switch block {
        case .heading(let heading):
            let contentOffset = offset + heading.prefixLength
            let title = heading.content.plainText
            let normalizedTitle = WikiLinkNormalizer.headingLookupKey(title)
            if !normalizedTitle.isEmpty {
                headings.append(
                    HeadingAnchor(
                        title: title,
                        normalizedKey: normalizedTitle,
                        sourceOffset: offset
                    )
                )
            }
            if let blockID = heading.blockID {
                blocks.append(
                    BlockAnchor(
                        blockID: blockID,
                        normalizedKey: WikiLinkNormalizer.blockLookupKey(blockID),
                        sourceOffset: offset
                    )
                )
            }
            append(inlines: heading.content, at: contentOffset)

        case .paragraph(let paragraph):
            append(inlines: paragraph.content, at: offset)
            if let blockID = paragraph.blockID {
                blocks.append(
                    BlockAnchor(
                        blockID: blockID,
                        normalizedKey: WikiLinkNormalizer.blockLookupKey(blockID),
                        sourceOffset: offset
                    )
                )
            }

        case .list(let list):
            var itemOffset = offset
            for item in list.items {
                append(inlines: item.content, at: itemOffset + item.markerLength)
                if let blockID = item.blockID {
                    blocks.append(
                        BlockAnchor(
                            blockID: blockID,
                            normalizedKey: WikiLinkNormalizer.blockLookupKey(blockID),
                            sourceOffset: itemOffset
                        )
                    )
                }
                itemOffset += item.sourceLength
            }

        case .blockquote(let blockquote):
            var childOffset = offset
            for child in blockquote.children {
                append(block: child, at: childOffset)
                childOffset += child.sourceLength
            }

        case .table(let table):
            for cell in table.headerCells {
                append(inlines: cell.content, at: offset + cell.sourceOffset)
            }
            for row in table.bodyRows {
                for cell in row {
                    append(inlines: cell.content, at: offset + cell.sourceOffset)
                }
            }

        case .fencedCode, .thematicBreak, .frontmatter, .blankLine, .displayLatex, .htmlBlock:
            break
        }
    }

    mutating func append(inlines: [InlineNode], at offset: Int) {
        var position = offset
        for inline in inlines {
            append(inline: inline, at: position)
            position += inline.sourceLength
        }
    }

    mutating func append(inline: InlineNode, at offset: Int) {
        switch inline {
        case .emphasis(let children, _):
            append(inlines: children, at: offset + 1)

        case .strong(let children, _):
            append(inlines: children, at: offset + 2)

        case .strikethrough(let children), .highlight(let children):
            append(inlines: children, at: offset + 2)

        case .link(let children, _, _):
            append(inlines: children, at: offset + 1)

        case .inlineFootnote(let children):
            append(inlines: children, at: offset + 2)

        case .wikilink(let target, let alias):
            references.append(
                DocumentReference(
                    kind: .link,
                    target: target,
                    alias: alias,
                    sourceSpan: SourceSpan(location: offset, length: inline.sourceLength)
                )
            )

        case .embed(let target, let params):
            references.append(
                DocumentReference(
                    kind: .embed,
                    target: target,
                    alias: params,
                    sourceSpan: SourceSpan(location: offset, length: inline.sourceLength)
                )
            )

        case .text, .codeSpan, .image, .comment, .inlineLatex, .displayLatex, .blockReference,
            .autolink, .hardLineBreak, .softLineBreak:
            break
        }
    }

    func build() -> DocumentIndex {
        DocumentIndex(
            blockOffsets: blockOffsets,
            headings: headings,
            blocks: blocks,
            references: references
        )
    }
}

extension InlineNode {
    var plainText: String {
        switch self {
        case .text(let text):
            return text
        case .emphasis(let children, _), .strong(let children, _), .strikethrough(let children),
            .highlight(let children), .link(let children, _, _), .inlineFootnote(let children):
            return children.plainText
        case .codeSpan(let code, _):
            return code
        case .wikilink(let target, let alias):
            return alias ?? target.notePath ?? target.heading ?? target.blockID ?? ""
        case .embed(let target, let params):
            return params ?? target.notePath ?? target.heading ?? target.blockID ?? ""
        case .image(let alt, _, _):
            return alt
        case .comment:
            return ""
        case .inlineLatex(let latex), .displayLatex(let latex):
            return latex
        case .blockReference(let id):
            return id
        case .autolink(let url):
            return url
        case .hardLineBreak, .softLineBreak:
            return " "
        }
    }
}

extension [InlineNode] {
    var plainText: String {
        map(\.plainText).joined()
    }
}
