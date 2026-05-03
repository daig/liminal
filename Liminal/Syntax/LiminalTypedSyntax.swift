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
    case valueDeclaration(ValueDeclarationSyntax)
    case typedBlock(TypedBlockSyntax)
    case mathBlock(MathBlockSyntax)
    case htmlBlock(HtmlBlockSyntax)
    case structuredEmbedBlock(StructuredEmbedBlockSyntax)
    case wikiEmbedBlock(WikiEmbedBlockSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .blankLine:
            self = .blankLine(BlankLineSyntax(unchecked: syntax))
        case .paragraph:
            self = .paragraph(ParagraphSyntax(unchecked: syntax))
        case .atxHeading:
            self = .atxHeading(AtxHeadingSyntax(unchecked: syntax))
        case .valueDeclaration:
            self = .valueDeclaration(ValueDeclarationSyntax(unchecked: syntax))
        case .typedBlock:
            self = .typedBlock(TypedBlockSyntax(unchecked: syntax))
        case .mathBlock:
            self = .mathBlock(MathBlockSyntax(unchecked: syntax))
        case .htmlBlock:
            self = .htmlBlock(HtmlBlockSyntax(unchecked: syntax))
        case .structuredEmbedBlock:
            self = .structuredEmbedBlock(StructuredEmbedBlockSyntax(unchecked: syntax))
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
        case .valueDeclaration(let item):
            item.syntax
        case .typedBlock(let item):
            item.syntax
        case .mathBlock(let item):
            item.syntax
        case .htmlBlock(let item):
            item.syntax
        case .structuredEmbedBlock(let item):
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
        case .valueDeclaration(let item):
            item.range
        case .typedBlock(let item):
            item.range
        case .mathBlock(let item):
            item.range
        case .htmlBlock(let item):
            item.range
        case .structuredEmbedBlock(let item):
            item.range
        case .wikiEmbedBlock(let item):
            item.range
        }
    }
}

public enum BlockSyntax: Sendable, Hashable {
    case paragraph(ParagraphSyntax)
    case atxHeading(AtxHeadingSyntax)
    case typedBlock(TypedBlockSyntax)
    case mathBlock(MathBlockSyntax)
    case htmlBlock(HtmlBlockSyntax)
    case structuredEmbedBlock(StructuredEmbedBlockSyntax)
    case wikiEmbedBlock(WikiEmbedBlockSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .paragraph:
            self = .paragraph(ParagraphSyntax(unchecked: syntax))
        case .atxHeading:
            self = .atxHeading(AtxHeadingSyntax(unchecked: syntax))
        case .typedBlock:
            self = .typedBlock(TypedBlockSyntax(unchecked: syntax))
        case .mathBlock:
            self = .mathBlock(MathBlockSyntax(unchecked: syntax))
        case .htmlBlock:
            self = .htmlBlock(HtmlBlockSyntax(unchecked: syntax))
        case .structuredEmbedBlock:
            self = .structuredEmbedBlock(StructuredEmbedBlockSyntax(unchecked: syntax))
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
        case .typedBlock(let block):
            block.syntax
        case .mathBlock(let block):
            block.syntax
        case .htmlBlock(let block):
            block.syntax
        case .structuredEmbedBlock(let block):
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
        case .typedBlock(let block):
            block.range
        case .mathBlock(let block):
            block.range
        case .htmlBlock(let block):
            block.range
        case .structuredEmbedBlock(let block):
            block.range
        case .wikiEmbedBlock(let block):
            block.range
        }
    }
}

