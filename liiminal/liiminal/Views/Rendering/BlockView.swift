import LaTeXSwiftUI
import SwiftUI

/// Dispatches rendering for a single BlockNode to the appropriate view.
struct BlockView: View {
    let block: BlockNode

    var body: some View {
        switch block {
        case .heading(let h):
            HeadingBlockView(heading: h)
        case .paragraph(let p):
            ParagraphBlockView(paragraph: p)
        case .fencedCode(let c):
            CodeBlockView(codeBlock: c)
        case .thematicBreak:
            ThematicBreakView()
        case .frontmatter(let f):
            FrontmatterBlockView(frontmatter: f)
        case .blankLine:
            Spacer().frame(height: 4)
        case .blockquote(let b):
            BlockquoteBlockView(blockquote: b)
        case .list(let l):
            ListBlockView(list: l)
        case .table(let t):
            TableBlockView(table: t)
        case .displayLatex(let d):
            DisplayLatexBlockView(latex: d)
        case .htmlBlock(let h):
            HTMLBlockView(block: h)
        }
    }
}

// MARK: - Heading

struct HeadingBlockView: View {
    let heading: HeadingBlock

    var body: some View {
        Text(InlineRenderer.render(heading.content, style: .heading(level: heading.level)))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, 4)
    }

    private var topPadding: CGFloat {
        switch heading.level {
        case 1: return 24
        case 2: return 20
        case 3: return 16
        default: return 12
        }
    }
}

// MARK: - Paragraph

struct ParagraphBlockView: View {
    let paragraph: ParagraphBlock

    var body: some View {
        if let embed = singleEmbed {
            EmbedView(target: embed.target, params: embed.params)
        } else {
            Text(InlineRenderer.render(paragraph.content))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private var singleEmbed: (target: String, params: String?)? {
        guard paragraph.content.count == 1,
            case .embed(let target, let params) = paragraph.content[0]
        else { return nil }
        return (target, params)
    }
}

// MARK: - Embed (standalone)

struct EmbedView: View {
    let target: String
    let params: String?

    var body: some View {
        let isImage = target.hasSuffix(".png") || target.hasSuffix(".jpg")
            || target.hasSuffix(".jpeg") || target.hasSuffix(".gif")
            || target.hasSuffix(".svg") || target.hasSuffix(".webp")

        if isImage {
            // Image embed placeholder — actual loading requires vault path context
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(target)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(RenderStyle.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        } else {
            // Note embed reference
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(target)
                    .foregroundStyle(RenderStyle.embedColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RenderStyle.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let codeBlock: FencedCodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = codeBlock.language {
                Text(lang)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            Text(codeBlock.code)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(RenderStyle.codeColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, codeBlock.language != nil ? 4 : 12)
                .padding(.bottom, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
    }
}

// MARK: - Thematic Break

struct ThematicBreakView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 12)
    }
}

// MARK: - Frontmatter

struct FrontmatterBlockView: View {
    let frontmatter: FrontmatterBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("frontmatter")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Text(frontmatter.yaml)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.purple.opacity(0.8))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
    }
}

// MARK: - Blockquote

struct BlockquoteBlockView: View {
    let blockquote: BlockquoteBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(blockquote.children.enumerated()), id: \.offset
                ) { _, child in
                    BlockView(block: child)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}

// MARK: - HTML Block

// MARK: - List

struct ListBlockView: View {
    let list: ListBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { idx, item in
                // Gap indicator for ordered lists: skipped numbers or start > 1
                if list.ordered {
                    let prevNumber = idx > 0 ? list.items[idx - 1].number : 0
                    if idx == 0 && item.number > 1 {
                        GapIndicator(indent: item.indent)
                    } else if idx > 0 && item.number > prevNumber + 1 {
                        GapIndicator(indent: item.indent)
                    }
                }

                ListItemView(item: item, ordered: list.ordered)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GapIndicator: View {
    let indent: Int

    var body: some View {
        Text("⋯")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.leading, CGFloat(indent) * 20 + 6)
            .padding(.vertical, 1)
    }
}

struct ListItemView: View {
    let item: ListItem
    let ordered: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Number (for ordered lists — always shown, even with checkbox)
            if ordered {
                Text("\(item.number).")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16, design: .monospaced))
                    .frame(minWidth: 20, alignment: .trailing)
            } else if item.checked == nil {
                // Unordered bullet (only when no checkbox)
                Text("•")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                    .frame(minWidth: 12)
            }

            // Checkbox (alongside number for ordered, replaces bullet for unordered)
            if let checked = item.checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? .blue : .secondary)
                    .font(.system(size: 14))
            }

            Text(InlineRenderer.render(item.content))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.indent) * 20)
    }
}

// MARK: - Table

struct TableBlockView: View {
    let table: TableBlock

    var body: some View {
        let columnCount = max(
            table.headerCells.count,
            table.bodyRows.first?.count ?? 0
        )
        guard columnCount > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let content = col < table.headerCells.count
                            ? table.headerCells[col].content : []
                        let alignment = col < table.alignments.count
                            ? table.alignments[col] : nil
                        Text(InlineRenderer.render(content, style: .body.bolded()))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: textAlignment(alignment))
                            .padding(8)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Body rows
                ForEach(Array(table.bodyRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let content = col < row.count ? row[col].content : []
                            let alignment = col < table.alignments.count
                                ? table.alignments[col] : nil
                            Text(InlineRenderer.render(content))
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: textAlignment(alignment))
                                .padding(8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.vertical, 4)
        )
    }

    private func textAlignment(_ alignment: TableAlignment?) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case nil: return .leading
        }
    }
}

// MARK: - Display LaTeX

struct DisplayLatexBlockView: View {
    let latex: DisplayLatexBlock

    var body: some View {
        let view = LaTeX("$$\(latex.latex)$$")
            .font(NSFont.systemFont(ofSize: 32, weight: .regular))
            .blockMode(.blockViews)
            .errorMode(.original)
        view
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - HTML Block

struct HTMLBlockView: View {
    let block: HTMLBlock

    var body: some View {
        Text(block.rawHTML)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RenderStyle.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
    }
}
