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
    case list(ListSyntax)
    case blockQuote(BlockQuoteSyntax)
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
        case .list:
            self = .list(ListSyntax(unchecked: syntax))
        case .blockQuote:
            self = .blockQuote(BlockQuoteSyntax(unchecked: syntax))
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
        case .list(let item):
            item.syntax
        case .blockQuote(let item):
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
        case .list(let item):
            item.range
        case .blockQuote(let item):
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
    case list(ListSyntax)
    case blockQuote(BlockQuoteSyntax)
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
        case .list:
            self = .list(ListSyntax(unchecked: syntax))
        case .blockQuote:
            self = .blockQuote(BlockQuoteSyntax(unchecked: syntax))
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
        case .list(let block):
            block.syntax
        case .blockQuote(let block):
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
        case .list(let block):
            block.range
        case .blockQuote(let block):
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

    /// Per v0.2 §6.4, a trailing `^block-id` on the opening paragraph of a
    /// list item attaches to the `ListItem`, not the paragraph: in that
    /// position the parser emits the suffix as a sibling of the paragraph
    /// inside the list item, and this accessor returns nil. Read
    /// `ListItemSyntax.blockIdToken` from the parent for list-item block IDs.
    /// Top-level paragraphs and paragraphs inside blockquote content keep
    /// the suffix as a direct child and return it here.
    public var blockIdToken: LiminalTokenSyntax? {
        firstChild(kind: .blockIdSuffix)
            .map(BlockIdSuffixSyntax.init(unchecked:))?
            .blockIdToken
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

    public var blockIdToken: LiminalTokenSyntax? {
        firstChild(kind: .blockIdSuffix)
            .map(BlockIdSuffixSyntax.init(unchecked:))?
            .blockIdToken
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .blockIdSuffix)
public struct BlockIdSuffixSyntax: LiminalSyntaxNode {
    public var blockIdToken: LiminalTokenSyntax? {
        firstToken(kind: .anchor)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikiEmbedBlock)
public struct WikiEmbedBlockSyntax: LiminalSyntaxNode {
    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .wikiTarget)?
            .firstToken(kind: .wikiTargetText)
    }

    public var targetText: String {
        targetTextToken?.text ?? ""
    }

    public var payloadToken: LiminalTokenSyntax? {
        firstToken(kind: .rawPayloadText)
    }

    public var payloadText: String? {
        payloadToken?.text
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

@CambiumSyntaxNode(LiminalKind.self, for: .list)
public struct ListSyntax: LiminalSyntaxNode {
    public var items: [ListItemSyntax] {
        childNodes(kind: .listItem).map(ListItemSyntax.init(unchecked:))
    }

    public var unorderedMarkerToken: LiminalTokenSyntax? {
        firstDescendantToken(kind: .listMarker)
    }

    public var orderedMarkerToken: LiminalTokenSyntax? {
        firstDescendantToken(kind: .orderedListMarker)
    }

    public var markerText: String {
        unorderedMarkerToken?.text ?? orderedMarkerToken?.text ?? ""
    }

    public var isOrdered: Bool {
        orderedMarkerToken != nil
    }

    public var startNumber: Int? {
        guard let marker = orderedMarkerToken?.text.dropLast(),
              !marker.isEmpty
        else {
            return nil
        }
        return Int(String(marker))
    }
}

public enum TaskMarkerState: Sendable, Hashable {
    case unchecked
    case checked
}

@CambiumSyntaxNode(LiminalKind.self, for: .listItem)
public struct ListItemSyntax: LiminalSyntaxNode {
    public var taskMarkerToken: LiminalTokenSyntax? {
        firstToken(kind: .taskMarker)
    }

    public var taskState: TaskMarkerState? {
        switch taskMarkerToken?.text {
        case "[ ]":
            .unchecked
        case "[x]", "[X]":
            .checked
        default:
            nil
        }
    }

    /// The trailing `^block-id` anchor token from the list item's opening
    /// paragraph, per v0.2 §6.4. The parser emits the suffix as a direct
    /// child of the list item (sibling of the contained paragraph), so the
    /// opening `ParagraphSyntax.blockIdToken` returns nil and this accessor
    /// owns the ID for the whole item.
    public var blockIdToken: LiminalTokenSyntax? {
        firstChild(kind: .blockIdSuffix)
            .map(BlockIdSuffixSyntax.init(unchecked:))?
            .blockIdToken
    }

    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .blockQuote)
public struct BlockQuoteSyntax: LiminalSyntaxNode {
    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
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
        targetTextToken?.text ?? ""
    }

    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)
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
        destinationTextToken?.text ?? ""
    }

    public var destinationTextToken: LiminalTokenSyntax? {
        firstChild(kind: .linkDestination)?
            .firstToken(kind: .linkDestinationText)
    }

    public var titleText: String? {
        titleTextToken?.text
    }

    public var titleTextToken: LiminalTokenSyntax? {
        firstChild(kind: .linkDestination)?
            .firstChild(kind: .linkTitle)?
            .firstToken(kind: .linkTitleText)
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
        destinationTextToken?.text ?? ""
    }

    public var destinationTextToken: LiminalTokenSyntax? {
        firstChild(kind: .linkDestination)?
            .firstToken(kind: .linkDestinationText)
    }

    public var titleText: String? {
        titleTextToken?.text
    }

    public var titleTextToken: LiminalTokenSyntax? {
        firstChild(kind: .linkDestination)?
            .firstChild(kind: .linkTitle)?
            .firstToken(kind: .linkTitleText)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikilink)
