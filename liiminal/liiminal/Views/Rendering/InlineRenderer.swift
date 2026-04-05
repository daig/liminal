import Foundation
import SwiftUI

// MARK: - Environment Key

private struct BaseFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    var baseFontSize: CGFloat {
        get { self[BaseFontSizeKey.self] }
        set { self[BaseFontSizeKey.self] = newValue }
    }
}

/// Converts an array of InlineNodes into an AttributedString for SwiftUI Text rendering.
struct InlineRenderer {
    static func render(_ nodes: [InlineNode], style: RenderStyle = .body()) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            result.append(renderNode(node, style: style))
        }
        return result
    }

    // MARK: - Node Dispatch

    private static func renderNode(
        _ node: InlineNode, style: RenderStyle
    ) -> AttributedString {
        switch node {
        case .text(let s):
            return styledText(s, style: style)

        case .emphasis(let children, _):
            return render(children, style: style.italicized())

        case .strong(let children, _):
            return render(children, style: style.bolded())

        case .strikethrough(let children):
            var result = render(children, style: style)
            result.strikethroughStyle = .single
            return result

        case .highlight(let children):
            var result = render(children, style: style)
            result.backgroundColor = .yellow.opacity(0.3)
            return result

        case .codeSpan(let code, _):
            var attr = AttributedString(code)
            attr.font = style.monospaced().font
            attr.foregroundColor = RenderStyle.codeColor
            attr.backgroundColor = RenderStyle.codeBackground
            return attr

        case .link(let children, let url, _):
            var result = render(children, style: style)
            result.foregroundColor = RenderStyle.linkColor
            result.underlineStyle = .single
            if let parsed = URL(string: url) {
                result.link = parsed
            }
            return result

        case .image(let alt, _, _):
            // Render alt text as placeholder; actual images handled at block level
            var attr = AttributedString(alt.isEmpty ? "[image]" : alt)
            attr.font = style.italicized().font
            attr.foregroundColor = .secondary
            return attr

        case .wikilink(let target, let alias):
            let display = alias ?? target.notePath ?? target.heading ?? target.blockID ?? ""
            var attr = AttributedString(display)
            attr.font = style.font
            attr.foregroundColor = RenderStyle.wikilinkColor
            let encoded =
                target.rawTargetString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? target.rawTargetString
            attr.link = URL(string: "wikilink:///\(encoded)")
            return attr

        case .embed(let target, _):
            // Inline embed reference; standalone embeds handled at block level
            var attr = AttributedString(target.notePath ?? target.heading ?? target.blockID ?? "")
            attr.font = style.font
            attr.foregroundColor = RenderStyle.embedColor
            return attr

        case .comment:
            // Comments are invisible in rendered output
            return AttributedString()

        case .inlineLatex(let latex):
            // Render LaTeX source styled; actual math rendering is future work
            var attr = AttributedString(latex)
            attr.font = style.monospaced().font
            attr.foregroundColor = RenderStyle.latexColor
            return attr

        case .displayLatex(let latex):
            var attr = AttributedString(latex)
            attr.font = style.monospaced().font
            attr.foregroundColor = RenderStyle.latexColor
            return attr

        case .inlineFootnote(let children):
            // Render as superscript-styled parenthetical
            var result = render(children, style: style.sized(style.size * 0.8))
            result.foregroundColor = .secondary
            let open = styledText("(", style: style.sized(style.size * 0.8))
            let close = styledText(")", style: style.sized(style.size * 0.8))
            var combined = open
            combined.append(result)
            combined.append(close)
            return combined

        case .blockReference(let id):
            var attr = AttributedString("^" + id)
            attr.font = style.font
            attr.foregroundColor = .secondary
            return attr

        case .autolink(let url):
            var attr = AttributedString(url)
            attr.font = style.font
            attr.foregroundColor = RenderStyle.linkColor
            attr.underlineStyle = .single
            if let parsed = URL(string: url) {
                attr.link = parsed
            }
            return attr

        case .hardLineBreak:
            return AttributedString("\n")

        case .softLineBreak:
            return AttributedString(" ")
        }
    }

    private static func styledText(_ text: String, style: RenderStyle) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = style.font
        return attr
    }

}

// MARK: - Render Style

/// Tracks accumulated font traits for recursive inline rendering.
struct RenderStyle {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isMonospace: Bool = false
    var size: CGFloat = 16

    var font: Font {
        var f: Font
        if isMonospace {
            f = .system(size: size, design: .monospaced)
        } else {
            f = .system(size: size)
        }
        if isBold { f = f.bold() }
        if isItalic { f = f.italic() }
        return f
    }

    func bolded() -> RenderStyle { var c = self; c.isBold = true; return c }
    func italicized() -> RenderStyle { var c = self; c.isItalic = true; return c }
    func monospaced() -> RenderStyle { var c = self; c.isMonospace = true; return c }
    func sized(_ s: CGFloat) -> RenderStyle { var c = self; c.size = s; return c }

    static func body(size: CGFloat = 16) -> RenderStyle {
        RenderStyle(size: size)
    }

    static func heading(level: Int, baseSize: CGFloat = 16) -> RenderStyle {
        let scales: [CGFloat] = [2.0, 1.625, 1.375, 1.125, 1.0, 0.9375]
        let scale = (level >= 1 && level <= 6) ? scales[level - 1] : 1.0
        return RenderStyle(isBold: true, size: baseSize * scale)
    }

    /// The NSFont size for LaTeX rendering that matches this style's body size.
    /// The 2x factor compensates for MathJax's internal scaling.
    static func latexFontSize(for baseSize: CGFloat) -> CGFloat {
        baseSize * 2.0
    }

    // Semantic colors
    static let linkColor: Color = .blue
    static let wikilinkColor: Color = .blue
    static let embedColor: Color = .teal
    static let codeColor: Color = .green.opacity(0.9)
    static let codeBackground: Color = .gray.opacity(0.12)
    static let latexColor: Color = .orange
}
