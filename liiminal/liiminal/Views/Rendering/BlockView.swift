import LaTeXSwiftUI
import SwiftUI

/// Dispatches rendering for a single BlockNode to the appropriate view.
struct BlockView: View {
    let block: BlockNode
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil

    var body: some View {
        switch block {
        case .heading(let h):
            HeadingBlockView(heading: h)
        case .paragraph(let p):
            ParagraphBlockView(paragraph: p, onOpenWikiTarget: onOpenWikiTarget)
        case .fencedCode(let c):
            CodeBlockView(codeBlock: c)
        case .thematicBreak:
            ThematicBreakView()
        case .frontmatter(let f):
            FrontmatterBlockView(frontmatter: f)
        case .blankLine:
            Spacer().frame(height: 4)
        case .blockquote(let b):
            BlockquoteBlockView(blockquote: b, onOpenWikiTarget: onOpenWikiTarget)
        case .list(let l):
            ListBlockView(list: l, onOpenWikiTarget: onOpenWikiTarget)
        case .table(let t):
            TableBlockView(table: t, onOpenWikiTarget: onOpenWikiTarget)
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
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        Text(
            InlineRenderer.render(
                heading.content,
                style: .heading(level: heading.level, baseSize: baseFontSize))
        )
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
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        if let embed = singleEmbed {
            EmbedView(target: embed.target, params: embed.params, onOpenWikiTarget: onOpenWikiTarget)
        } else {
            Text(InlineRenderer.render(paragraph.content, style: .body(size: baseFontSize)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private var singleEmbed: (target: WikiTarget, params: String?)? {
        guard paragraph.content.count == 1,
            case .embed(let target, let params) = paragraph.content[0]
        else { return nil }
        return (target, params)
    }
}

// MARK: - Embed (standalone)

struct EmbedView: View {
    let target: WikiTarget
    let params: String?
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil

    var body: some View {
        let targetLabel = target.notePath ?? target.heading ?? target.blockID ?? target.rawTargetString
        let isImage = targetLabel.hasSuffix(".png") || targetLabel.hasSuffix(".jpg")
            || targetLabel.hasSuffix(".jpeg") || targetLabel.hasSuffix(".gif")
            || targetLabel.hasSuffix(".svg") || targetLabel.hasSuffix(".webp")

        if isImage {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(targetLabel)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(RenderStyle.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 4)
        } else {
            Button {
                onOpenWikiTarget?(target)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(targetLabel)
                        .foregroundStyle(RenderStyle.embedColor)
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RenderStyle.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let codeBlock: FencedCodeBlock
    @Environment(\.baseFontSize) private var baseFontSize

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
                .font(.system(size: baseFontSize - 2, design: .monospaced))
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
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("frontmatter")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Text(frontmatter.yaml)
                .font(.system(size: baseFontSize - 3, design: .monospaced))
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
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(blockquote.children.enumerated()), id: \.offset
                ) { _, child in
                    BlockView(block: child, onOpenWikiTarget: onOpenWikiTarget)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}

// MARK: - List

struct ListBlockView: View {
    let list: ListBlock
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { idx, item in
                if list.ordered {
                    let prevNumber = idx > 0 ? list.items[idx - 1].number : 0
                    if idx == 0 && item.number > 1 {
                        GapIndicator(indent: item.indent)
                    } else if idx > 0 && item.number > prevNumber + 1 {
                        GapIndicator(indent: item.indent)
                    }
                }

                ListItemView(item: item, ordered: list.ordered, onOpenWikiTarget: onOpenWikiTarget)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GapIndicator: View {
    let indent: Int

    var body: some View {
        Text("\u{22EF}")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.leading, CGFloat(indent) * 20 + 6)
            .padding(.vertical, 1)
    }
}

struct ListItemView: View {
    let item: ListItem
    let ordered: Bool
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if ordered {
                Text("\(item.number).")
                    .foregroundStyle(.secondary)
                    .font(.system(size: baseFontSize, design: .monospaced))
                    .frame(minWidth: 20, alignment: .trailing)
            } else if item.checked == nil {
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                    .font(.system(size: baseFontSize))
                    .frame(minWidth: 12)
            }

            if let checked = item.checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? .blue : .secondary)
                    .font(.system(size: baseFontSize - 2))
            }

            Text(InlineRenderer.render(item.content, style: .body(size: baseFontSize)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.indent) * 20)
    }
}

// MARK: - Table

struct TableBlockView: View {
    let table: TableBlock
    var onOpenWikiTarget: ((WikiTarget) -> Void)? = nil
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        let columnCount = max(
            table.headerCells.count,
            table.bodyRows.first?.count ?? 0
        )
        guard columnCount > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let content = col < table.headerCells.count
                            ? table.headerCells[col].content : []
                        let alignment = col < table.alignments.count
                            ? table.alignments[col] : nil
                        Text(
                            InlineRenderer.render(
                                content, style: .body(size: baseFontSize).bolded())
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: textAlignment(alignment))
                        .padding(8)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ForEach(Array(table.bodyRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let content = col < row.count ? row[col].content : []
                            let alignment = col < table.alignments.count
                                ? table.alignments[col] : nil
                            Text(
                                InlineRenderer.render(
                                    content, style: .body(size: baseFontSize))
                            )
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
    @Environment(\.baseFontSize) private var baseFontSize

    var body: some View {
        let view = LaTeX("$$\(latex.latex)$$")
            .font(NSFont.systemFont(ofSize: RenderStyle.latexFontSize(for: baseFontSize), weight: .regular))
            .blockMode(.blockViews)
            .errorMode(.original)
        view
            .id("\(latex.latex.hashValue)_\(baseFontSize)")  // bust library cache on size change
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - HTML Block

struct HTMLBlockView: View {
    let block: HTMLBlock
    @Environment(\.baseFontSize) private var baseFontSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 20

    var body: some View {
        HTMLTextView(
            html: block.rawHTML,
            baseFontSize: baseFontSize,
            isDarkMode: colorScheme == .dark,
            contentHeight: $contentHeight
        )
        .frame(height: contentHeight)
        .padding(.vertical, 4)
    }
}

// MARK: - HTML Text View (NSViewRepresentable)

/// Renders HTML via NSTextView, which properly supports NSTextTable
/// and other rich paragraph-level attributes that SwiftUI Text ignores.
struct HTMLTextView: NSViewRepresentable {
    let html: String
    let baseFontSize: CGFloat
    let isDarkMode: Bool
    @Binding var contentHeight: CGFloat

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        applyHTML(to: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        applyHTML(to: textView)
    }

    private func applyHTML(to textView: NSTextView) {
        guard let attributed = Self.renderHTML(
            html, fontSize: baseFontSize, isDark: isDarkMode
        ) else { return }

        textView.textStorage?.setAttributedString(attributed)

        // Measure content height after layout
        DispatchQueue.main.async {
            textView.layoutManager?.ensureLayout(
                for: textView.textContainer!
            )
            let rect = textView.layoutManager!.usedRect(
                for: textView.textContainer!
            )
            let newHeight = ceil(rect.height)
            if abs(newHeight - self.contentHeight) > 1 {
                self.contentHeight = max(newHeight, 1)
            }
        }
    }

    static func renderHTML(
        _ html: String, fontSize: CGFloat, isDark: Bool
    ) -> NSAttributedString? {
        let textColor = isDark ? "#e0e0e0" : "#1d1d1f"
        let linkColor = isDark ? "#6eb5ff" : "#0066cc"
        let borderColor = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"

        let wrapped = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.6;
            color: \(textColor);
        }
        a { color: \(linkColor); }
        table { border-collapse: collapse; }
        th, td {
            border: 1px solid \(borderColor);
            padding: 4px 8px;
            text-align: left;
        }
        code, pre {
            font-family: ui-monospace, Menlo, monospace;
            font-size: 0.9em;
        }
        </style>
        \(html)
        """

        guard let data = wrapped.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
    }
}
