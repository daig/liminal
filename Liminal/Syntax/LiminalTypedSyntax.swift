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

    /// True when the parser inserted a `.missing` child during recovery.
    /// Used by lowering to fall back to literal text per spec rules
    /// (e.g. §7.4 unmatched delimiters remain literal text).
    var isIncomplete: Bool {
        syntax.withCursor { node in
            var found = false
            node.forEachChild { child in
                if !found, child.kind == .missing {
                    found = true
                }
            }
            return found
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
    case frontmatter(FrontmatterSyntax)
    case directive(DirectiveSyntax)
    case schemaBlock(SchemaBlockSyntax)
    case templateBlock(TemplateBlockSyntax)
    case paragraph(ParagraphSyntax)
    case atxHeading(AtxHeadingSyntax)
    case valueDeclaration(ValueDeclarationSyntax)
    case typedBlock(TypedBlockSyntax)
    case fencedCodeBlock(FencedCodeBlockSyntax)
    case mathBlock(MathBlockSyntax)
    case htmlBlock(HtmlBlockSyntax)
    case commentBlock(CommentBlockSyntax)
    case list(ListSyntax)
    case blockQuote(BlockQuoteSyntax)
    case pipeTable(PipeTableSyntax)
    case structuredEmbedBlock(StructuredEmbedBlockSyntax)
    case wikiEmbedBlock(WikiEmbedBlockSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .blankLine:
            self = .blankLine(BlankLineSyntax(unchecked: syntax))
        case .frontmatter:
            self = .frontmatter(FrontmatterSyntax(unchecked: syntax))
        case .directive:
            self = .directive(DirectiveSyntax(unchecked: syntax))
        case .schemaBlock:
            self = .schemaBlock(SchemaBlockSyntax(unchecked: syntax))
        case .templateBlock:
            self = .templateBlock(TemplateBlockSyntax(unchecked: syntax))
        case .paragraph:
            self = .paragraph(ParagraphSyntax(unchecked: syntax))
        case .atxHeading:
            self = .atxHeading(AtxHeadingSyntax(unchecked: syntax))
        case .valueDeclaration:
            self = .valueDeclaration(ValueDeclarationSyntax(unchecked: syntax))
        case .typedBlock:
            self = .typedBlock(TypedBlockSyntax(unchecked: syntax))
        case .fencedCodeBlock:
            self = .fencedCodeBlock(FencedCodeBlockSyntax(unchecked: syntax))
        case .mathBlock:
            self = .mathBlock(MathBlockSyntax(unchecked: syntax))
        case .htmlBlock:
            self = .htmlBlock(HtmlBlockSyntax(unchecked: syntax))
        case .commentBlock:
            self = .commentBlock(CommentBlockSyntax(unchecked: syntax))
        case .list:
            self = .list(ListSyntax(unchecked: syntax))
        case .blockQuote:
            self = .blockQuote(BlockQuoteSyntax(unchecked: syntax))
        case .pipeTable:
            self = .pipeTable(PipeTableSyntax(unchecked: syntax))
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
        case .frontmatter(let item):
            item.syntax
        case .directive(let item):
            item.syntax
        case .schemaBlock(let item):
            item.syntax
        case .templateBlock(let item):
            item.syntax
        case .paragraph(let item):
            item.syntax
        case .atxHeading(let item):
            item.syntax
        case .valueDeclaration(let item):
            item.syntax
        case .typedBlock(let item):
            item.syntax
        case .fencedCodeBlock(let item):
            item.syntax
        case .mathBlock(let item):
            item.syntax
        case .htmlBlock(let item):
            item.syntax
        case .commentBlock(let item):
            item.syntax
        case .list(let item):
            item.syntax
        case .blockQuote(let item):
            item.syntax
        case .pipeTable(let item):
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
        case .frontmatter(let item):
            item.range
        case .directive(let item):
            item.range
        case .schemaBlock(let item):
            item.range
        case .templateBlock(let item):
            item.range
        case .paragraph(let item):
            item.range
        case .atxHeading(let item):
            item.range
        case .valueDeclaration(let item):
            item.range
        case .typedBlock(let item):
            item.range
        case .fencedCodeBlock(let item):
            item.range
        case .mathBlock(let item):
            item.range
        case .htmlBlock(let item):
            item.range
        case .commentBlock(let item):
            item.range
        case .list(let item):
            item.range
        case .blockQuote(let item):
            item.range
        case .pipeTable(let item):
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
    case fencedCodeBlock(FencedCodeBlockSyntax)
    case mathBlock(MathBlockSyntax)
    case htmlBlock(HtmlBlockSyntax)
    case commentBlock(CommentBlockSyntax)
    case list(ListSyntax)
    case blockQuote(BlockQuoteSyntax)
    case pipeTable(PipeTableSyntax)
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
        case .fencedCodeBlock:
            self = .fencedCodeBlock(FencedCodeBlockSyntax(unchecked: syntax))
        case .mathBlock:
            self = .mathBlock(MathBlockSyntax(unchecked: syntax))
        case .htmlBlock:
            self = .htmlBlock(HtmlBlockSyntax(unchecked: syntax))
        case .commentBlock:
            self = .commentBlock(CommentBlockSyntax(unchecked: syntax))
        case .list:
            self = .list(ListSyntax(unchecked: syntax))
        case .blockQuote:
            self = .blockQuote(BlockQuoteSyntax(unchecked: syntax))
        case .pipeTable:
            self = .pipeTable(PipeTableSyntax(unchecked: syntax))
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
        case .fencedCodeBlock(let block):
            block.syntax
        case .mathBlock(let block):
            block.syntax
        case .htmlBlock(let block):
            block.syntax
        case .commentBlock(let block):
            block.syntax
        case .list(let block):
            block.syntax
        case .blockQuote(let block):
            block.syntax
        case .pipeTable(let block):
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
        case .fencedCodeBlock(let block):
            block.range
        case .mathBlock(let block):
            block.range
        case .htmlBlock(let block):
            block.range
        case .commentBlock(let block):
            block.range
        case .list(let block):
            block.range
        case .blockQuote(let block):
            block.range
        case .pipeTable(let block):
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
    case strikethrough(StrikethroughSyntax)
    case highlight(HighlightSyntax)
    case mdLink(MdLinkSyntax)
    case mdImage(MdImageSyntax)
    case wikilink(WikilinkSyntax)
    case wikiEmbed(WikiEmbedSyntax)
    case typedInline(TypedInlineSyntax)
    case structuredEmbed(StructuredEmbedSyntax)
    case mathInline(MathInlineSyntax)
    case interpolation(InterpolationSyntax)
    case inlineComment(InlineCommentSyntax)
    case footnoteInline(FootnoteInlineSyntax)

    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        switch LiminalLanguage.kind(for: syntax.rawKind) {
        case .codeSpan:
            self = .codeSpan(CodeSpanSyntax(unchecked: syntax))
        case .escapedPunctuation:
            self = .escapedPunctuation(EscapedPunctuationSyntax(unchecked: syntax))
        case .strikethrough:
            self = .strikethrough(StrikethroughSyntax(unchecked: syntax))
        case .highlight:
            self = .highlight(HighlightSyntax(unchecked: syntax))
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
        case .mathInline:
            self = .mathInline(MathInlineSyntax(unchecked: syntax))
        case .interpolation:
            self = .interpolation(InterpolationSyntax(unchecked: syntax))
        case .inlineComment:
            self = .inlineComment(InlineCommentSyntax(unchecked: syntax))
        case .footnoteInline:
            self = .footnoteInline(FootnoteInlineSyntax(unchecked: syntax))
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
        case .strikethrough(let inline):
            inline.syntax
        case .highlight(let inline):
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
        case .mathInline(let inline):
            inline.syntax
        case .interpolation(let inline):
            inline.syntax
        case .inlineComment(let inline):
            inline.syntax
        case .footnoteInline(let inline):
            inline.syntax
        }
    }

    public var range: TextRange {
        switch self {
        case .codeSpan(let inline):
            inline.range
        case .escapedPunctuation(let inline):
            inline.range
        case .strikethrough(let inline):
            inline.range
        case .highlight(let inline):
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
        case .mathInline(let inline):
            inline.range
        case .interpolation(let inline):
            inline.range
        case .inlineComment(let inline):
            inline.range
        case .footnoteInline(let inline):
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

@CambiumSyntaxNode(LiminalKind.self, for: .frontmatter)
public struct FrontmatterSyntax: LiminalSyntaxNode {
    public var rawYamlText: String {
        directTokens(kind: .frontmatterText).map(\.text).joined()
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .directive)
public struct DirectiveSyntax: LiminalSyntaxNode {
    public var useDirective: UseDirectiveSyntax? {
        firstChild(kind: .useDirective).map(UseDirectiveSyntax.init(unchecked:))
    }

    public var keywordText: String {
        useDirective?.keywordText ?? ""
    }

    public var bodyText: String {
        useDirective?.bodyText ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .useDirective)
public struct UseDirectiveSyntax: LiminalSyntaxNode {
    public var keywordText: String {
        firstToken(kind: .identifier)?.text ?? ""
    }

    /// The full directive body following the `use` keyword and its
    /// trailing whitespace, derived from the underlying tokens. Slice 7
    /// callers depended on this string when the body was a single
    /// `.directiveText` token; Phase 3b.2 reconstructs it by stripping
    /// the `use` prefix from `sourceText`.
    public var bodyText: String {
        let text = sourceText
        guard text.hasPrefix("use") else { return text }
        var cursor = text.index(text.startIndex, offsetBy: 3)
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        return String(text[cursor..<text.endIndex])
    }

    /// The optional `UseKind` ("type" or "data") if the directive body
    /// supplies one before the target.
    public var kindText: String? {
        let identifiers = directTokens(kind: .identifier).map(\.text)
        guard identifiers.count >= 2 else { return nil }
        let candidate = identifiers[1]
        return (candidate == "type" || candidate == "data") ? candidate : nil
    }

    /// The interpreted target value: bare scalar text, or quoted string
    /// content with surrounding quotes stripped (escape decoding is
    /// deferred to the consumer that needs it).
    public var targetText: String {
        if let token = firstToken(kind: .quotedStringLiteral) {
            let raw = token.text
            if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
                return String(raw.dropFirst().dropLast())
            }
            return raw
        }
        if let token = firstToken(kind: .bareScalarLiteral) {
            return token.text
        }
        return ""
    }

    /// Whether the target was supplied as a quoted string. Useful when
    /// the consumer needs to distinguish raw paths from bare scalars
    /// (e.g., for escape-decoding policy).
    public var targetIsQuoted: Bool {
        firstToken(kind: .quotedStringLiteral) != nil
    }

    /// True iff an `only { … }` import filter is present, even when the
    /// filter list is empty. Distinguishes "no filter (import all)" from
    /// "explicit empty filter (import nothing)".
    public var hasFilter: Bool {
        directTokens(kind: .identifier).contains { $0.text == "only" }
    }

    /// QNames inside the optional `only { … }` filter, in source order.
    /// Empty when no filter is supplied or when the filter list itself is
    /// empty — use `hasFilter` to distinguish.
    public var filterQNames: [String] {
        directTokens(kind: .qname).map(\.text)
    }

    /// The optional alias identifier introduced by `as <ident>`.
    public var aliasText: String? {
        let identifiers = directTokens(kind: .identifier).map(\.text)
        guard let asIndex = identifiers.firstIndex(of: "as"),
              asIndex + 1 < identifiers.count
        else {
            return nil
        }
        return identifiers[asIndex + 1]
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .schemaBlock)
public struct SchemaBlockSyntax: LiminalSyntaxNode {
    public var header: SchemaHeaderSyntax? {
        firstChild(kind: .schemaHeader).map(SchemaHeaderSyntax.init(unchecked:))
    }

    public var body: SchemaBodySyntax? {
        firstChild(kind: .schemaBody).map(SchemaBodySyntax.init(unchecked:))
    }

    public var nameText: String? {
        header?.nameText
    }

    public var rawText: String {
        body?.sourceText ?? ""
    }

    public var declarations: [SchemaTypeDeclarationSyntax] {
        body?.declarations ?? []
    }

    public var templateDeclarations: [SchemaTemplateTypeDeclarationSyntax] {
        body?.templateDeclarations ?? []
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .schemaHeader)
public struct SchemaHeaderSyntax: LiminalSyntaxNode {
    public var keywordText: String {
        directTokens(kind: .identifier).first?.text ?? ""
    }

    public var nameText: String? {
        let identifiers = directTokens(kind: .identifier)
        guard identifiers.count > 1 else {
            return nil
        }
        return identifiers[1].text
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .schemaBody)
public struct SchemaBodySyntax: LiminalSyntaxNode {
    public var declarations: [SchemaTypeDeclarationSyntax] {
        childNodes(kind: .schemaTypeDeclaration).map(SchemaTypeDeclarationSyntax.init(unchecked:))
    }

    public var templateDeclarations: [SchemaTemplateTypeDeclarationSyntax] {
        childNodes(kind: .schemaTemplateTypeDeclaration).map(SchemaTemplateTypeDeclarationSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .schemaTypeDeclaration)
public struct SchemaTypeDeclarationSyntax: LiminalSyntaxNode {
    public var qnameText: String {
        firstToken(kind: .qname)?.text ?? ""
    }

    /// The discriminator identifier — the second `.identifier` token (the
    /// first being the literal `type` keyword). Returns the empty string
    /// when the declaration is malformed and the discriminator is missing.
    public var nodeKindText: String {
        let identifiers = directTokens(kind: .identifier)
        guard identifiers.count > 1 else {
            return ""
        }
        return identifiers[1].text
    }

    public var rhsText: String {
        firstToken(kind: .schemaText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .schemaTemplateTypeDeclaration)
public struct SchemaTemplateTypeDeclarationSyntax: LiminalSyntaxNode {
    public var qnameText: String {
        firstToken(kind: .qname)?.text ?? ""
    }

    public var nodeKindText: String {
        let identifiers = directTokens(kind: .identifier)
        guard identifiers.count > 1 else {
            return ""
        }
        return identifiers[1].text
    }

    /// Same accessor as `SchemaTypeDeclarationSyntax.rhsText` but named
    /// for the template surface where the RHS is the template signature.
    public var signatureText: String {
        firstToken(kind: .schemaText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .templateBlock)
public struct TemplateBlockSyntax: LiminalSyntaxNode {
    public var signature: TemplateSignatureSyntax? {
        firstChild(kind: .templateSignature).map(TemplateSignatureSyntax.init(unchecked:))
    }

    public var body: TemplateBodySyntax? {
        firstChild(kind: .templateBody).map(TemplateBodySyntax.init(unchecked:))
    }

    public var signatureText: String {
        signature?.rawText ?? ""
    }

    public var rawBodyText: String {
        body?.sourceText ?? ""
    }

    public var documentItems: [DocumentItemSyntax] {
        body?.documentItems ?? []
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .templateSignature)
public struct TemplateSignatureSyntax: LiminalSyntaxNode {
    public var rawText: String {
        firstToken(kind: .templateText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .templateBody)
public struct TemplateBodySyntax: LiminalSyntaxNode {
    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }
}

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

@CambiumSyntaxNode(LiminalKind.self, for: .fencedCodeBlock)
public struct FencedCodeBlockSyntax: LiminalSyntaxNode {
    public var infoText: String {
        firstToken(kind: .rawPayloadText)?.text ?? ""
    }

    public var normalizedInfoText: String {
        infoText.trimmingHorizontalWhitespace
    }

    public var languageText: String? {
        let trimmed = normalizedInfoText
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    public var codeText: String {
        firstToken(kind: .codeText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .mathBlock)
public struct MathBlockSyntax: LiminalSyntaxNode {
    public var texText: String {
        firstToken(kind: .mathText)?.text
            ?? firstToken(kind: .rawPayloadText)?.text
            ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .htmlBlock)
public struct HtmlBlockSyntax: LiminalSyntaxNode {
    public var rawText: String {
        firstToken(kind: .htmlText)?.text
            ?? firstToken(kind: .rawPayloadText)?.text
            ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .commentBlock)
public struct CommentBlockSyntax: LiminalSyntaxNode {
    public var rawText: String {
        firstToken(kind: .commentText)?.text ?? ""
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

public enum PipeTableAlignment: String, Sendable, Hashable {
    case left
    case center
    case right
}

@CambiumSyntaxNode(LiminalKind.self, for: .pipeTable)
public struct PipeTableSyntax: LiminalSyntaxNode {
    public var header: PipeTableHeaderSyntax? {
        firstChild(kind: .pipeTableHeader).map(PipeTableHeaderSyntax.init(unchecked:))
    }

    public var delimiter: PipeTableDelimiterSyntax? {
        firstChild(kind: .pipeTableDelimiter).map(PipeTableDelimiterSyntax.init(unchecked:))
    }

    public var rows: [PipeTableRowSyntax] {
        childNodes(kind: .pipeTableRow).map(PipeTableRowSyntax.init(unchecked:))
    }

    public var headerCells: [PipeTableCellSyntax] {
        header?.cells ?? []
    }

    public var alignments: [PipeTableAlignment?] {
        delimiter?.alignments ?? []
    }

    public var bodyRows: [[PipeTableCellSyntax]] {
        rows.map(\.cells)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .pipeTableHeader)
public struct PipeTableHeaderSyntax: LiminalSyntaxNode {
    public var cells: [PipeTableCellSyntax] {
        childNodes(kind: .pipeTableCell).map(PipeTableCellSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .pipeTableDelimiter)
public struct PipeTableDelimiterSyntax: LiminalSyntaxNode {
    public var cells: [PipeTableCellSyntax] {
        childNodes(kind: .pipeTableCell).map(PipeTableCellSyntax.init(unchecked:))
    }

    public var alignments: [PipeTableAlignment?] {
        cells.map(\.delimiterAlignment)
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .pipeTableRow)
public struct PipeTableRowSyntax: LiminalSyntaxNode {
    public var cells: [PipeTableCellSyntax] {
        childNodes(kind: .pipeTableCell).map(PipeTableCellSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .pipeTableCell)
public struct PipeTableCellSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }

    public var delimiterAlignment: PipeTableAlignment? {
        let trimmed = sourceText.trimmingHorizontalWhitespace
        let left = trimmed.hasPrefix(":")
        let right = trimmed.hasSuffix(":")
        switch (left, right) {
        case (true, true):
            return .center
        case (true, false):
            return .left
        case (false, true):
            return .right
        case (false, false):
            return nil
        }
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

@CambiumSyntaxNode(LiminalKind.self, for: .strikethrough)
public struct StrikethroughSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .highlight)
public struct HighlightSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
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

@CambiumSyntaxNode(LiminalKind.self, for: .mathInline)
public struct MathInlineSyntax: LiminalSyntaxNode {
    public var texText: String {
        firstToken(kind: .mathText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .interpolation)
public struct InterpolationSyntax: LiminalSyntaxNode {
    public var expressionText: String {
        firstToken(kind: .interpolationText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .inlineComment)
public struct InlineCommentSyntax: LiminalSyntaxNode {
    public var rawText: String {
        firstToken(kind: .commentText)?.text ?? ""
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .footnoteInline)
public struct FootnoteInlineSyntax: LiminalSyntaxNode {
    public var inlineContent: InlineContentSyntax? {
        firstChild(kind: .inlineContent).map(InlineContentSyntax.init(unchecked:))
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
        case .strikethrough(let strikethrough):
            strikethrough.inlineContent?.plainText ?? ""
        case .highlight(let highlight):
            highlight.inlineContent?.plainText ?? ""
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
        case .mathInline(let math):
            math.texText
        case .interpolation(let interpolation):
            interpolation.expressionText
        case .inlineComment:
            ""
        case .footnoteInline(let footnote):
            footnote.inlineContent?.plainText ?? ""
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

private extension String {
    var trimmingHorizontalWhitespace: String {
        var start = startIndex
        while start < endIndex, self[start].isHorizontalWhitespace {
            start = index(after: start)
        }

        var end = endIndex
        while end > start {
            let previous = index(before: end)
            guard self[previous].isHorizontalWhitespace else {
                break
            }
            end = previous
        }

        return String(self[start..<end])
    }
}

private extension Character {
    var isHorizontalWhitespace: Bool {
        self == " " || self == "\t"
    }
}
