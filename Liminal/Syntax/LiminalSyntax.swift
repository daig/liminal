import CambiumBuilder
import CambiumCore
import CambiumIncremental
import CambiumSyntaxMacros

@CambiumSyntaxKind
public enum LiminalKind: UInt32, Sendable {
    case whitespace = 1
    case newline = 2

    @StaticText("@")
    case atSign = 10
    @StaticText("!")
    case bang = 11
    @StaticText("&")
    case ampersand = 12
    @StaticText("#")
    case hash = 13
    @StaticText("^")
    case caret = 14
    @StaticText("$")
    case dollar = 15
    @StaticText("[")
    case leftBracket = 16
    @StaticText("]")
    case rightBracket = 17
    @StaticText("(")
    case leftParen = 18
    @StaticText(")")
    case rightParen = 19
    @StaticText("{")
    case leftBrace = 20
    @StaticText("}")
    case rightBrace = 21
    @StaticText("<")
    case lessThan = 22
    @StaticText(">")
    case greaterThan = 23
    @StaticText(",")
    case comma = 24
    @StaticText(":")
    case colon = 25
    @StaticText("|")
    case pipe = 26
    @StaticText("`")
    case backtick = 27
    @StaticText("~")
    case tilde = 28
    @StaticText("*")
    case star = 29
    @StaticText("_")
    case underscore = 30
    @StaticText("-")
    case dash = 31
    @StaticText("+")
    case plus = 32
    @StaticText(".")
    case dot = 33
    @StaticText("/")
    case slash = 34
    @StaticText("\\")
    case backslash = 35
    @StaticText("%")
    case percent = 36
    @StaticText("=")
    case equals = 37
    @StaticText("?")
    case questionMark = 38
    @StaticText("'")
    case singleQuote = 39
    @StaticText("\"")
    case doubleQuote = 40
    @StaticText(";")
    case semicolon = 41

    case hashRun = 50
    case colonRun = 51
    case fenceRun = 52
    case listMarker = 53
    case orderedListMarker = 54
    case taskMarker = 55
    case identifier = 56
    case qname = 57
    case anchor = 58
    case fieldName = 59
    case quotedStringLiteral = 60
    case integerLiteral = 61
    case numberLiteral = 62
    case booleanLiteral = 63
    case nullLiteral = 64
    case bareScalarLiteral = 65
    case inlineText = 66
    case codeText = 67
    case mathText = 68
    case htmlText = 69
    case frontmatterText = 70
    case commentText = 71
    case rawPayloadText = 72
    case linkDestinationText = 73
    case linkTitleText = 74
    case wikiTargetText = 75
    case embedTargetText = 76
    case interpolationText = 77
    case externalReferenceText = 78
    case schemaText = 79
    case templateText = 80
    case directiveText = 81
    case errorText = 82

    case root = 100
    case blankLine = 101
    case frontmatter = 102
    case directive = 103
    case valueDeclaration = 104
    case paragraph = 105
    case atxHeading = 106
    case thematicBreak = 107
    case list = 108
    case listItem = 109
    case blockQuote = 110
    case fencedCodeBlock = 111
    case mathBlock = 112
    case htmlBlock = 113
    case commentBlock = 114
    case typedBlock = 115
    case pipeTable = 116
    case pipeTableHeader = 117
    case pipeTableDelimiter = 118
    case pipeTableRow = 119
    case pipeTableCell = 120
    case structuredEmbedBlock = 121
    case wikiEmbedBlock = 122
    case blockIdSuffix = 123

    case inlineContent = 200
    case softBreak = 201
    case hardBreak = 202
    case codeSpan = 203
    case escapedPunctuation = 204
    case emphasis = 205
    case strong = 206
    case strikethrough = 207
    case highlight = 208
    case mdLink = 209
    case mdImage = 210
    case autolink = 211
    case wikilink = 212
    case wikiEmbed = 213
    case structuredEmbed = 214
    case mathInline = 215
    case htmlInline = 216
    case inlineComment = 217
    case footnoteInline = 218
    case interpolation = 219
    case typedInline = 220
    case linkLabel = 221
    case linkDestination = 222
    case linkTitle = 223
    case wikiTarget = 224
    case embedTarget = 225

