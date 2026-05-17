import CambiumCore

/// Set-membership classification of every ``LiminalKind`` into structural
/// and content categories.
///
/// Backs the vim-style CST navigation kernel: motion predicates query
/// category membership ("is this a heading?", "is this a glue wrapper I
/// should skip past?", "does this differ from the head's category for a
/// `w`-style hop?").
///
/// Categories compose freely — a `wikiEmbedBlock` is `.reference + .embed +
/// .blockItem + .blockContainer`. Look up via ``LiminalKind/categories`` or
/// the classifier function ``categories(of:)``.
public struct LiminalStructuralCategory: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    // MARK: - Structural-role atoms (orthogonal to content kind)

    /// Appears as a sibling in a document-item sequence.
    public static let blockItem      = Self(rawValue: 1 <<  0)
    /// Owns a sequence of document items.
    public static let blockContainer = Self(rawValue: 1 <<  1)
    /// Inline-level structural form.
    public static let inlineUnit     = Self(rawValue: 1 <<  2)
    /// Wrapper hosting typed children; smart-ascend (`h`) skips past.
    public static let glueWrapper    = Self(rawValue: 1 <<  3)
    /// Has ``ChildSelectionPolicy/opaque`` child policy — navigation
    /// won't descend into its payload.
    public static let opaquePayload  = Self(rawValue: 1 <<  4)
    /// `.missing` / `.error` recovery sentinel.
    public static let recovery       = Self(rawValue: 1 <<  5)
    /// Whitespace / newline.
    public static let trivia         = Self(rawValue: 1 <<  6)
    /// Bracket / punctuation / structural-marker token.
    public static let punctuation    = Self(rawValue: 1 <<  7)
    /// Non-navigable text token inside an opaque or glue container.
    public static let payloadText    = Self(rawValue: 1 <<  8)

    // MARK: - Content-kind atoms

    /// Heading kind. Backs `]]` / `[[` / `][` / `[]` / `]h` / `[h` / `gh`.
    public static let heading        = Self(rawValue: 1 <<  9)
    /// `list` or `listItem`.
    public static let listy          = Self(rawValue: 1 << 10)
    /// `pipeTable` or any of its inner row / header / cell / delimiter kinds.
    public static let table          = Self(rawValue: 1 << 11)
    /// Fenced code block or inline code span. Backs `]c` / `[c`.
    public static let code           = Self(rawValue: 1 << 12)
    /// Math block or inline math. Backs `]m` / `[m`.
    public static let math           = Self(rawValue: 1 << 13)
    /// HTML block or inline HTML.
    public static let html           = Self(rawValue: 1 << 14)
    /// Comment block or inline comment.
    public static let comment        = Self(rawValue: 1 << 15)
    /// Anything in the typed-construct family. Backs `]k` / `[k`.
    public static let typed          = Self(rawValue: 1 << 16)
    /// Typed literal (`inlineLiteral`, `blockLiteral`).
    public static let literal        = Self(rawValue: 1 << 17)
    /// Schema declaration (block and inner schema-family kinds; excludes glue).
    public static let schema         = Self(rawValue: 1 << 18)
    /// Template declaration.
    public static let template       = Self(rawValue: 1 << 19)
    /// `directive` or `useDirective`.
    public static let directive      = Self(rawValue: 1 << 20)
    /// Frontmatter block.
    public static let frontmatter    = Self(rawValue: 1 << 21)
    /// Thematic break (`---`).
    public static let thematicBreak  = Self(rawValue: 1 << 22)
    /// Block-id anchor suffix (`^name`). Backs `]b` / `[b`.
    public static let blockAnchor    = Self(rawValue: 1 << 23)

    // MARK: - Reference family

    /// Broadest reference umbrella — anything that points to or names
    /// something elsewhere. Backs `]r` / `[r`.
    public static let reference      = Self(rawValue: 1 << 24)
    /// Text-pointing markdown link (`mdLink`, `autolink`). Backs `]l` /
    /// `[l`. Note that `mdImage` is `.embed` (not `.link`) and `wikilink`
    /// has its own atom ``wikilinkRef``.
    public static let link           = Self(rawValue: 1 << 25)
    /// Wikilink (`[[name]]`). Backs `]w` / `[w`.
    public static let wikilinkRef    = Self(rawValue: 1 << 26)
    /// Content-embedding reference (`mdImage`, wiki embeds, structured
    /// embeds). Backs `]e` / `[e`.
    public static let embed          = Self(rawValue: 1 << 27)
    /// Footnote inline reference.
    public static let footnote       = Self(rawValue: 1 << 28)

    // MARK: - Inline modifiers

    /// Emphasis family (`emphasis`, `strong`, `strikethrough`, `highlight`).
    public static let emphasis       = Self(rawValue: 1 << 29)

    /// Every defined category. Useful as a mask for `.differentFrom`
    /// when the caller wants "any category bit difference" — e.g.,
    /// the default `w`/`b` kind-run semantic.
    public static let all = Self(rawValue: UInt64.max)
}