public struct WikilinkSyntax: LiminalSyntaxNode {
    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .wikiTarget)?
            .firstToken(kind: .wikiTargetText)
    }

    public var targetText: String {
        targetTextToken?.text ?? ""
    }

    public var aliasContent: InlineContentSyntax? {
        childNodes(kind: .inlineContent).first.map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .wikiEmbed)
public struct WikiEmbedSyntax: LiminalSyntaxNode {
    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .wikiTarget)?
            .firstToken(kind: .wikiTargetText)
    }

    public var targetText: String {
        targetTextToken?.text ?? ""
    }

    public var payloadToken: LiminalTokenSyntax? {
        firstToken(kind: .rawPayloadText)
    }

    public var payloadText: String? {
        payloadToken?.text
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
        targetTextToken?.text ?? ""
    }

    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)
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
        targetTextToken?.text ?? ""
    }

    public var targetTextToken: LiminalTokenSyntax? {
        firstChild(kind: .embedTarget)?
            .firstToken(kind: .embedTargetText)
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

public extension InlineContentSyntax {
    var plainText: String {
        syntax.withCursor { node in
            var result = ""
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where token.kind == .inlineText:
                    result += token.makeString()
                case .node(let child) where child.kind == .softBreak:
                    result += " "
                case .node(let child) where child.kind == .hardBreak:
                    result += "\n"
                case .node(let child):
                    result += InlineSyntax(child.makeHandle())?.plainText ?? ""
                default:
                    break
                }
            }
            return result
        }
    }
}

private extension InlineSyntax {
    var plainText: String {
        switch self {
        case .codeSpan(let codeSpan):
            codeSpan.codeText
        case .escapedPunctuation(let punctuation):
            punctuation.escapedText
        case .mdLink(let link):
            link.labelContent?.plainText ?? ""
        case .mdImage(let image):
            image.altContent?.plainText ?? ""
        case .wikilink(let wikilink):
            wikilink.aliasContent?.plainText ?? wikilink.targetText
        case .wikiEmbed(let embed):
            embed.payloadText ?? embed.targetText
        case .typedInline(let typedInline):
            typedInline.constructor?.inlineContent?.plainText ?? ""
        case .structuredEmbed(let embed):
            embed.fallbackContent?.plainText ?? embed.targetText
        }
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