    case value = 300
    case typedConstructor = 301
    case fields = 302
    case field = 303
    case listValue = 304
    case recordValue = 305
    case inlineLiteral = 306
    case blockLiteral = 307
    case reference = 308
    case externalReference = 309
    case structuredEmbedValue = 310
    case scalarValue = 311
    case schemaBlock = 312
    case schemaHeader = 313
    case schemaTypeDeclaration = 314
    case schemaTemplateTypeDeclaration = 315
    case schemaTypeExpression = 316
    case schemaField = 317
    case schemaModifier = 318
    case templateBlock = 319
    case templateSignature = 320
    case templateParameter = 321
    case templateBody = 322
    case useDirective = 323
    case schemaBody = 324
    case interpolationExpression = 325
    case schemaVariantCase = 326

    case missing = 900
    case error = 901
}

public enum LiminalLanguage: SyntaxLanguage {
    public typealias Kind = LiminalKind

    public static let rootKind: LiminalKind = .root
    public static let missingKind: LiminalKind = .missing
    public static let errorKind: LiminalKind = .error
    public static let serializationID = "dog.lambda.liminal.markup"
    public static let serializationVersion: UInt32 = 8

    public static func isTrivia(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .whitespace, .newline:
            true
        default:
            false
        }
    }

    public static func isNode(_ kind: LiminalKind) -> Bool {
        switch kind {
        case
            .root,
            .blankLine,
            .frontmatter,
            .directive,
            .valueDeclaration,
            .paragraph,
            .atxHeading,
            .thematicBreak,
            .list,
            .listItem,
            .blockQuote,
            .fencedCodeBlock,
            .mathBlock,
            .htmlBlock,
            .commentBlock,
            .typedBlock,
            .pipeTable,
            .pipeTableHeader,
            .pipeTableDelimiter,
            .pipeTableRow,
            .pipeTableCell,
            .structuredEmbedBlock,
            .wikiEmbedBlock,
            .blockIdSuffix,
            .inlineContent,
            .softBreak,
            .hardBreak,
            .codeSpan,
            .escapedPunctuation,
            .emphasis,
            .strong,
            .strikethrough,
            .highlight,
            .mdLink,
            .mdImage,
            .autolink,
            .wikilink,
            .wikiEmbed,
            .structuredEmbed,
            .mathInline,
            .htmlInline,
            .inlineComment,
            .footnoteInline,
            .interpolation,
            .typedInline,
            .linkLabel,
            .linkDestination,
            .linkTitle,
            .wikiTarget,
            .embedTarget,
            .value,
            .typedConstructor,
            .fields,
            .field,
            .listValue,
            .recordValue,
            .inlineLiteral,
            .blockLiteral,
            .reference,
            .externalReference,
            .structuredEmbedValue,
            .scalarValue,
            .schemaBlock,
            .schemaHeader,
            .schemaTypeDeclaration,
            .schemaTemplateTypeDeclaration,
            .schemaTypeExpression,
            .schemaField,
            .schemaModifier,
            .templateBlock,
            .templateSignature,
            .templateParameter,
            .templateBody,
            .useDirective,
            .schemaBody,
            .interpolationExpression,
            .schemaVariantCase,
            .missing,
            .error:
            true
        default:
            false
        }
    }

    public static func isToken(_ kind: LiminalKind) -> Bool {
        !isNode(kind)
    }
}

public struct LiminalDiagnostic: Equatable, Sendable {
    public var severity: LiminalDiagnosticSeverity
    public var message: String
    public var range: TextRange

    public init(
        severity: LiminalDiagnosticSeverity,
        message: String,
        range: TextRange = .empty
    ) {
        self.severity = severity
        self.message = message
        self.range = range
    }
}

public enum LiminalDiagnosticSeverity: String, Equatable, Sendable {
    case note
    case warning
    case error
}

