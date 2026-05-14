import CambiumCore
import CambiumSelection

/// The selection policy that parameterizes ``LiminalForest`` /
/// ``LiminalForestAnchor`` for the Liminal editor.
///
/// This policy answers two questions for every ``LiminalKind``:
///
/// 1. ``isNavigable(_:)`` — can a child of this kind, in isolation, be an
///    endpoint of a structural selection? Trivia, punctuation glue,
///    payload-only tokens (the body of a fenced code block, frontmatter,
///    raw text salvage tokens) all return `false`.
/// 2. ``childPolicy(of:)`` — when this kind is a parent of a selection,
///    what's the rule for which children participate? Opaque-payload
///    parents (code blocks, math, HTML, comments, frontmatter) return
///    ``ChildSelectionPolicy/opaque``; ``inlineContent`` returns
///    ``ChildSelectionPolicy/allChildren`` so its text-token children
///    are navigable; everything else uses
///    ``ChildSelectionPolicy/structuralChildren``.
///
/// Both functions are exhaustive switches on ``LiminalKind`` with no
/// `default:` branch — the compiler enforces that new kinds in the grammar
/// get an explicit classification when they're added.
public enum LiminalCSTPolicy: SyntaxSelectionPolicy {
    public typealias Lang = LiminalLanguage

    public static func isNavigable(_ kind: LiminalKind) -> Bool {
        switch kind {
        // Trivia and structural punctuation tokens: never selectable on
        // their own.
        case .whitespace, .newline,
             .atSign, .bang, .ampersand, .hash, .caret, .dollar,
             .leftBracket, .rightBracket, .leftParen, .rightParen,
             .leftBrace, .rightBrace, .lessThan, .greaterThan,
             .comma, .colon, .pipe, .backtick, .tilde, .star,
             .underscore, .dash, .plus, .dot, .slash, .backslash,
             .percent, .equals, .questionMark, .singleQuote,
             .doubleQuote, .semicolon,
             .hashRun, .colonRun, .fenceRun,
             .listMarker, .orderedListMarker, .taskMarker:
            return false

        // Identifier and literal tokens: pieces of structured nodes, not
        // selection targets in their own right.
        case .identifier, .qname, .anchor, .fieldName,
             .quotedStringLiteral, .integerLiteral, .numberLiteral,
             .booleanLiteral, .nullLiteral, .bareScalarLiteral:
            return false

        // Payload-only content tokens: the body of an opaque container or
        // an internal text slice of a wrapper. Not selection targets.
        case .codeText, .mathText, .htmlText, .frontmatterText,
             .commentText, .rawPayloadText,
             .linkDestinationText, .linkTitleText,
             .wikiTargetText, .embedTargetText,
             .interpolationText, .externalReferenceText,
             .schemaText, .templateText, .directiveText, .errorText:
            return false

        // The lone navigable token: inline text runs inside an
        // inlineContent container with .allChildren policy.
        case .inlineText:
            return true

        // Document, block, inline, value, schema, and template structural
        // nodes. Every node kind is a meaningful structural unit.
        case .root,
             .blankLine, .frontmatter, .directive, .valueDeclaration,
             .paragraph, .atxHeading, .thematicBreak,
             .list, .listItem, .blockQuote,
             .fencedCodeBlock, .mathBlock, .htmlBlock, .commentBlock,
             .typedBlock,
             .pipeTable, .pipeTableHeader, .pipeTableDelimiter,
             .pipeTableRow, .pipeTableCell,
             .structuredEmbedBlock, .wikiEmbedBlock,
             .blockIdSuffix,
             .inlineContent,
             .softBreak, .hardBreak, .codeSpan, .escapedPunctuation,
             .emphasis, .strong, .strikethrough, .highlight,
             .mdLink, .mdImage, .autolink,
             .wikilink, .wikiEmbed, .structuredEmbed,
             .mathInline, .htmlInline, .inlineComment,
             .footnoteInline, .interpolation, .typedInline,
             .linkLabel, .linkDestination, .linkTitle,
             .wikiTarget, .embedTarget,
             .value, .typedConstructor, .fields, .field,
             .listValue, .recordValue,
             .inlineLiteral, .blockLiteral,
             .reference, .externalReference,
             .structuredEmbedValue, .scalarValue,
             .schemaBlock, .schemaHeader,
             .schemaTypeDeclaration, .schemaTemplateTypeDeclaration,
             .schemaTypeExpression, .schemaField, .schemaModifier,
             .schemaBody, .schemaVariantCase,
             .templateBlock, .templateSignature, .templateParameter,
             .templateBody,
             .useDirective, .interpolationExpression:
            return true

        // Recovery sentinels: selectable so the editor can navigate to
        // them and surface a "this region is incomplete" affordance.
        case .missing, .error:
            return true
        }
    }

