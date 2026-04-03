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
        // Check if the paragraph is a standalone embed (image/note embed on its own line)
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
