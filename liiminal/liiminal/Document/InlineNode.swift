import Foundation

/// A structural inline element within a markdown block's content.
indirect enum InlineNode: Equatable, Sendable {
    // Containers (have children that are themselves inline nodes)
    case emphasis(children: [InlineNode], delimiter: Character)
    case strong(children: [InlineNode], delimiter: Character)
    case strikethrough(children: [InlineNode])
    case highlight(children: [InlineNode])
    case link(children: [InlineNode], url: String, title: String?)
    case inlineFootnote(children: [InlineNode])

    // Leaves
    case text(String)
    case codeSpan(code: String, backtickCount: Int)
    case wikilink(target: WikiTarget, alias: String?)
    case embed(target: WikiTarget, params: String?)
    case image(alt: String, url: String, title: String?)
    case comment(String)
    case inlineLatex(String)
    case displayLatex(String)
    case blockReference(String)
    case autolink(String)
    case hardLineBreak
    case softLineBreak

    /// Characters this node occupies in serialized markdown source.
    var sourceLength: Int {
        switch self {
        case .text(let s):
            return s.count
        case .emphasis(let children, _):
            return 1 + children.totalSourceLength + 1
        case .strong(let children, _):
            return 2 + children.totalSourceLength + 2
        case .strikethrough(let children):
            return 2 + children.totalSourceLength + 2
        case .highlight(let children):
            return 2 + children.totalSourceLength + 2
        case .codeSpan(let code, let n):
            return n + code.count + n
        case .link(let children, let url, let title):
            if let t = title {
                return children.totalSourceLength + url.count + t.count + 7
            }
            return children.totalSourceLength + url.count + 4
        case .image(let alt, let url, let title):
            if let t = title {
                return alt.count + url.count + t.count + 8
            }
            return alt.count + url.count + 5
        case .wikilink(let target, let alias):
            if let a = alias {
                return target.rawTargetString.count + a.count + 5
            }
            return target.rawTargetString.count + 4
        case .embed(let target, let params):
            if let p = params {
                return target.rawTargetString.count + p.count + 6
            }
            return target.rawTargetString.count + 5
        case .comment(let s):
            return s.count + 4
        case .inlineLatex(let s):
            return s.count + 2
        case .displayLatex(let s):
            return s.count + 4
        case .inlineFootnote(let children):
            return children.totalSourceLength + 3
        case .blockReference(let id):
            return id.count + 1
        case .autolink(let url):
            return url.count + 2
        case .hardLineBreak:
            return 2
        case .softLineBreak:
            return 1
        }
    }

    /// Characters of visible/meaningful content, ignoring syntax delimiters.
    var contentLength: Int {
        switch self {
        case .text(let s):
            return s.count
        case .emphasis(let children, _):
            return children.totalContentLength
        case .strong(let children, _):
            return children.totalContentLength
        case .strikethrough(let children):
            return children.totalContentLength
        case .highlight(let children):
            return children.totalContentLength
        case .codeSpan(let code, _):
            return code.count
        case .link(let children, _, _):
            return children.totalContentLength
        case .image(let alt, _, _):
            return alt.count
        case .wikilink(let target, let alias):
            return (alias ?? target.notePath ?? target.heading ?? target.blockID ?? "").count
        case .embed(let target, let params):
            return (params ?? target.notePath ?? target.heading ?? target.blockID ?? "").count
        case .comment:
            return 0
        case .inlineLatex(let s):
            return s.count
        case .displayLatex(let s):
            return s.count
        case .inlineFootnote(let children):
            return children.totalContentLength
        case .blockReference(let id):
            return id.count + 1
        case .autolink(let url):
            return url.count
        case .hardLineBreak:
            return 1
        case .softLineBreak:
            return 1
        }
    }

    var children: [InlineNode] {
        switch self {
        case .emphasis(let c, _), .strong(let c, _), .strikethrough(let c),
            .highlight(let c), .link(let c, _, _), .inlineFootnote(let c):
            return c
        default:
            return []
        }
    }
}

extension [InlineNode] {
    var totalSourceLength: Int { reduce(0) { $0 + $1.sourceLength } }
    var totalContentLength: Int { reduce(0) { $0 + $1.contentLength } }
}