public enum InlineSyntax: Sendable, Hashable {
    case codeSpan(CodeSpanSyntax)
    case escapedPunctuation(EscapedPunctuationSyntax)
    case mdLink(MdLinkSyntax)
    case mdImage(MdImageSyntax)
    case wikilink(WikilinkSyntax)
    case wikiEmbed(WikiEmbedSyntax)
    case typedInline(TypedInlineSyntax)
    case structuredEmbed(StructuredEmbedSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .codeSpan:
            self = .codeSpan(CodeSpanSyntax(unchecked: syntax))
        case .escapedPunctuation:
            self = .escapedPunctuation(EscapedPunctuationSyntax(unchecked: syntax))
        case .mdLink:
            self = .mdLink(MdLinkSyntax(unchecked: syntax))
        case .mdImage:
            self = .mdImage(MdImageSyntax(unchecked: syntax))
        case .wikilink:
            self = .wikilink(WikilinkSyntax(unchecked: syntax))
        case .wikiEmbed:
            self = .wikiEmbed(WikiEmbedSyntax(unchecked: syntax))
        case .typedInline:
            self = .typedInline(TypedInlineSyntax(unchecked: syntax))
        case .structuredEmbed:
            self = .structuredEmbed(StructuredEmbedSyntax(unchecked: syntax))
        default:
            return nil
        }
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {
        case .codeSpan(let inline):
            inline.syntax
        case .escapedPunctuation(let inline):
            inline.syntax
        case .mdLink(let inline):
            inline.syntax
        case .mdImage(let inline):
            inline.syntax
        case .wikilink(let inline):
            inline.syntax
        case .wikiEmbed(let inline):
            inline.syntax
        case .typedInline(let inline):
            inline.syntax
        case .structuredEmbed(let inline):
            inline.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .codeSpan(let inline):
            inline.range
        case .escapedPunctuation(let inline):
            inline.range
        case .mdLink(let inline):
            inline.range
        case .mdImage(let inline):
            inline.range
        case .wikilink(let inline):
            inline.range
        case .wikiEmbed(let inline):
            inline.range
        case .typedInline(let inline):
            inline.range
        case .structuredEmbed(let inline):
            inline.range
        }
    }
}