public extension LiminalStructuralCategory {
    /// Total, exhaustive classification of every ``LiminalKind``.
    ///
    /// Implemented as `switch` with no `default:` arm — adding a new kind
    /// to ``LiminalKind`` without classifying it here is a compile-time
    /// error.
    static func categories(of kind: LiminalKind) -> LiminalStructuralCategory {
        switch kind {

        // MARK: Trivia / punctuation / sub-token literals

        case .whitespace, .newline:
            return .trivia

        case .atSign, .bang, .ampersand, .hash, .caret, .dollar,
             .leftBracket, .rightBracket, .leftParen, .rightParen,
             .leftBrace, .rightBrace, .lessThan, .greaterThan,
             .comma, .colon, .pipe, .backtick, .tilde, .star,
             .underscore, .dash, .plus, .dot, .slash, .backslash,
             .percent, .equals, .questionMark, .singleQuote,
             .doubleQuote, .semicolon,
             .hashRun, .colonRun, .fenceRun,
             .listMarker, .orderedListMarker, .taskMarker:
            return .punctuation

        // Sub-tokens of typed/value/schema constructs — their containing
        // kind carries the semantic role, so they have no category of
        // their own.
        case .identifier, .qname, .anchor, .fieldName,
             .quotedStringLiteral, .integerLiteral, .numberLiteral,
             .booleanLiteral, .nullLiteral, .bareScalarLiteral:
            return []

        // The lone navigable token: inline text under .inlineContent.
        case .inlineText:
            return .inlineUnit

        case .codeText, .mathText, .htmlText, .frontmatterText,
             .commentText, .rawPayloadText,
             .linkDestinationText, .linkTitleText,
             .wikiTargetText, .embedTargetText,
             .interpolationText, .externalReferenceText,
             .schemaText, .templateText, .directiveText, .errorText:
            return .payloadText

        // MARK: Block-level structural nodes

        case .root:                    return .blockContainer
        case .blankLine:               return .blockItem
        case .frontmatter:             return [.blockItem, .opaquePayload, .frontmatter]
        case .directive:               return [.blockItem, .directive]
        case .valueDeclaration:        return [.blockItem, .typed]
        case .paragraph:               return .blockItem
        case .atxHeading:              return [.blockItem, .heading]
        case .thematicBreak:           return [.blockItem, .thematicBreak]
        case .list:                    return [.blockItem, .listy]
        case .listItem:                return [.blockItem, .blockContainer, .listy]
        case .blockQuote:              return [.blockItem, .blockContainer]
        case .fencedCodeBlock:         return [.blockItem, .opaquePayload, .code]
        case .mathBlock:               return [.blockItem, .opaquePayload, .math]
        case .htmlBlock:               return [.blockItem, .opaquePayload, .html]
        case .commentBlock:            return [.blockItem, .opaquePayload, .comment]
        case .typedBlock:              return [.blockItem, .blockContainer, .typed]
        case .pipeTable:               return [.blockItem, .table]
        // Inner table kinds: live only inside a pipeTable, never as a
        // generic document-item sibling.
        case .pipeTableHeader,
             .pipeTableDelimiter,
             .pipeTableRow,
             .pipeTableCell:
            return .table
        case .structuredEmbedBlock:    return [.blockItem, .blockContainer, .reference, .embed]
        case .wikiEmbedBlock:          return [.blockItem, .blockContainer, .reference, .embed]
        case .blockIdSuffix:           return .blockAnchor

        // MARK: Inline structural nodes

        case .inlineContent:           return [.inlineUnit, .glueWrapper]
        case .softBreak, .hardBreak:   return .inlineUnit
        case .codeSpan:                return [.inlineUnit, .code]
        case .escapedPunctuation:      return .inlineUnit
        case .emphasis, .strong, .strikethrough, .highlight:
            return [.inlineUnit, .emphasis]
        case .mdLink:                  return [.inlineUnit, .reference, .link]
        case .mdImage:                 return [.inlineUnit, .reference, .embed]
        case .autolink:                return [.inlineUnit, .reference, .link]
        case .wikilink:                return [.inlineUnit, .reference, .wikilinkRef]
        case .wikiEmbed:               return [.inlineUnit, .reference, .embed]
        case .structuredEmbed:         return [.inlineUnit, .reference, .embed]
        case .mathInline:              return [.inlineUnit, .math]
        case .htmlInline:              return [.inlineUnit, .html]
        case .inlineComment:           return [.inlineUnit, .comment]
        case .footnoteInline:          return [.inlineUnit, .reference, .footnote]
        case .interpolation:           return [.inlineUnit, .reference]
        case .typedInline:             return [.inlineUnit, .typed]
        case .linkLabel, .linkDestination, .linkTitle,
             .wikiTarget, .embedTarget:
            return .glueWrapper

        // MARK: Value / typed family

        case .value, .typedConstructor,
             .fields, .listValue, .recordValue, .scalarValue:
            return .glueWrapper
        case .field:                   return .typed
        case .inlineLiteral:           return [.literal, .typed, .inlineUnit]
        case .blockLiteral:            return [.literal, .typed, .blockItem]
        case .reference:               return .reference
        case .externalReference:       return .reference
        case .structuredEmbedValue:    return [.reference, .glueWrapper]

        // MARK: Schema family

        case .schemaBlock:             return [.blockItem, .blockContainer, .typed, .schema]
        case .schemaHeader:            return [.schema, .typed]
        case .schemaTypeDeclaration,
             .schemaTemplateTypeDeclaration:
            return [.schema, .typed]
        case .schemaTypeExpression:    return [.schema, .typed]
        case .schemaField:             return [.schema, .typed]
        // schemaModifier is a real schema declaration, NOT a glue wrapper.
        case .schemaModifier:          return [.schema, .typed]
        case .schemaVariantCase:       return [.schema, .typed]
        case .schemaBody:              return [.glueWrapper, .schema]

        // MARK: Template family

        case .templateBlock:           return [.blockItem, .blockContainer, .typed, .template]
        case .templateSignature:       return [.template, .typed, .glueWrapper]
        case .templateParameter:       return [.template, .typed]
        case .templateBody:            return [.glueWrapper, .template]

        // MARK: Directives / interpolation expressions

        case .useDirective:            return [.blockItem, .directive, .typed]
        case .interpolationExpression: return [.glueWrapper, .typed]

        // MARK: Recovery sentinels

        case .missing, .error:         return .recovery
        }
    }
}

public extension LiminalKind {
    /// Ergonomic accessor: `kind.categories.contains(.heading)`.
    var categories: LiminalStructuralCategory {
        LiminalStructuralCategory.categories(of: self)
    }
}

public extension LiminalStructuralCategory {
    /// Runtime predicate for `]t` / `[t` — task-ness requires inspecting
    /// children (the `.taskMarker` token), so it can't be a pure category.
    /// Colocated here so this file remains the single source of truth for
    /// "what kinds participate in which chord."
    static func isTaskListItem(_ handle: SyntaxNodeHandle<LiminalLanguage>) -> Bool {
        guard let item = ListItemSyntax(handle) else { return false }
        return item.taskMarkerToken != nil
    }
}
