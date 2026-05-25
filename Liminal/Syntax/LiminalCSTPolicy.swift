import CambiumCore
import CambiumSelection

/// The selection policy that parameterizes ``LiminalForest`` /
/// ``LiminalForestAnchor`` for the Liminal editor.
///
/// Structural ("visual CST") navigation is *behaviorally* navigating the
/// conceptual typed-AST, not the raw CST. The CST carries extra elements that
/// have no AST counterpart — required delimiters, separators, trivia, and pure
/// wrapper nodes. This policy assigns each ``LiminalKind`` one
/// ``NavigationRole`` so the generic selection layer can contract the CST down
/// to its AST-content view:
///
/// - ``NavigationRole/stop``: an AST-present element — every structural node,
///   plus the payload tokens that carry leaf data (a URL, a code body, an
///   inline-text run, a scalar literal, an identifier). Navigation lands here.
/// - ``NavigationRole/passThrough``: an AST-erased *single-content wrapper*
///   that is never a sibling of other stops (`inlineContent`, `scalarValue`,
///   `interpolationExpression`). Navigation descends through it and ascends
///   past it, never landing on it.
/// - ``NavigationRole/skip``: AST-erased filler — required markers/delimiters,
///   element separators, whitespace/newline trivia, soft/hard breaks, the
///   table delimiter row, and zero-width `missing` recovery holes.
///
/// One exhaustive `switch` with no `default:` keeps the policy in sync with the
/// grammar: a new ``LiminalKind`` is a compile error until it is classified.
public enum LiminalCSTPolicy: SyntaxSelectionPolicy {
    public typealias Lang = LiminalLanguage

    public static func navigationRole(_ kind: LiminalKind) -> NavigationRole {
        switch kind {

        // MARK: skip — AST-erased filler

        // Trivia.
        case .whitespace, .newline:
            return .skip
        // Required delimiters / markers / punctuation.
        case .atSign, .bang, .ampersand, .hash, .caret, .dollar,
             .leftBracket, .rightBracket, .leftParen, .rightParen,
             .leftBrace, .rightBrace, .lessThan, .greaterThan,
             .comma, .colon, .pipe, .backtick, .tilde, .star,
             .underscore, .dash, .plus, .dot, .slash, .backslash,
             .percent, .equals, .questionMark, .singleQuote,
             .doubleQuote, .semicolon,
             .hashRun, .colonRun, .fenceRun,
             .listMarker, .orderedListMarker, .taskMarker:
            return .skip
        // Line breaks carry no AST content.
        case .softBreak, .hardBreak:
            return .skip
        // The `|---|` table delimiter row is pure framing.
        case .pipeTableDelimiter:
            return .skip
        // A zero-width recovery hole — nothing to land on.
        case .missing:
            return .skip

        // MARK: passThrough — AST-erased single-content wrappers

        case .inlineContent, .scalarValue, .interpolationExpression:
            return .passThrough

        // MARK: stop — payload tokens

        case .identifier, .qname, .anchor, .fieldName,
             .quotedStringLiteral, .integerLiteral, .numberLiteral,
             .booleanLiteral, .nullLiteral, .bareScalarLiteral,
             .inlineText,
             .codeText, .mathText, .htmlText, .frontmatterText,
             .commentText, .rawPayloadText,
             .linkDestinationText, .linkTitleText,
             .wikiTargetText, .embedTargetText,
             .interpolationText, .externalReferenceText,
             .schemaText, .templateText, .directiveText, .errorText:
            return .stop

        // MARK: stop — structural nodes

        case .root,
             .blankLine, .frontmatter, .directive, .valueDeclaration,
             .paragraph, .atxHeading, .thematicBreak,
             .list, .listItem, .blockQuote,
             .fencedCodeBlock, .mathBlock, .htmlBlock, .commentBlock,
             .typedBlock,
             .pipeTable, .pipeTableHeader, .pipeTableRow, .pipeTableCell,
             .structuredEmbedBlock, .wikiEmbedBlock,
             .blockIdSuffix,
             .codeSpan, .escapedPunctuation,
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
             .structuredEmbedValue,
             .schemaBlock, .schemaHeader,
             .schemaTypeDeclaration, .schemaTemplateTypeDeclaration,
             .schemaTypeExpression, .schemaField, .schemaModifier,
             .schemaBody, .schemaVariantCase,
             .templateBlock, .templateSignature, .templateParameter,
             .templateBody,
             .useDirective,
             .error:
            return .stop
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
    /// Build the forest under the editor's block cursor.
    ///
    /// A normal-mode block cursor visually occupies the character starting at
    /// `offset`; when one child ends and another starts at the same byte,
    /// editor targeting should prefer the downstream child.
    static func cursorTarget(
        at offset: TextSize,
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        LiminalForest.containing(offset, in: tree, affinity: .downstream)
    }

    /// Build the entry-point forest for visual CST mode at a cursor byte
    /// offset.
    ///
    /// `cursorTarget(at:in:)` returns the smallest stop under the cursor —
    /// inside prose that resolves to a single inline-text run, inside a link to
    /// its label/destination content. That's the correct foundation primitive
    /// but the wrong final selection for visual-CST entry: a user who pressed
    /// the entry chord wants structural reach, not a single word.
    ///
    /// This helper ascends from `cursorTarget(at:in:)`'s result until the
    /// focused element is a structural node that isn't buried inside an
    /// inline-content stream — a paragraph, list item, table cell, code block,
    /// etc. It lifts off bare payload leaf tokens (a word, a code body) and out
    /// of ``NavigationRole/passThrough`` wrappers, but stops there; pressing
    /// `l` then walks further down into the AST.
    ///
    /// Returns `nil` only when no stop contains `offset` (empty tree, offset
    /// past document end) — the Coordinator treats `nil` as "decline to enter."
    static func cstVisualEntry(
        at offset: TextSize,
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        guard var current = LiminalForest.cursorTarget(at: offset, in: tree) else {
            return nil
        }
        while shouldAscendForCSTEntry(current) {
            guard let parent = current.parentForest() else { break }
            current = parent
        }
        return current
    }

    /// `true` while entry should keep lifting: the focused stop is inside an
    /// inline-content stream (its parent is `passThrough`), or it is a bare
    /// payload leaf token. Either way we'd rather land on the enclosing
    /// structural node than on a single word or raw payload body.
    private static func shouldAscendForCSTEntry(_ forest: LiminalForest) -> Bool {
        forest.parent.withCursor { parent in
            if LiminalCSTPolicy.navigationRole(parent.kind) == .passThrough {
                return true
            }
            let element = parent.green { green in green.child(at: forest.anchorChildIndex) }
            if case .token = element { return true }
            return false
        }
    }
}
