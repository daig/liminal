import Foundation

struct MarkdownSerializer {
    static func serialize(_ document: Document) -> String {
        document.blocks.map { serializeBlock($0) }.joined()
    }

    // MARK: - Blocks

    static func serializeBlock(_ block: BlockNode) -> String {
        switch block {
        case .heading(let h):
            let prefix = String(repeating: "#", count: h.level) + " "
            return prefix + serializeInlines(h.content) + "\n"
        case .paragraph(let p):
            let trailing = String(repeating: "\n", count: max(p.trailingNewlineCount, 1))
            return serializeInlines(p.content) + trailing
        case .fencedCode(let c):
            let lang = c.language ?? ""
            return c.fence + lang + "\n" + c.code + "\n" + c.fence + "\n"
        case .thematicBreak(let t):
            return t.sourceText
        case .frontmatter(let f):
            return "---\n" + f.yaml + "---\n"
        case .blankLine:
            return "\n"
        case .blockquote(let b):
            return b.children.map { "> " + serializeBlock($0) }.joined()
        case .htmlBlock(let h):
            return h.rawHTML
        }
    }

    // MARK: - Inlines

    static func serializeInlines(_ nodes: [InlineNode]) -> String {
        nodes.map { serializeInline($0) }.joined()
    }

    static func serializeInline(_ node: InlineNode) -> String {
        switch node {
        case .text(let s):
            return s
        case .emphasis(let children, let d):
            return String(d) + serializeInlines(children) + String(d)
        case .strong(let children, let d):
            let dd = String(repeating: d, count: 2)
            return dd + serializeInlines(children) + dd
        case .strikethrough(let children):
            return "~~" + serializeInlines(children) + "~~"
        case .highlight(let children):
            return "==" + serializeInlines(children) + "=="
        case .codeSpan(let code, let n):
            let ticks = String(repeating: "`", count: n)
            return ticks + code + ticks
        case .link(let children, let url, let title):
            var result = "[" + serializeInlines(children) + "](" + url
            if let t = title { result += " \"" + t + "\"" }
            return result + ")"
        case .image(let alt, let url, let title):
            var result = "![" + alt + "](" + url
            if let t = title { result += " \"" + t + "\"" }
            return result + ")"
        case .wikilink(let target, let alias):
            if let a = alias { return "[[" + target + "|" + a + "]]" }
            return "[[" + target + "]]"
        case .embed(let target, let params):
            if let p = params { return "![[" + target + "|" + p + "]]" }
            return "![[" + target + "]]"
        case .comment(let s):
            return "%%" + s + "%%"
        case .inlineLatex(let s):
            return "$" + s + "$"
        case .inlineFootnote(let children):
            return "^[" + serializeInlines(children) + "]"
        case .blockReference(let id):
            return "^" + id
        case .autolink(let url):
            return "<" + url + ">"
        case .hardLineBreak:
            return "\\\n"
        case .softLineBreak:
            return "\n"
        }
    }
}
