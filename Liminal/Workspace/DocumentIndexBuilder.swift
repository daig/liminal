import CambiumCore
import Foundation

/// One CST node's contribution to the `DocumentIndex`, in coordinates
/// **relative to the node's own start** when stored in the memo, and absolute
/// while a fold is in flight. Snippets are position-independent (the
/// reference's offset is relative to its enclosing block's text), so they are
/// never shifted.
struct DocumentIndexContribution: Sendable {
    var blocks: [BlockAnchor] = []
    var references: [DocumentReference] = []

    static let empty = DocumentIndexContribution()

    mutating func merge(_ other: DocumentIndexContribution) {
        blocks.append(contentsOf: other.blocks)
        references.append(contentsOf: other.references)
    }

    func shifted(by delta: Int) -> DocumentIndexContribution {
        guard delta != 0 else { return self }
        return DocumentIndexContribution(
            blocks: blocks.map {
                BlockAnchor(
                    blockID: $0.blockID,
                    sourceOffset: TextSize(UInt32(Int($0.sourceOffset.rawValue) + delta))
                )
            },
            references: references.map {
                DocumentReference(
                    kind: $0.kind,
                    target: $0.target,
                    alias: $0.alias,
                    sourceRange: DocumentIndexBuilder.shift($0.sourceRange, by: delta),
                    targetRange: $0.targetRange.map { DocumentIndexBuilder.shift($0, by: delta) },
                    snippet: $0.snippet
                )
            }
        )
    }
}

/// Memo carried across reparses: each substantial subtree's contribution keyed
/// by its content hash. Because `ContentHash` is content-determined (not
/// identity-based), an unchanged subtree hits even when the parser rebuilt it
/// from scratch — so the index reuses exactly what the tree leaves unchanged,
/// at whatever granularity the tree provides. Double-buffered: a build reads
/// the previous memo and returns a fresh one populated as it folds.
typealias DocumentIndexMemo = [ContentHash: DocumentIndexContribution]

/// Builds a `DocumentIndex` as a memoized bottom-up fold over the CST. On a
/// reparse, subtrees whose content is unchanged reuse their cached
/// contribution (skipping the descent and snippet extraction); only the
/// changed region is re-walked.
struct DocumentIndexBuilder {
    private let source: CambiumSource?
    private let previousMemo: DocumentIndexMemo
    private var newMemo: DocumentIndexMemo = [:]

    /// Reuse instrumentation (read by tests / debug). A hit means a subtree's
    /// contribution was reused from `previousMemo` without descending.
    private(set) var reuseHits = 0
    private(set) var reuseMisses = 0

    init(source: CambiumSource? = nil, previousMemo: DocumentIndexMemo? = nil) {
        self.source = source
        self.previousMemo = previousMemo ?? [:]
    }

    /// Fold the document. `blockOffsets` and the document-outline `headings`
    /// are top-level-only, so they are gathered in this O(#top-level-children)
    /// root pass; `blocks` and `references` come from the per-node fold.
    mutating func build(root: RootSyntax) -> (index: DocumentIndex, memo: DocumentIndexMemo) {
        var blockOffsets: [TextSize] = []
        var headings: [HeadingAnchor] = []
        var blocks: [BlockAnchor] = []
        var references: [DocumentReference] = []

        for item in root.documentItems {
            if case .blankLine = item { continue }
            blockOffsets.append(item.range.start)

            // Only top-level headings populate the outline. Nested headings
            // (inside typed block bodies, block literals, etc.) are content;
            // anchor inside those via a block ID instead.
            if case .atxHeading(let heading) = item {
                let title = heading.inlineContent?.plainText ?? ""
                if !WikiLinkNormalizer.headingLookupKey(title).isEmpty {
                    headings.append(HeadingAnchor(
                        title: title,
                        sourceOffset: heading.range.start,
                        level: heading.level
                    ))
                }
            }

            let contribution = foldNode(item.syntax)
            blocks.append(contentsOf: contribution.blocks)
            references.append(contentsOf: contribution.references)
        }

        let index = DocumentIndex(
            blockOffsets: blockOffsets,
            headings: headings,
            blocks: blocks,
            references: references
        )
        return (index, newMemo)
    }

    // MARK: - Memoized fold

