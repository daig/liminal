import CambiumASTSupport
import CambiumCore
import CambiumSyntaxMacros

public protocol LiminalSyntaxNode: TypedSyntaxNode, Sendable, Hashable
    where Lang == LiminalLanguage
{
    static var kind: LiminalKind { get }

    var syntax: SyntaxNodeHandle<LiminalLanguage> { get }

    init(unchecked syntax: SyntaxNodeHandle<LiminalLanguage>)
}

public extension LiminalSyntaxNode {
    static var rawKind: RawSyntaxKind {
        LiminalLanguage.rawKind(for: kind)
    }

    init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        guard syntax.rawKind == Self.rawKind else {
            return nil
        }
        self.init(unchecked: syntax)
    }

    var range: TextRange {
        syntax.textRange
    }

    var sourceText: String {
        syntax.withCursor { node in
            node.makeString()
        }
    }
}

public struct LiminalTokenSyntax: Sendable, Hashable {
    public let syntax: SyntaxTokenHandle<LiminalLanguage>

    public init(_ syntax: SyntaxTokenHandle<LiminalLanguage>) {
        self.syntax = syntax
    }

    public var kind: LiminalKind {
        syntax.withCursor { token in
            token.kind
        }
    }

    public var range: TextRange {
        syntax.withCursor { token in
            token.textRange
        }
    }

    public var text: String {
        syntax.withCursor { token in
            token.makeString()
        }
    }

    public func withTextUTF8<R>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> R
    ) throws -> R {
        try syntax.withCursor { token in
            try token.withTextUTF8(body)
        }
    }
}

public enum DocumentItemSyntax: Sendable, Hashable {
    case blankLine(BlankLineSyntax)
    case paragraph(ParagraphSyntax)
    case atxHeading(AtxHeadingSyntax)
    case wikiEmbedBlock(WikiEmbedBlockSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .blankLine:
            self = .blankLine(BlankLineSyntax(unchecked: syntax))
        case .paragraph:
            self = .paragraph(ParagraphSyntax(unchecked: syntax))
        case .atxHeading:
            self = .atxHeading(AtxHeadingSyntax(unchecked: syntax))
        case .wikiEmbedBlock:
            self = .wikiEmbedBlock(WikiEmbedBlockSyntax(unchecked: syntax))
        default:
            return nil
        }
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {
        case .blankLine(let item):
            item.syntax
        case .paragraph(let item):
            item.syntax
        case .atxHeading(let item):
            item.syntax
        case .wikiEmbedBlock(let item):
            item.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .blankLine(let item):
            item.range
        case .paragraph(let item):
            item.range
        case .atxHeading(let item):
            item.range
        case .wikiEmbedBlock(let item):
            item.range
        }
    }
}

public enum BlockSyntax: Sendable, Hashable {
    case paragraph(ParagraphSyntax)
    case atxHeading(AtxHeadingSyntax)
    case wikiEmbedBlock(WikiEmbedBlockSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .paragraph:
            self = .paragraph(ParagraphSyntax(unchecked: syntax))
        case .atxHeading:
            self = .atxHeading(AtxHeadingSyntax(unchecked: syntax))
        case .wikiEmbedBlock:
            self = .wikiEmbedBlock(WikiEmbedBlockSyntax(unchecked: syntax))
        default:
            return nil
        }
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {
        case .paragraph(let block):
            block.syntax
        case .atxHeading(let block):
            block.syntax
        case .wikiEmbedBlock(let block):
            block.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .paragraph(let block):
            block.range
        case .atxHeading(let block):
            block.range
        case .wikiEmbedBlock(let block):
            block.range
        }
    }
}

public enum InlineSyntax: Sendable, Hashable {
    case codeSpan(CodeSpanSyntax)
    case mdLink(MdLinkSyntax)
    case mdImage(MdImageSyntax)
    case wikilink(WikilinkSyntax)
    case wikiEmbed(WikiEmbedSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .codeSpan:
            self = .codeSpan(CodeSpanSyntax(unchecked: syntax))
        case .mdLink:
            self = .mdLink(MdLinkSyntax(unchecked: syntax))
        case .mdImage:
            self = .mdImage(MdImageSyntax(unchecked: syntax))
        case .wikilink:
            self = .wikilink(WikilinkSyntax(unchecked: syntax))
        case .wikiEmbed:
            self = .wikiEmbed(WikiEmbedSyntax(unchecked: syntax))
        default:
            return nil
        }
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {
        case .codeSpan(let inline):
            inline.syntax
        case .mdLink(let inline):
            inline.syntax
        case .mdImage(let inline):
            inline.syntax
        case .wikilink(let inline):
            inline.syntax
        case .wikiEmbed(let inline):
            inline.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .codeSpan(let inline):
            inline.range
        case .mdLink(let inline):
            inline.range
        case .mdImage(let inline):
            inline.range
        case .wikilink(let inline):
            inline.range
        case .wikiEmbed(let inline):
            inline.range
        }
    }
}

public enum ValueSyntax: Sendable, Hashable {
    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        _ = syntax
        return nil
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {}
    }

    public var range: TextRange {
        switch self {}
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .blankLine)
public struct BlankLineSyntax: LiminalSyntaxNode {}

