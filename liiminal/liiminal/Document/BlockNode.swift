import Foundation

/// A block-level structural element in a markdown document.
enum BlockNode: Equatable, Sendable {
    case heading(HeadingBlock)
    case paragraph(ParagraphBlock)
    case fencedCode(FencedCodeBlock)
    case thematicBreak(ThematicBreakBlock)
    case frontmatter(FrontmatterBlock)
    case blankLine(BlankLineBlock)
    case blockquote(BlockquoteBlock)
    case list(ListBlock)
    case table(TableBlock)
    case displayLatex(DisplayLatexBlock)
    case htmlBlock(HTMLBlock)

    /// Total characters this block occupies in the serialized source.
    var sourceLength: Int {
        switch self {
        case .heading(let b): return b.sourceLength
        case .paragraph(let b): return b.sourceLength
        case .fencedCode(let b): return b.sourceLength
        case .thematicBreak(let b): return b.sourceLength
        case .frontmatter(let b): return b.sourceLength
        case .blankLine(let b): return b.sourceLength
        case .blockquote(let b): return b.sourceLength
        case .list(let b): return b.sourceLength
        case .table(let b): return b.sourceLength
        case .displayLatex(let b): return b.sourceLength
        case .htmlBlock(let b): return b.sourceLength
        }
    }

    /// Visible content characters, ignoring structural syntax.
    var contentLength: Int {
        switch self {
        case .heading(let b): return b.content.totalContentLength
        case .paragraph(let b): return b.content.totalContentLength
        case .fencedCode(let b): return b.code.count
        case .thematicBreak: return 0
        case .frontmatter(let b): return b.yaml.count
        case .blankLine: return 0
        case .blockquote(let b): return b.children.reduce(0) { $0 + $1.contentLength }
        case .list(let b): return b.items.reduce(0) { $0 + $1.content.totalContentLength }
        case .table(let b):
            let header = b.headerCells.reduce(0) { $0 + $1.content.totalContentLength }
            let body = b.bodyRows.reduce(0) { r, row in
                r + row.reduce(0) { $0 + $1.content.totalContentLength }
            }
            return header + body
        case .displayLatex(let b): return b.latex.count
        case .htmlBlock(let b): return b.rawHTML.count
        }
    }

    /// The inline content of this block, if any.
    var inlineContent: [InlineNode]? {
        switch self {
        case .heading(let b): return b.content
        case .paragraph(let b): return b.content
        default: return nil
        }
    }
}

// MARK: - Block Structs

struct HeadingBlock: Equatable, Sendable {
    let level: Int
    let content: [InlineNode]
    let sourceLength: Int

    /// Characters before inline content starts (e.g. "## " = 3).
    var prefixLength: Int { level + 1 }
}

struct ParagraphBlock: Equatable, Sendable {
    let content: [InlineNode]
    let sourceLength: Int
    let trailingNewlineCount: Int
}

struct FencedCodeBlock: Equatable, Sendable {
    let language: String?
    let code: String
    let fence: String
    let sourceLength: Int
}

struct ThematicBreakBlock: Equatable, Sendable {
    let sourceText: String
    var sourceLength: Int { sourceText.count }
}

struct FrontmatterBlock: Equatable, Sendable {
    let yaml: String
    let sourceLength: Int
}

struct BlankLineBlock: Equatable, Sendable {
    let sourceLength: Int
}

struct BlockquoteBlock: Equatable, Sendable {
    let children: [BlockNode]
    let sourceLength: Int
}

struct ListBlock: Equatable, Sendable {
    let ordered: Bool
    let startNumber: Int
    let items: [ListItem]
    let sourceLength: Int
}

struct ListItem: Equatable, Sendable {
    let content: [InlineNode]
    let checked: Bool?
    let indent: Int
    let number: Int  // actual number from source (0 for unordered)
    let sourceLength: Int
    let markerLength: Int
}

struct TableCell: Equatable, Sendable {
    let content: [InlineNode]
    let sourceOffset: Int  // offset from start of the table block
}

struct TableBlock: Equatable, Sendable {
    let headerCells: [TableCell]
    let alignments: [TableAlignment?]
    let bodyRows: [[TableCell]]
    let sourceLength: Int
    let separatorOffset: Int
    let separatorLength: Int
}

enum TableAlignment: Equatable, Sendable {
    case left, center, right
}

struct DisplayLatexBlock: Equatable, Sendable {
    let latex: String
    let sourceLength: Int
}

struct HTMLBlock: Equatable, Sendable {
    let rawHTML: String
    let sourceLength: Int
}