    private mutating func foldNode(
        _ handle: SyntaxNodeHandle<LiminalLanguage>
    ) -> DocumentIndexContribution {
        let (hash, range) = handle.withCursor { ($0.greenHash, $0.textRange) }
        let start = Int(range.start.rawValue)

        if let cached = previousMemo[hash] {
            // Reused subtree: carry the (relative) contribution forward and
            // rebase it to this node's current absolute position. Skips the
            // descent entirely.
            reuseHits += 1
            newMemo[hash] = cached
            return cached.shifted(by: start)
        }

        reuseMisses += 1
        let contribution = computeNode(handle)
        // Memoize exactly the nodes whose reuse saves real work: those that
        // produced index entries (a hit skips the snippet extraction /
        // `WikiTarget.parse` / descent that built them). Entry-less subtrees
        // re-fold by cheap traversal alone — and any *entry-bearing* ancestor
        // is itself memoized (its contribution carries the descendant
        // entries), so an unchanged region above a reference is still skipped
        // wholesale on a hit. No size heuristic needed.
        if !contribution.references.isEmpty || !contribution.blocks.isEmpty {
            newMemo[hash] = contribution.shifted(by: -start)
        }
        return contribution
    }

    /// Dispatch a node to its kind-specific fold. Mirrors the typed structure
    /// so recursion stays *selective* (e.g. a wikilink's alias text is read
    /// for the alias string but not descended for references).
    private mutating func computeNode(
        _ handle: SyntaxNodeHandle<LiminalLanguage>
    ) -> DocumentIndexContribution {
        if let item = DocumentItemSyntax(handle) {
            return computeItem(item)
        }
        if let inline = InlineSyntax(handle) {
            return computeInline(inline)
        }
        if let value = ValueSyntax(handle) {
            return computeValue(value)
        }
        switch LiminalLanguage.kind(for: handle.rawKind) {
        case .listItem:
            return computeListItem(ListItemSyntax(unchecked: handle))
        case .inlineContent:
            return computeInlineContent(InlineContentSyntax(unchecked: handle))
        case .fields:
            return computeFields(FieldsSyntax(unchecked: handle))
        case .field:
            return computeValueNode(FieldSyntax(unchecked: handle).value)
        case .value:
            return computeValueNode(ValueNodeSyntax(unchecked: handle))
        default:
            return computeGenericChildren(handle)
        }
    }