@CambiumSyntaxNode(LiminalKind.self, for: .paragraph)
public struct ParagraphSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .atxHeading)
public struct AtxHeadingSyntax: LiminalSyntaxNode {
    public var markerToken: LiminalTokenSyntax? {
        firstToken(kind: .hashRun)
    }

    public var level: Int {
        markerToken?.text.count ?? 0
    }

    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikiEmbedBlock)
public struct WikiEmbedBlockSyntax: LiminalSyntaxNode {
    public var targetText: String {
        firstDescendantToken(kind: .wikiTargetText)?.text ?? ""
    }

    public var payloadText: String? {
        firstToken(kind: .rawPayloadText)?.text
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .inlineContent)
public struct InlineContentSyntax: LiminalSyntaxNode {
    public var inlineNodes: [InlineSyntax] {
        childNodes().compactMap(InlineSyntax.init)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .codeSpan)
public struct CodeSpanSyntax: LiminalSyntaxNode {
    public var codeText: String {
        firstToken(kind: .codeText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .mdLink)
public struct MdLinkSyntax: LiminalSyntaxNode {
    public var labelContent: InlineContentSyntax? {
        firstChild(kind: .linkLabel)?
            .firstChild(kind: .inlineContent)
            .map(InlineContentSyntax.init(unchecked:))
    }

    public var destinationText: String {
        firstChild(kind: .linkDestination)?
            .firstToken(kind: .linkDestinationText)?
            .text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .mdImage)
public struct MdImageSyntax: LiminalSyntaxNode {
    public var altContent: InlineContentSyntax? {
        firstChild(kind: .linkLabel)?
            .firstChild(kind: .inlineContent)
            .map(InlineContentSyntax.init(unchecked:))
    }

    public var destinationText: String {
        firstChild(kind: .linkDestination)?
            .firstToken(kind: .linkDestinationText)?
            .text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikilink)
public struct WikilinkSyntax: LiminalSyntaxNode {
    public var targetText: String {
        firstChild(kind: .wikiTarget)?
            .firstToken(kind: .wikiTargetText)?
            .text ?? ""
    }

    public var aliasContent: InlineContentSyntax? {
        childNodes(kind: .inlineContent).first.map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikiEmbed)
public struct WikiEmbedSyntax: LiminalSyntaxNode {
    public var targetText: String {
        firstChild(kind: .wikiTarget)?
            .firstToken(kind: .wikiTargetText)?
            .text ?? ""
    }

    public var payloadText: String? {
        firstToken(kind: .rawPayloadText)?.text
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .root)
public struct RootSyntax: LiminalSyntaxNode {
    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }

    public var tokens: [LiminalTokenSyntax] {
        directTokens()
    }

    public func tokens(kind: LiminalKind) -> [LiminalTokenSyntax] {
        directTokens(kind: kind)
    }

    public var rawPayloadToken: LiminalTokenSyntax? {
        firstToken(kind: .rawPayloadText)
    }
}

internal extension LiminalSyntaxNode {
    func childNodes() -> [SyntaxNodeHandle<LiminalLanguage>] {
        syntax.withCursor { node in
            var result: [SyntaxNodeHandle<LiminalLanguage>] = []
            node.forEachChild { child in
                result.append(child.makeHandle())
            }
            return result
        }
    }

    func childNodes(kind: LiminalKind) -> [SyntaxNodeHandle<LiminalLanguage>] {
        childNodes().filter { LiminalLanguage.kind(for: $0.rawKind) == kind }
    }

    func firstChild(kind: LiminalKind) -> SyntaxNodeHandle<LiminalLanguage>? {
        syntax.firstChild(kind: kind)
    }

    func directTokens(kind: LiminalKind? = nil) -> [LiminalTokenSyntax] {
        syntax.withCursor { node in
            var result: [LiminalTokenSyntax] = []
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where kind == nil || token.kind == kind:
                    result.append(LiminalTokenSyntax(token.makeHandle()))
                default:
                    break
                }
            }
            return result
        }
    }

    func firstToken(kind: LiminalKind) -> LiminalTokenSyntax? {
        directTokens(kind: kind).first
    }

    func firstDescendantToken(kind: LiminalKind) -> LiminalTokenSyntax? {
        syntax.firstDescendantToken(kind: kind)
    }
}

internal extension SyntaxNodeHandle where Lang == LiminalLanguage {
    func firstChild(kind: LiminalKind) -> SyntaxNodeHandle<LiminalLanguage>? {
        withCursor { node in
            var result: SyntaxNodeHandle<LiminalLanguage>?
            node.forEachChild { child in
                if result == nil, child.kind == kind {
                    result = child.makeHandle()
                }
            }
            return result
        }
    }

    func firstToken(kind: LiminalKind) -> LiminalTokenSyntax? {
        withCursor { node in
            var result: LiminalTokenSyntax?
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where result == nil && token.kind == kind:
                    result = LiminalTokenSyntax(token.makeHandle())
                default:
                    break
                }
            }
            return result
        }
    }

    func firstDescendantToken(kind: LiminalKind) -> LiminalTokenSyntax? {
        if let direct = firstToken(kind: kind) {
            return direct
        }

        return withCursor { node in
            var result: LiminalTokenSyntax?
            node.forEachChild { child in
                if result == nil {
                    result = child.makeHandle().firstDescendantToken(kind: kind)
                }
            }
            return result
        }
    }
}