public enum ValueSyntax: Sendable, Hashable {
    case scalar(ScalarValueSyntax)
    case list(ListValueSyntax)
    case record(RecordValueSyntax)
    case typedConstructor(TypedConstructorSyntax)
    case inlineLiteral(InlineLiteralSyntax)
    case blockLiteral(BlockLiteralSyntax)
    case reference(ReferenceSyntax)
    case structuredEmbedValue(StructuredEmbedValueSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .scalarValue:
            self = .scalar(ScalarValueSyntax(unchecked: syntax))
        case .listValue:
            self = .list(ListValueSyntax(unchecked: syntax))
        case .recordValue:
            self = .record(RecordValueSyntax(unchecked: syntax))
        case .typedConstructor:
            self = .typedConstructor(TypedConstructorSyntax(unchecked: syntax))
        case .inlineLiteral:
            self = .inlineLiteral(InlineLiteralSyntax(unchecked: syntax))
        case .blockLiteral:
            self = .blockLiteral(BlockLiteralSyntax(unchecked: syntax))
        case .reference:
            self = .reference(ReferenceSyntax(unchecked: syntax))
        case .structuredEmbedValue:
            self = .structuredEmbedValue(StructuredEmbedValueSyntax(unchecked: syntax))
        default:
            return nil
        }
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {
        case .scalar(let value):
            value.syntax
        case .list(let value):
            value.syntax
        case .record(let value):
            value.syntax
        case .typedConstructor(let value):
            value.syntax
        case .inlineLiteral(let value):
            value.syntax
        case .blockLiteral(let value):
            value.syntax
        case .reference(let value):
            value.syntax
        case .structuredEmbedValue(let value):
            value.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .scalar(let value):
            value.range
        case .list(let value):
            value.range
        case .record(let value):
            value.range
        case .typedConstructor(let value):
            value.range
        case .inlineLiteral(let value):
            value.range
        case .blockLiteral(let value):
            value.range
        case .reference(let value):
            value.range
        case .structuredEmbedValue(let value):
            value.range
        }
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

@CambiumSyntaxNode(LiminalKind.self, for: .valueDeclaration)
public struct ValueDeclarationSyntax: LiminalSyntaxNode {
    public var constructor: TypedConstructorSyntax? {
        firstChild(kind: .typedConstructor).map(TypedConstructorSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .typedBlock)
public struct TypedBlockSyntax: LiminalSyntaxNode {
    public var typeName: String {
        firstToken(kind: .qname)?.text ?? ""
    }

    public var idText: String? {
        firstToken(kind: .anchor)?.text
    }

    public var fields: FieldsSyntax? {
        firstChild(kind: .fields).map(FieldsSyntax.init(unchecked:))
    }

    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .mathBlock)
public struct MathBlockSyntax: LiminalSyntaxNode {
    public var texText: String {
        firstToken(kind: .rawPayloadText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .htmlBlock)
public struct HtmlBlockSyntax: LiminalSyntaxNode {
    public var rawText: String {
        firstToken(kind: .rawPayloadText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .structuredEmbedBlock)
public struct StructuredEmbedBlockSyntax: LiminalSyntaxNode {
    public var expectedType: String? {
        firstToken(kind: .qname)?.text
    }

    public var fallbackContent: InlineContentSyntax? {
        firstChild(kind: .linkLabel)?
            .firstChild(kind: .inlineContent)
            .map(InlineContentSyntax.init(unchecked:))
    }

    public var targetText: String {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)?
            .text ?? ""
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

@CambiumSyntaxNode(LiminalKind.self, for: .escapedPunctuation)
public struct EscapedPunctuationSyntax: LiminalSyntaxNode {
    public var escapedText: String {
        directTokens().dropFirst().map(\.text).joined()
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

    public var titleText: String? {
        firstChild(kind: .linkDestination)?
            .firstChild(kind: .linkTitle)?
            .firstToken(kind: .linkTitleText)?
            .text
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

    public var titleText: String? {
        firstChild(kind: .linkDestination)?
            .firstChild(kind: .linkTitle)?
            .firstToken(kind: .linkTitleText)?
            .text
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

@CambiumSyntaxNode(LiminalKind.self, for: .typedInline)
public struct TypedInlineSyntax: LiminalSyntaxNode {
    public var constructor: TypedConstructorSyntax? {
        firstChild(kind: .typedConstructor).map(TypedConstructorSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .structuredEmbed)
public struct StructuredEmbedSyntax: LiminalSyntaxNode {
    public var expectedType: String? {
        firstToken(kind: .qname)?.text
    }

    public var fallbackContent: InlineContentSyntax? {
        firstChild(kind: .linkLabel)?
            .firstChild(kind: .inlineContent)
            .map(InlineContentSyntax.init(unchecked:))
    }

    public var targetText: String {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)?
            .text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .typedConstructor)
public struct TypedConstructorSyntax: LiminalSyntaxNode {
    public var typeName: String {
        firstToken(kind: .qname)?.text ?? ""
    }

    public var idText: String? {
        firstToken(kind: .anchor)?.text
    }

    public var fields: FieldsSyntax? {
        firstChild(kind: .fields).map(FieldsSyntax.init(unchecked:))
    }

    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .fields)
public struct FieldsSyntax: LiminalSyntaxNode {
    public var fields: [FieldSyntax] {
        childNodes(kind: .field).map(FieldSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .field)
public struct FieldSyntax: LiminalSyntaxNode {
    public var name: String {
        firstToken(kind: .fieldName)?.text ?? ""
    }

    public var value: ValueNodeSyntax? {
        firstChild(kind: .value).map(ValueNodeSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .value)
public struct ValueNodeSyntax: LiminalSyntaxNode {
    public var payload: ValueSyntax? {
        childNodes().compactMap(ValueSyntax.init).first
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .scalarValue)
public struct ScalarValueSyntax: LiminalSyntaxNode {
    public var token: LiminalTokenSyntax? {
        directTokens().first
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .listValue)
public struct ListValueSyntax: LiminalSyntaxNode {
    public var values: [ValueNodeSyntax] {
        childNodes(kind: .value).map(ValueNodeSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .recordValue)
public struct RecordValueSyntax: LiminalSyntaxNode {
    public var fields: FieldsSyntax? {
        firstChild(kind: .fields).map(FieldsSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .inlineLiteral)
public struct InlineLiteralSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .blockLiteral)
public struct BlockLiteralSyntax: LiminalSyntaxNode {
    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .reference)
public struct ReferenceSyntax: LiminalSyntaxNode {
    public var qnameText: String? {
        firstToken(kind: .qname)?.text
    }

    public var externalTargetText: String? {
        firstToken(kind: .externalReferenceText)?.text
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .structuredEmbedValue)
public struct StructuredEmbedValueSyntax: LiminalSyntaxNode {
    public var expectedType: String? {
        firstToken(kind: .qname)?.text
    }

    public var fallbackContent: InlineContentSyntax? {
        firstChild(kind: .linkLabel)?
            .firstChild(kind: .inlineContent)
            .map(InlineContentSyntax.init(unchecked:))
    }

    public var targetText: String {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)?
            .text ?? ""
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
