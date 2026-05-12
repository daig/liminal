import CambiumCore

/// Semantic category derived from a token's `LiminalKind`. The theme maps
/// these to AppKit attributes (color, decoration). Kept AppKit-free so
/// tests can verify span classification without importing AppKit.
public enum HighlightCategory: Equatable, Sendable {
    case `default`         // inlineText, whitespace, plain content
    case delimiter         // hashRun, fenceRun, colonRun, list markers, punctuation
    case typeName          // qname
    case identifier        // identifier, fieldName, anchor
    case stringLiteral     // quotedStringLiteral
    case numberLiteral     // integer/number/boolean/null/bare scalar literals
    case linkText          // link destinations/titles, wiki/embed targets
    case codeContent       // codeText, mathText
    case rawContent        // raw payloads (HTML, schema, template, directive, frontmatter)
    case commentContent    // commentText
    case interpolation     // interpolationText
    case error             // errorText, .missing, .error sentinels
}

/// Inline modifiers contributed by ancestor nodes as the walker descends.
/// They compose: text inside `**_x_**` carries `[.strong, .emphasis]`.
public struct InlineModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let emphasis      = InlineModifiers(rawValue: 1 << 0)
    public static let strong        = InlineModifiers(rawValue: 1 << 1)
    public static let strikethrough = InlineModifiers(rawValue: 1 << 2)
    public static let highlight     = InlineModifiers(rawValue: 1 << 3)
    public static let heading       = InlineModifiers(rawValue: 1 << 4)
}

/// One contiguous run of source bytes with a uniform highlight category and
/// modifier set. Ranges are in UTF-8 byte coordinates; the AppKit layer
/// translates them to UTF-16 NSRanges before applying attributes.
public struct HighlightSpan: Equatable, Sendable {
    public let range: TextRange
    public let category: HighlightCategory
    public let modifiers: InlineModifiers

    public init(range: TextRange, category: HighlightCategory, modifiers: InlineModifiers) {
        self.range = range
        self.category = category
        self.modifiers = modifiers
    }
}

/// Walks the parsed tree and emits one `HighlightSpan` per token.
public struct LiminalHighlighter: Sendable {
    public init() {}

    /// Produce spans in source order for every token under `root`. The
    /// returned array's ranges are contiguous and non-overlapping (subject
    /// to the parser's guarantee that token ranges tile the source).
    public func spans(for root: RootSyntax) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        root.syntax.withCursor { cursor in
            Self.walk(
                cursor,
                modifiers: [],
                errorScope: false,
                byteRange: nil,
                into: &spans
            )
        }
        return spans
    }

    /// Produce spans for tokens whose byte ranges intersect `byteRange`.
    /// Prunes whole subtrees that fall entirely outside the range so the
    /// walker never enters paragraphs/blocks the caller isn't going to
    /// paint. Used on the per-keystroke highlight path, where the
    /// repaint scope is a few lines around the edit and walking the full
    /// tree to emit ~233K spans on a 1 MB document is the dominant cost.
    ///
    /// Modifier inheritance is preserved: an ancestor node's modifier
    /// applies to every descendant token in `byteRange` even if other
    /// descendants of that ancestor fall outside the range.
    public func spans(
        for root: RootSyntax,
        in byteRange: TextRange
    ) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        root.syntax.withCursor { cursor in
            Self.walk(
                cursor,
                modifiers: [],
                errorScope: false,
                byteRange: byteRange,
                into: &spans
            )
        }
        return spans
    }

    private static func walk(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        modifiers: InlineModifiers,
        errorScope: Bool,
        byteRange: TextRange?,
        into spans: inout [HighlightSpan]
    ) {
        if let byteRange, !cursor.textRange.intersects(byteRange) {
            return
        }

        let nodeKind = LiminalLanguage.kind(for: cursor.rawKind)
        let addedModifier = modifier(for: nodeKind) ?? []
        let childModifiers = modifiers.union(addedModifier)
        // Propagate "we're inside an error/missing subtree" downward so
        // every descendant token gets `.error` category regardless of its
        // own kind. This catches recovery sentinels comprehensively.
        let childErrorScope = errorScope || nodeKind == .missing || nodeKind == .error

        cursor.forEachChildOrToken { element in
            switch element {
            case .token(let token):
                if let byteRange, !token.textRange.intersects(byteRange) {
                    return
                }
                let tokenKind = LiminalLanguage.kind(for: token.rawKind)
                let category: HighlightCategory = childErrorScope ? .error : Self.category(for: tokenKind)
                spans.append(HighlightSpan(
                    range: token.textRange,
                    category: category,
                    modifiers: childModifiers
                ))
            case .node(let childCursor):
                walk(
                    childCursor,
                    modifiers: childModifiers,
                    errorScope: childErrorScope,
                    byteRange: byteRange,
                    into: &spans
                )
            }
        }
    }

    // MARK: - Kind dispatch

    /// Token-kind → highlight category. Exhaustive over the LiminalKind
    /// token range (10-99) plus the trivia kinds (1-2). New token kinds
    /// added to LiminalKind will fall through to `.default` until added
    /// here.
    static func category(for kind: LiminalKind) -> HighlightCategory {
        switch kind {
        // Trivia.
        case .whitespace, .newline:
            return .default

        // Static punctuation tokens and run-of-punctuation tokens.
        case .atSign, .bang, .ampersand, .hash, .caret, .dollar,
             .leftBracket, .rightBracket, .leftParen, .rightParen,
             .leftBrace, .rightBrace, .lessThan, .greaterThan,
             .comma, .colon, .pipe, .backtick, .tilde, .star,
             .underscore, .dash, .plus, .dot, .slash, .backslash,
             .percent, .equals, .questionMark, .singleQuote,
             .doubleQuote, .semicolon,
             .hashRun, .colonRun, .fenceRun,
             .listMarker, .orderedListMarker, .taskMarker:
            return .delimiter

        case .qname:
            return .typeName

        case .identifier, .fieldName, .anchor:
            return .identifier

        case .quotedStringLiteral:
            return .stringLiteral

        case .integerLiteral, .numberLiteral, .booleanLiteral,
             .nullLiteral, .bareScalarLiteral:
            return .numberLiteral

        case .linkDestinationText, .linkTitleText,
             .wikiTargetText, .embedTargetText, .externalReferenceText:
            return .linkText

        case .codeText, .mathText:
            return .codeContent

        case .rawPayloadText, .htmlText,
             .schemaText, .templateText, .directiveText, .frontmatterText:
            return .rawContent

        case .commentText:
            return .commentContent

        case .interpolationText:
            return .interpolation

        case .errorText:
            return .error

        case .inlineText:
            return .default

        default:
            // Node kinds shouldn't reach here (walker dispatches them).
            // Unknown / new kinds fall through to default.
            return .default
        }
    }

    /// Node-kind → modifier the node contributes to its descendants'
    /// styling. nil for nodes that don't add a style (most kinds).
    static func modifier(for kind: LiminalKind) -> InlineModifiers? {
        switch kind {
        case .emphasis:      return .emphasis
        case .strong:        return .strong
        case .strikethrough: return .strikethrough
        case .highlight:     return .highlight
        case .atxHeading:    return .heading
        default:             return nil
        }
    }
}