    public static func childPolicy(of parent: LiminalKind) -> ChildSelectionPolicy {
        switch parent {
        // Raw-payload containers: their inner CST is a flat text token,
        // not something a user navigates into. CST visual mode lands on
        // the whole block as an atomic unit.
        case .fencedCodeBlock, .mathBlock, .htmlBlock,
             .commentBlock, .frontmatter:
            return .opaque

        // Mixed-content containers: structurally interesting node
        // children appear alongside meaningful text-token children
        // (e.g. inline-text runs inside an inlineContent), so token
        // children participate in navigation.
        case .inlineContent:
            return .allChildren

        // Everything else: only structural node children participate.
        case .root, .blankLine, .directive, .valueDeclaration,
             .paragraph, .atxHeading, .thematicBreak,
             .list, .listItem, .blockQuote,
             .typedBlock,
             .pipeTable, .pipeTableHeader, .pipeTableDelimiter,
             .pipeTableRow, .pipeTableCell,
             .structuredEmbedBlock, .wikiEmbedBlock,
             .blockIdSuffix,
             .softBreak, .hardBreak, .codeSpan, .escapedPunctuation,
             .emphasis, .strong, .strikethrough, .highlight,
             .mdLink, .mdImage, .autolink,
             .wikilink, .wikiEmbed, .structuredEmbed,
             .mathInline, .htmlInline, .inlineComment,
             .footnoteInline, .interpolation, .typedInline,
             .linkLabel, .linkDestination, .linkTitle,
             .wikiTarget, .embedTarget,
             .value, .typedConstructor, .fields, .field,
             .listValue, .recordValue,
             .inlineLiteral, .blockLiteral,
             .reference, .externalReference,
             .structuredEmbedValue, .scalarValue,
             .schemaBlock, .schemaHeader,
             .schemaTypeDeclaration, .schemaTemplateTypeDeclaration,
             .schemaTypeExpression, .schemaField, .schemaModifier,
             .schemaBody, .schemaVariantCase,
             .templateBlock, .templateSignature, .templateParameter,
             .templateBody,
             .useDirective, .interpolationExpression,
             .missing, .error,
             // Token-kind parents: tokens have no children, so the
             // policy is irrelevant in practice; pick the conservative
             // default rather than a special case.
             .whitespace, .newline,
             .atSign, .bang, .ampersand, .hash, .caret, .dollar,
             .leftBracket, .rightBracket, .leftParen, .rightParen,
             .leftBrace, .rightBrace, .lessThan, .greaterThan,
             .comma, .colon, .pipe, .backtick, .tilde, .star,
             .underscore, .dash, .plus, .dot, .slash, .backslash,
             .percent, .equals, .questionMark, .singleQuote,
             .doubleQuote, .semicolon,
             .hashRun, .colonRun, .fenceRun,
             .listMarker, .orderedListMarker, .taskMarker,
             .identifier, .qname, .anchor, .fieldName,
             .quotedStringLiteral, .integerLiteral, .numberLiteral,
             .booleanLiteral, .nullLiteral, .bareScalarLiteral,
             .inlineText,
             .codeText, .mathText, .htmlText, .frontmatterText,
             .commentText, .rawPayloadText,
             .linkDestinationText, .linkTitleText,
             .wikiTargetText, .embedTargetText,
             .interpolationText, .externalReferenceText,
             .schemaText, .templateText, .directiveText, .errorText:
            return .structuralChildren
        }
    }
}

/// A structural CST selection in the Liminal editor.
public typealias LiminalForest = SyntaxForest<LiminalCSTPolicy>

/// A persistent, version-independent capture of a ``LiminalForest``.
public typealias LiminalForestAnchor = ForestAnchor<LiminalCSTPolicy>

/// The graded outcome of re-resolving a ``LiminalForestAnchor`` against a
/// later tree version.
public typealias LiminalForestResolution = ForestResolution<LiminalCSTPolicy>

public extension SyntaxForest where Policy == LiminalCSTPolicy {
    /// Build the entry-point forest for visual CST mode at a cursor byte
    /// offset.
    ///
    /// `LiminalForest.containing(_:in:)` returns the *smallest* navigable
    /// forest covering `offset` — which inside markup inline content
    /// resolves to a single `.inlineText` token under an
    /// ``ChildSelectionPolicy/allChildren`` parent. That's the correct
    /// foundation primitive but the wrong default for visual CST mode's
    /// UX: a user who pressed the entry chord wants structural reach, not
    /// a single-word selection.
    ///
    /// This helper ascends from `containing(_:in:)`'s result until the
    /// focused child kind is a meaningful structural unit — a paragraph,
    /// list item, code block, heading, table row, field, etc. It ascends
    /// past both ``ChildSelectionPolicy/allChildren`` parents (which
    /// admit token siblings that aren't meaningful selection targets) and
    /// structural-glue wrappers (``LiminalKind/inlineContent``,
    /// ``LiminalKind/value``, ``LiminalKind/fields``, the typed-value
    /// payload wrappers) that exist purely to host typed children. The
    /// user can press `h` to ascend further from the resulting block.
    ///
    /// Returns `nil` only when no navigable forest contains `offset`
    /// (empty tree, offset past document end). The Coordinator's entry
    /// path treats `nil` as "decline to enter visual CST mode."
    static func cstVisualEntry(
        at offset: TextSize,
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        guard var current = LiminalForest.containing(offset, in: tree) else {
            return nil
        }
        while shouldAscendForCSTEntry(current) {
            guard let parent = current.parentForest() else { break }
            current = parent
        }
        return current
    }

    /// `true` when `forest` is still inside an ascend-past target — its
    /// parent is `.allChildren`, OR its focused child kind is a
    /// structural-glue wrapper that exists to host typed children rather
    /// than represent a selection unit on its own.
    private static func shouldAscendForCSTEntry(_ forest: LiminalForest) -> Bool {
        let parentKind = forest.parent.withCursor { $0.kind }
        if LiminalCSTPolicy.childPolicy(of: parentKind) == .allChildren {
            return true
        }
        let childKind = forest.parent.withCursor { cursor in
            cursor.green { green in green.child(at: forest.anchorChildIndex) }
        }.kind
        return Self.isCSTStructuralGlueWrapper(childKind)
    }

    /// The set of kinds whose role is "host other typed children" rather
    /// than "be a selection unit." Used by ``cstVisualEntry(at:in:)`` to
    /// ascend past them on entry.
    private static func isCSTStructuralGlueWrapper(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .inlineContent,
             .fields, .value,
             .listValue, .recordValue, .scalarValue,
             .schemaBody, .templateBody,
             .typedConstructor:
            return true
        default:
            return false
        }
    }
}