public struct LiminalParseResult: Sendable {
    public var tree: SharedSyntaxTree<LiminalLanguage>
    public var diagnostics: [LiminalDiagnostic]
    /// Byte range of the new source's "dirty span" — the contiguous slice
    /// of top-level children that this parse actually re-walked. Spans
    /// outside this range were transplanted verbatim from the previous
    /// tree and have byte-identical attribution. Consumers driving
    /// per-edit refreshes (syntax highlighter, decoration providers,
    /// etc.) should treat this as the authoritative repaint scope.
    ///
    /// `nil` when no scope information is available — cold parses, full
    /// rewrites without edits, and any path where the parse didn't take
    /// the skip-clean-regions fast path. Consumers should treat `nil`
    /// as "every byte may have changed" and repaint the whole document.
    public var changedByteRange: TextRange?

    public init(
        tree: SharedSyntaxTree<LiminalLanguage>,
        diagnostics: [LiminalDiagnostic] = [],
        changedByteRange: TextRange? = nil
    ) {
        self.tree = tree
        self.diagnostics = diagnostics
        self.changedByteRange = changedByteRange
    }

    public var sourceText: String {
        tree.withRoot { root in
            root.makeString()
        }
    }

    public var rootSyntax: RootSyntax {
        RootSyntax(unchecked: tree.rootHandle())
    }
}

public struct LiminalParser {
    public init() {}