    private mutating func computeItem(_ item: DocumentItemSyntax) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        switch item {
        case .blankLine, .frontmatter, .directive, .schemaBlock,
             .thematicBreak, .fencedCodeBlock, .mathBlock, .htmlBlock, .commentBlock:
            break
        case .templateBlock(let template):
            for child in template.documentItems {
                c.merge(foldNode(child.syntax))
            }
        case .paragraph(let paragraph):
            appendBlockID(&c, token: paragraph.blockIdToken, at: paragraph.range.start)
            if let content = paragraph.inlineContent {
                c.merge(foldNode(content.syntax))
            }
            stamp(&c, scope: paragraph.range)
        case .atxHeading(let heading):
            appendBlockID(&c, token: heading.blockIdToken, at: heading.range.start)
            if let content = heading.inlineContent {
                c.merge(foldNode(content.syntax))
            }
            stamp(&c, scope: heading.range)
        case .wikiEmbedBlock(let embed):
            appendReference(
                &c,
                kind: .embed,
                targetToken: embed.targetTextToken,
                alias: embed.payloadToken?.text,
                sourceRange: embed.range
            )
            stamp(&c, scope: embed.range)
        case .structuredEmbedBlock(let embed):
            appendDestination(
                &c,
                kind: .embed,
                targetToken: embed.targetTextToken,
                sourceRange: embed.range
            )
            if let fallback = embed.fallbackContent {
                c.merge(foldNode(fallback.syntax))
            }
            stamp(&c, scope: embed.range)
        case .list(let list):
            for listItem in list.items {
                c.merge(foldNode(listItem.syntax))
            }
        case .blockQuote(let quote):
            for child in quote.documentItems {
                c.merge(foldNode(child.syntax))
            }
        case .pipeTable(let table):
            c.merge(computePipeTable(table))
        case .valueDeclaration(let declaration):
            if let constructor = declaration.constructor {
                c.merge(computeGenericChildren(constructor.syntax))
            }
        case .typedBlock(let block):
            c.merge(computeGenericChildren(block.syntax))
        }
        return c
    }

    private mutating func computePipeTable(_ table: PipeTableSyntax) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        for cell in table.headerCells {
            c.merge(computeCell(cell.inlineContent))
        }
        for row in table.bodyRows {
            for cell in row {
                c.merge(computeCell(cell.inlineContent))
            }
        }
        return c
    }

    private mutating func computeCell(_ content: InlineContentSyntax?) -> DocumentIndexContribution {
        guard let content else { return .empty }
        var c = foldNode(content.syntax)
        stamp(&c, scope: content.range)
        return c
    }

    private mutating func computeListItem(_ item: ListItemSyntax) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        appendBlockID(&c, token: item.blockIdToken, at: item.range.start)
        for child in item.documentItems {
            c.merge(foldNode(child.syntax))
        }
        return c
    }

    private mutating func computeInlineContent(
        _ content: InlineContentSyntax
    ) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        for inline in content.inlineNodes {
            c.merge(foldNode(inline.syntax))
        }
        return c
    }

    private mutating func computeInline(_ inline: InlineSyntax) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        switch inline {
        case .codeSpan, .escapedPunctuation, .mathInline, .interpolation, .inlineComment:
            break
        case .wikilink(let wikilink):
            appendReference(
                &c,
                kind: .link,
                targetToken: wikilink.targetTextToken,
                alias: wikilink.aliasContent?.plainText,
                sourceRange: wikilink.range
            )
        case .wikiEmbed(let embed):
            appendReference(
                &c,
                kind: .embed,
                targetToken: embed.targetTextToken,
                alias: embed.payloadToken?.text,
                sourceRange: embed.range
            )
        case .structuredEmbed(let embed):
            appendDestination(
                &c,
                kind: .embed,
                targetToken: embed.targetTextToken,
                sourceRange: embed.range
            )
            if let fallback = embed.fallbackContent {
                c.merge(foldNode(fallback.syntax))
            }
        case .typedInline(let typedInline):
            if let constructor = typedInline.constructor {
                c.merge(computeGenericChildren(constructor.syntax))
            }
        case .emphasis(let emphasis):
            if let content = emphasis.inlineContent { c.merge(foldNode(content.syntax)) }
        case .strong(let strong):
            if let content = strong.inlineContent { c.merge(foldNode(content.syntax)) }
        case .strikethrough(let strikethrough):
            if let content = strikethrough.inlineContent { c.merge(foldNode(content.syntax)) }
        case .highlight(let highlight):
            if let content = highlight.inlineContent { c.merge(foldNode(content.syntax)) }
        case .footnoteInline(let footnote):
            if let content = footnote.inlineContent { c.merge(foldNode(content.syntax)) }
        case .mdLink(let link):
            appendDestination(
                &c,
                kind: .link,
                targetToken: link.destinationTextToken,
                sourceRange: link.range,
                alias: link.labelContent?.plainText
            )
            if let label = link.labelContent { c.merge(foldNode(label.syntax)) }
        case .autolink(let autolink):
            appendDestination(
                &c,
                kind: .link,
                targetToken: autolink.targetTextToken,
                sourceRange: autolink.range,
                alias: autolink.targetText,
                targetText: autolink.hrefText
            )
        case .mdImage(let image):
            appendDestination(
                &c,
                kind: .embed,
                targetToken: image.destinationTextToken,
                sourceRange: image.range,
                alias: image.altContent?.plainText
            )
            if let alt = image.altContent { c.merge(foldNode(alt.syntax)) }
        }
        return c
    }

    private mutating func computeValueNode(_ value: ValueNodeSyntax?) -> DocumentIndexContribution {
        guard let payload = value?.payload else { return .empty }
        return computeValue(payload)
    }

    private mutating func computeValue(_ value: ValueSyntax) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        switch value {
        case .scalar, .reference:
            break
        case .list(let list):
            for nested in list.values {
                c.merge(computeValueNode(nested))
            }
        case .record(let record):
            c.merge(computeFields(record.fields))
        case .typedConstructor(let constructor):
            c.merge(computeGenericChildren(constructor.syntax))
        case .inlineLiteral(let literal):
            if let content = literal.inlineContent {
                c.merge(foldNode(content.syntax))
                stamp(&c, scope: content.range)
            }
        case .blockLiteral(let literal):
            for item in literal.documentItems {
                c.merge(foldNode(item.syntax))
            }
        case .structuredEmbedValue(let embed):
            if let fallback = embed.fallbackContent {
                c.merge(foldNode(fallback.syntax))
                stamp(&c, scope: fallback.range)
            }
        }
        return c
    }

    private mutating func computeFields(_ fields: FieldsSyntax?) -> DocumentIndexContribution {
        var c = DocumentIndexContribution.empty
        for field in fields?.fields ?? [] {
            c.merge(computeValueNode(field.value))
        }
        return c
    }

    private mutating func computeGenericChildren(
        _ handle: SyntaxNodeHandle<LiminalLanguage>
    ) -> DocumentIndexContribution {
        var childHandles: [SyntaxNodeHandle<LiminalLanguage>] = []
        handle.withCursor { node in
            node.forEachChild { childHandles.append($0.makeHandle()) }
        }
        var c = DocumentIndexContribution.empty
        for child in childHandles {
            c.merge(foldNode(child))
        }
        return c
    }

    // MARK: - Entry emission (absolute, snippet stamped later)

    private func appendBlockID(
        _ c: inout DocumentIndexContribution,
        token: LiminalTokenSyntax?,
        at sourceOffset: TextSize
    ) {
        guard let token else { return }
        c.blocks.append(BlockAnchor(blockID: token.text, sourceOffset: sourceOffset))
    }

    private func appendReference(
        _ c: inout DocumentIndexContribution,
        kind: ReferenceKind,
        targetToken: LiminalTokenSyntax?,
        alias: String?,
        sourceRange: LiminalSourceRange
    ) {
        guard let targetToken else { return }
        c.references.append(DocumentReference(
            kind: kind,
            target: WikiTarget.parse(targetToken.text),
            alias: alias,
            sourceRange: sourceRange,
            targetRange: targetToken.range,
            snippet: .empty
        ))
    }

    /// Markdown link/image destinations and structured embed targets.
    /// `WikiTarget.parse` routes external URIs into the external case;
    /// everything else parses as a vault target. Empty destinations are
    /// dropped so `[label]()` / `![alt]()` don't pollute the index.
    private func appendDestination(
        _ c: inout DocumentIndexContribution,
        kind: ReferenceKind,
        targetToken: LiminalTokenSyntax?,
        sourceRange: LiminalSourceRange,
        alias: String? = nil,
        targetText: String? = nil
    ) {
        guard let targetToken else { return }
        let raw = targetText ?? targetToken.text
        let trimmedAlias: String? = alias.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let target = WikiTarget.parse(raw)
        if target.notePath == nil,
           target.heading == nil,
           target.blockID == nil,
           target.externalURI == nil
        {
            return
        }
        c.references.append(DocumentReference(
            kind: kind,
            target: target,
            alias: trimmedAlias,
            sourceRange: sourceRange,
            targetRange: targetToken.range,
            snippet: .empty
        ))
    }

    // MARK: - Snippet stamping

    /// Stamp every still-unstamped reference in `c` with the text of `scope`
    /// (the nearest enclosing block-level node). Newlines collapse to spaces;
    /// ASCII whitespace is trimmed from each end without crossing the
    /// reference. The snippet is relative to `scope`, so it's
    /// position-independent and survives reuse. No-op without `source`.
    private func stamp(_ c: inout DocumentIndexContribution, scope: LiminalSourceRange) {
        guard let source,
              c.references.contains(where: { $0.snippet == .empty })
        else { return }
        let scopeStart = Int(scope.start.rawValue)
        let scopeEnd = Int(scope.end.rawValue)
        guard scopeStart >= 0, scopeEnd > scopeStart, scopeEnd <= source.byteCount else { return }

        var bytes = source.bytes(in: TextRange(
            start: TextSize(UInt32(scopeStart)),
            end: TextSize(UInt32(scopeEnd))
        ))
        for i in bytes.indices where bytes[i] == 0x0A || bytes[i] == 0x0D {
            bytes[i] = 0x20
        }

        for i in c.references.indices {
            guard c.references[i].snippet == .empty else { continue }
            let ref = c.references[i]
            let initialOffset = max(0, Int(ref.sourceRange.start.rawValue) - scopeStart)
            let initialLength = min(Int(ref.sourceRange.length.rawValue), max(0, bytes.count - initialOffset))
            let refEnd = initialOffset + initialLength

            var leading = 0
            while leading < bytes.count, leading < initialOffset, Self.isAsciiWhitespace(bytes[leading]) {
                leading += 1
            }
            var trailing = 0
            while trailing < bytes.count - leading,
                  bytes.count - trailing > refEnd,
                  Self.isAsciiWhitespace(bytes[bytes.count - trailing - 1])
            {
                trailing += 1
            }

            let slice = Array(bytes[leading..<(bytes.count - trailing)])
            let text = String(decoding: slice, as: UTF8.self)
            let finalOffset = max(0, initialOffset - leading)
            let finalLength = min(initialLength, max(0, slice.count - finalOffset))
            c.references[i] = DocumentReference(
                kind: ref.kind,
                target: ref.target,
                alias: ref.alias,
                sourceRange: ref.sourceRange,
                targetRange: ref.targetRange,
                snippet: DocumentSnippet(
                    text: text,
                    referenceOffset: UInt32(finalOffset),
                    referenceLength: UInt32(finalLength)
                )
            )
        }
    }

    private static func isAsciiWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }

    fileprivate static func shift(_ range: LiminalSourceRange, by delta: Int) -> LiminalSourceRange {
        TextRange(
            start: TextSize(UInt32(Int(range.start.rawValue) + delta)),
            end: TextSize(UInt32(Int(range.end.rawValue) + delta))
        )
    }
}