    public func parse(_ source: String) throws -> LiminalParseResult {
        var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
        var parser = LiminalCSTParser(source: source)
        try parser.parse(with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        return LiminalParseResult(tree: tree, diagnostics: parser.diagnostics)
    }

    fileprivate func parse(
        _ source: String,
        edits: [TextEdit],
        previousTree: SharedSyntaxTree<LiminalLanguage>?,
        incrementalSession: IncrementalParseSession<LiminalLanguage>?,
        context: consuming GreenTreeContext<LiminalLanguage>
    ) throws -> LiminalParseSessionBuildOutput {
        var builder = GreenTreeBuilder<LiminalLanguage>(context: consume context)
        var parser = LiminalCSTParser(
            source: source,
            edits: edits,
            previousTree: previousTree,
            incrementalSession: incrementalSession
        )
        try parser.parse(with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        let nextContext = build.intoContext()
        return LiminalParseSessionBuildOutput(
            result: LiminalParseResult(tree: tree, diagnostics: parser.diagnostics),
            context: consume nextContext,
            acceptedReuses: parser.acceptedReuses
        )
    }
}

struct LiminalParseSessionBuildOutput: ~Copyable {
    var result: LiminalParseResult
    var context: GreenTreeContext<LiminalLanguage>
    var acceptedReuses: [LiminalAcceptedReuse]

    init(
        result: LiminalParseResult,
        context: consuming GreenTreeContext<LiminalLanguage>,
        acceptedReuses: [LiminalAcceptedReuse] = []
    ) {
        self.result = result
        self.context = context
        self.acceptedReuses = acceptedReuses
    }
}

public struct ReuseSummary: Equatable, Sendable {
    public let queries: Int
    public let hits: Int
    public let acceptedReuses: Int
    public let bytesOffered: UInt64
    public let bytesAccepted: UInt64

    public init(
        queries: Int = 0,
        hits: Int = 0,
        acceptedReuses: Int = 0,
        bytesOffered: UInt64 = 0,
        bytesAccepted: UInt64 = 0
    ) {
        self.queries = queries
        self.hits = hits
        self.acceptedReuses = acceptedReuses
        self.bytesOffered = bytesOffered
        self.bytesAccepted = bytesAccepted
    }

    public static let empty = ReuseSummary()
}

struct LiminalAcceptedReuse {
    let oldPath: SyntaxNodePath
    let green: GreenNode<LiminalLanguage>
    let newOffset: TextSize
}

public final class LiminalParseSession {
    private var context: GreenTreeContext<LiminalLanguage>?
    private var lastTree: SharedSyntaxTree<LiminalLanguage>?
    private let incrementalSession = IncrementalParseSession<LiminalLanguage>()
    private(set) public var lastReuseSummary: ReuseSummary = .empty
    private var pendingEditsInvalidated: Bool = false

    public init() {}

    @discardableResult
    public func parse(
        _ source: String,
        edits: [TextEdit] = []
    ) throws -> LiminalParseResult {
        _ = incrementalSession.consumeAcceptedReuses()

        let effectiveEdits: [TextEdit]
        if pendingEditsInvalidated {
            effectiveEdits = []
            pendingEditsInvalidated = false
        } else {
            effectiveEdits = edits
        }

        // Skip-clean-regions fast path: when a previous tree exists and the
        // caller reported edits, walk the previous tree's top-level children,
        // transplant the ones whose source bytes are unaffected by edits, and
        // sub-parse only the contiguous dirty span. Falls back to full parse
        // when the previous tree is empty (no children to transplant) or the
        // strategy bails out defensively.
        if let previousTree = lastTree, !effectiveEdits.isEmpty,
           let result = try performSkipCleanRegionsParse(
                source: source,
                edits: effectiveEdits,
                previousTree: previousTree
           )
        {
            return result
        }

        return try performFullParse(source: source, edits: effectiveEdits)
    }

    private func performFullParse(
        source: String,
        edits: [TextEdit]
    ) throws -> LiminalParseResult {
        let coldStart = (lastTree == nil && edits.isEmpty)
        let sessionForParser: IncrementalParseSession<LiminalLanguage>? = coldStart ? nil : incrementalSession
        let previousTreeForParser = coldStart ? nil : lastTree

        let countersBefore = incrementalSession.counters

        let parser = LiminalParser()
        let output: LiminalParseSessionBuildOutput
        if let existing = context.take() {
            output = try parser.parse(
                source,
                edits: edits,
                previousTree: previousTreeForParser,
                incrementalSession: sessionForParser,
                context: consume existing
            )
        } else {
            output = try parser.parse(
                source,
                edits: edits,
                previousTree: previousTreeForParser,
                incrementalSession: sessionForParser,
                context: GreenTreeContext(policy: .parseSession(maxEntries: 16_384))
            )
        }
        let result = output.result
        let acceptedReuses = output.acceptedReuses
        context = consume output.context
        lastTree = result.tree

        var bytesAccepted: UInt64 = 0
        for accepted in acceptedReuses {
            bytesAccepted += UInt64(accepted.green.textLength.rawValue)
            if let newPath = Self.resolveNewPath(
                in: result.tree,
                offset: accepted.newOffset,
                green: accepted.green
            ) {
                incrementalSession.recordAcceptedReuse(
                    oldPath: accepted.oldPath,
                    newPath: newPath,
                    green: accepted.green
                )
            }
        }

        let countersAfter = incrementalSession.counters
        lastReuseSummary = ReuseSummary(
            queries: countersAfter.reuseQueries - countersBefore.reuseQueries,
            hits: countersAfter.reuseHits - countersBefore.reuseHits,
            acceptedReuses: acceptedReuses.count,
            bytesOffered: countersAfter.reusedBytes - countersBefore.reusedBytes,
            bytesAccepted: bytesAccepted
        )

        return result
    }

    /// Snapshot of one top-level child in the previous tree: just enough
    /// to decide if it's dirty (its absolute byte range), how to apply
    /// the boundary halo (its kind), and whether it carries stale
    /// parse-error sentinels that must be re-parsed rather than
    /// transplanted (so their diagnostics get re-emitted under the new
    /// session).
    private struct OldChildSnapshot {
        let kind: LiminalKind
        let oldRange: TextRange
        let containsSentinels: Bool
    }

    /// Block kinds whose extent in the new source depends on what comes
    /// after them — a one-character edit at the boundary of a context-
    /// bounded kind can shift the boundary into or out of the next
    /// sibling. To stay correct under such shifts, include both immediate
    /// neighbors in the dirty span when the dirty primary has one of
    /// these kinds (and likewise when the neighbor itself is a blank
    /// line, whose removal can merge its neighbors).
    private static func isContextBounded(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .paragraph, .blockQuote, .list, .pipeTable, .blankLine:
            return true
        default:
            return false
        }
    }

    /// Walk `previousTree`'s root children, identify which intersect any
    /// edit's old-tree range (plus a boundary halo), and re-build the new
    /// tree by transplanting the unaffected children and sub-parsing the
    /// dirty span. Returns `nil` (so the caller falls back to a full
    /// parse) when the strategy isn't applicable — empty previous tree,
    /// edit ranges out of the document, or any defensive bail-out.
    private func performSkipCleanRegionsParse(
        source: String,
        edits: [TextEdit],
        previousTree: SharedSyntaxTree<LiminalLanguage>
    ) throws -> LiminalParseResult? {
        let countersBefore = incrementalSession.counters

        // Snapshot all top-level children's kinds + absolute byte ranges.
        // Uses green-only access (no red realization) so this is cheap even
        // for 6,000-child stress fixtures.
        let snapshot = previousTree.withRoot { root in
            Self.snapshotTopLevelChildren(root)
        }
        guard !snapshot.isEmpty else { return nil }

        // Step 1: direct hit set — which old-tree children does any edit touch?
        var touched: Set<Int> = []
        for edit in edits {
            Self.findTouched(edit: edit, snapshot: snapshot, into: &touched)
        }
        // If no child is touched (e.g., edit at EOF on an empty doc), fall
        // back to full parse rather than guessing.
        guard !touched.isEmpty else { return nil }

        // Step 2: boundary halo. Extend on each side if the BOUNDARY
        // dirty child is context-bounded (its extent could shift into or
        // out of the neighbor). Self-delimited dirty children (code
        // blocks, math, comments, typed blocks, etc.) can't shift their
        // boundaries from internal edits, so no halo is needed even if
        // their neighbors are context-bounded.
        var lo = touched.min()!
        var hi = touched.max()!
        if lo > 0, Self.isContextBounded(snapshot[lo].kind) {
            lo -= 1
        }
        if hi < snapshot.count - 1, Self.isContextBounded(snapshot[hi].kind) {
            hi += 1
        }

        // Step 2.5: sentinel expansion. A transplant candidate carrying a
        // parse-error sentinel was produced by the old parse from
        // identical source bytes, so transplanting it produces a tree
        // that's structurally correct. But the *diagnostics* attached to
        // that sentinel were emitted by the parser — they don't ride the
        // green tree. To keep the new parse result's diagnostics
        // representative of the new source, pull any sentinel-bearing
        // adjacent child into the dirty span so the sub-parse re-emits
        // its diagnostics. Rare (only when the old document was
        // malformed in a region the user hasn't touched yet); doesn't
        // affect the hot path for well-formed documents.
        while lo > 0, snapshot[lo - 1].containsSentinels {
            lo -= 1
        }
        while hi < snapshot.count - 1, snapshot[hi + 1].containsSentinels {
            hi += 1
        }

        // Step 3: compute new-source byte range for the dirty span.
        // Edits before the span shift its start; edits inside change its
        // length; edits after don't affect us.
        let oldDirtyStart = snapshot[lo].oldRange.start
        let oldDirtyEnd = snapshot[hi].oldRange.end
        let (newDirtyStart, newDirtyEnd) = Self.mapDirtyRange(
            oldStart: oldDirtyStart,
            oldEnd: oldDirtyEnd,
            edits: edits
        )

        // Step 4: extract the dirty slice as a String.
        guard let dirtyText = Self.utf8Slice(
            of: source,
            from: Int(newDirtyStart.rawValue),
            to: Int(newDirtyEnd.rawValue)
        ) else {
            return nil
        }

        // Step 5: build the new tree by transplant + sub-parse + transplant.
        var builder: GreenTreeBuilder<LiminalLanguage>
        if let existing = self.context.take() {
            builder = GreenTreeBuilder<LiminalLanguage>(context: consume existing)
        } else {
            builder = GreenTreeBuilder<LiminalLanguage>(
                context: GreenTreeContext(policy: .parseSession(maxEntries: 16_384))
            )
        }
        builder.startNode(.root)

        var bytesAccepted: UInt64 = 0

        // 5a. Transplant predecessors (indices [0, lo)).
        for oldIndex in 0..<lo {
            try previousTree.withRoot { root in
                try root.withChildNode(atRawIndex: oldIndex) { cursor in
                    _ = try builder.reuseSubtree(cursor)
                    let green = cursor.green { $0 }
                    bytesAccepted += UInt64(green.textLength.rawValue)
                    // The transplant *is* a successful reuse decision —
                    // semantically equivalent to a successful oracle
                    // query that returned this child. Bump the session
                    // counters so consumers reading `lastReuseSummary`
                    // see the same shape they'd get from the parser's
                    // tryReuse path.
                    incrementalSession.recordReuseQuery(hitBytes: green.textLength)
                    incrementalSession.recordAcceptedReuse(
                        oldPath: [UInt32(oldIndex)],
                        newPath: [UInt32(oldIndex)],
                        green: green
                    )
                }
            }
        }

        // 5b. Sub-parse the dirty slice. The sub-parser emits top-level
        // children directly into the open .root frame (parseDocumentItems
        // doesn't open its own root). It runs WITHOUT previousTree, so
        // its internal tryReuse calls are no-ops — the entire dirty slice
        // is parsed fresh. The slice is small (typically <10 lines) so this
        // is cheap.
        let childCountBeforeSubParse = builder.currentFrameChildCount
        var subParser = LiminalCSTParser(
            source: dirtyText,
            baseByteOffset: Int(newDirtyStart.rawValue),
            edits: [],
            previousTree: nil,
            incrementalSession: nil
        )
        try subParser.parseDocumentItems(with: &builder)
        let subParseChildCount = builder.currentFrameChildCount - childCountBeforeSubParse

        // 5c. Transplant successors (indices [hi + 1, count)).
        let newSuccessorBase = lo + subParseChildCount
        let successorCount = snapshot.count - (hi + 1)
        for offset in 0..<successorCount {
            let oldIndex = hi + 1 + offset
            let newIndex = newSuccessorBase + offset
            try previousTree.withRoot { root in
                try root.withChildNode(atRawIndex: oldIndex) { cursor in
                    _ = try builder.reuseSubtree(cursor)
                    let green = cursor.green { $0 }
                    bytesAccepted += UInt64(green.textLength.rawValue)
                    incrementalSession.recordReuseQuery(hitBytes: green.textLength)
                    incrementalSession.recordAcceptedReuse(
                        oldPath: [UInt32(oldIndex)],
                        newPath: [UInt32(newIndex)],
                        green: green
                    )
                }
            }
        }

        try builder.finishNode()
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        self.context = build.intoContext()
        self.lastTree = tree

        let countersAfter = incrementalSession.counters
        let acceptedReuseCount = lo + successorCount
        lastReuseSummary = ReuseSummary(
            queries: countersAfter.reuseQueries - countersBefore.reuseQueries,
            hits: countersAfter.reuseHits - countersBefore.reuseHits,
            acceptedReuses: acceptedReuseCount,
            bytesOffered: countersAfter.reusedBytes - countersBefore.reusedBytes,
            bytesAccepted: bytesAccepted
        )

        return LiminalParseResult(
            tree: tree,
            diagnostics: subParser.diagnostics,
            changedByteRange: TextRange(start: newDirtyStart, end: newDirtyEnd)
        )
    }

    private static func snapshotTopLevelChildren(
        _ root: borrowing SyntaxNodeCursor<LiminalLanguage>
    ) -> [OldChildSnapshot] {
        root.green { rootGreen -> [OldChildSnapshot] in
            let count = rootGreen.childCount
            var snapshots: [OldChildSnapshot] = []
            snapshots.reserveCapacity(count)
            var cursor = TextSize.zero
            for index in 0..<count {
                let child = rootGreen.child(at: index)
                let length = child.textLength
                let absStart = root.textRange.start + cursor
                let absEnd = absStart + length
                let kind: LiminalKind
                let containsSentinels: Bool
                switch child {
                case .node(let nodeGreen):
                    kind = LiminalLanguage.kind(for: nodeGreen.rawKind)
                    containsSentinels = nodeGreen.containsSentinels
                case .token(let tokenGreen):
                    kind = LiminalLanguage.kind(for: tokenGreen.rawKind)
                    // Tokens don't carry the bit; treat as clean.
                    containsSentinels = false
                }
                snapshots.append(OldChildSnapshot(
                    kind: kind,
                    oldRange: TextRange(start: absStart, end: absEnd),
                    containsSentinels: containsSentinels
                ))
                cursor = cursor + length
            }
            return snapshots
        }
    }

    /// Add the indices of `snapshot` entries whose old-tree range
    /// intersects `edit` to `touched`.
    ///
    /// Intersection rules:
    ///   - Non-empty edit `[a, b)` intersects child `[c, d)` iff
    ///     `b > c && a < d`.
    ///   - Zero-length insert at `a` intersects child `[c, d)` iff
    ///     `c <= a <= d`. The insert may be at either boundary; in the
    ///     boundary case both adjacent children become touched, which the
    ///     halo step further extends if needed.
    private static func findTouched(
        edit: TextEdit,
        snapshot: [OldChildSnapshot],
        into touched: inout Set<Int>
    ) {
        let a = edit.range.start.rawValue
        let b = edit.range.end.rawValue
        for index in 0..<snapshot.count {
            let c = snapshot[index].oldRange.start.rawValue
            let d = snapshot[index].oldRange.end.rawValue
            if a == b {
                if c <= a && a <= d { touched.insert(index) }
            } else {
                if b > c && a < d { touched.insert(index) }
            }
        }
    }

    /// Translate the old-tree dirty range `[oldStart, oldEnd]` to its
    /// new-tree counterpart, accounting for any edits that lie before or
    /// inside the range. Edits strictly after the range don't affect us.
    ///
    /// "Inside" is intersection in the closed-range sense:
    /// - Non-empty edit `[a, b)` is inside iff `b > oldStart && a < oldEnd`.
    /// - Zero-length insert at `a` is inside iff `oldStart <= a <= oldEnd`
    ///   (touches either boundary). An insert at the dirty range's start
    ///   or end injects new bytes that become part of the re-parsed span,
    ///   so it contributes to `deltaInside`, not to `deltaBeforeStart`.
    ///   This matters for the common "type a character at the end of a
    ///   paragraph" case, where the insert position equals
    ///   `oldDirtyEnd`.
    private static func mapDirtyRange(
        oldStart: TextSize,
        oldEnd: TextSize,
        edits: [TextEdit]
    ) -> (newStart: TextSize, newEnd: TextSize) {
        let dirtyStart = Int(oldStart.rawValue)
        let dirtyEnd = Int(oldEnd.rawValue)
        var deltaBeforeStart: Int = 0
        var deltaInside: Int = 0
        for edit in edits {
            let editStart = Int(edit.range.start.rawValue)
            let editEnd = Int(edit.range.end.rawValue)
            let delta = Int(edit.replacementUTF8.count) - Int(edit.range.length.rawValue)
            let isInside: Bool
            if editStart == editEnd {
                isInside = (dirtyStart <= editStart && editStart <= dirtyEnd)
            } else {
                isInside = (editEnd > dirtyStart && editStart < dirtyEnd)
            }
            if isInside {
                deltaInside += delta
            } else if editEnd <= dirtyStart {
                deltaBeforeStart += delta
            }
            // Else: strictly after dirty range — ignore.
        }
        let newStart = TextSize(UInt32(dirtyStart + deltaBeforeStart))
        let newEnd = TextSize(UInt32(dirtyStart + deltaBeforeStart + (dirtyEnd - dirtyStart) + deltaInside))
        return (newStart, newEnd)
    }

    /// Materialize `source.utf8[start..<end]` as a `String`. Uses
    /// `withContiguousStorageIfAvailable` for the fast path (native
    /// UTF-8-backed Swift strings) and falls back to a one-off `[UInt8]`
    /// copy otherwise. Returns `nil` if the byte range is out of bounds.
    private static func utf8Slice(of source: String, from start: Int, to end: Int) -> String? {
        let utf8Count = source.utf8.count
        guard start >= 0, end >= start, end <= utf8Count else { return nil }
        if let result = source.utf8.withContiguousStorageIfAvailable({ buffer -> String in
            let slice = UnsafeBufferPointer(rebasing: buffer[start..<end])
            return String(decoding: slice, as: UTF8.self)
        }) {
            return result
        }
        let array = Array(source.utf8)
        return String(decoding: array[start..<end], as: UTF8.self)
    }

    public var currentTree: SharedSyntaxTree<LiminalLanguage>? {
        lastTree
    }

    private static func resolveNewPath(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        offset: TextSize,
        green: GreenNode<LiminalLanguage>
    ) -> SyntaxNodePath? {
        let identity = green.identity
        return tree.withRoot { root in
            root.withFirstNode(
                startingAt: offset,
                where: { candidate in
                    candidate.green { $0.identity == identity }
                }
            ) { match in
                match.childIndexPath()
            }?.value
        }
    }

    /// Replace the subtree at `target` with `replacement`, updating the
    /// session's current tree. The parser is NOT re-run; any diagnostics
    /// from the previous parse are stale relative to the resulting tree.
    ///
    /// Returns the new tree and the replacement witness. Any
    /// `SyntaxNodeHandle` captured before this call is invalidated by the
    /// new `treeID`.
    func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: ResolvedGreenNode<LiminalLanguage>
    ) throws -> StructuralReplaceOutput {
        guard let tree = lastTree else {
            throw LiminalEditError.noParsedTree
        }
        guard var ctx = context.take() else {
            throw LiminalEditError.noParsedTree
        }
        let result = try tree.replacing(target, with: replacement, context: &ctx)
        let witness = result.witness
        let newTree = result.intoTree().intoShared()
        context = consume ctx
        lastTree = newTree
        pendingEditsInvalidated = true
        return StructuralReplaceOutput(tree: newTree, witness: witness)
    }

    func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: GreenTreeSnapshot<LiminalLanguage>
    ) throws -> StructuralReplaceOutput {
        guard let tree = lastTree else {
            throw LiminalEditError.noParsedTree
        }
        guard var ctx = context.take() else {
            throw LiminalEditError.noParsedTree
        }
        let result = try tree.replacing(target, with: replacement, context: &ctx)
        let witness = result.witness
        let newTree = result.intoTree().intoShared()
        context = consume ctx
        lastTree = newTree
        pendingEditsInvalidated = true
        return StructuralReplaceOutput(tree: newTree, witness: witness)
    }

    func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: borrowing GreenBuildResult<LiminalLanguage>
    ) throws -> StructuralReplaceOutput {
        guard let tree = lastTree else {
            throw LiminalEditError.noParsedTree
        }
        guard var ctx = context.take() else {
            throw LiminalEditError.noParsedTree
        }
        let result = try tree.replacing(target, with: replacement, context: &ctx)
        let witness = result.witness
        let newTree = result.intoTree().intoShared()
        context = consume ctx
        lastTree = newTree
        pendingEditsInvalidated = true
        return StructuralReplaceOutput(tree: newTree, witness: witness)
    }
}

struct StructuralReplaceOutput {
    let tree: SharedSyntaxTree<LiminalLanguage>
    let witness: ReplacementWitness<LiminalLanguage>
}

public enum LiminalEditError: Error, Equatable, Sendable {
    case noParsedTree
    case overlappingEdits
    case editOutOfRange(start: UInt32, end: UInt32, sourceByteLength: Int)
}
