import CambiumCore

/// CST queries that the vim layer needs to navigate by structure and
/// invoke structural actions. AppKit-free; takes a `RootSyntax` and a
/// byte offset, returns offsets / handles.
public enum StructureCursor {

    /// Byte offset of the previous direct sibling, within the smallest
    /// container node that holds `offset`. Returns nil if there is no
    /// previous sibling, or if the offset isn't inside a container with
    /// document-item children.
    public static func previousSibling(
        of offset: Int,
        in root: RootSyntax
    ) -> Int? {
        siblingOffset(of: offset, in: root, direction: .previous)
    }

    /// Byte offset of the next direct sibling.
    public static func nextSibling(
        of offset: Int,
        in root: RootSyntax
    ) -> Int? {
        siblingOffset(of: offset, in: root, direction: .next)
    }

    /// Locates the task-list item containing `offset` and returns its
    /// marker location and state. Returns nil if the cursor isn't inside
    /// a list item with a task marker.
    public static func taskListItem(
        at offset: Int,
        in root: RootSyntax
    ) -> TaskMarkerLocation? {
        let targetOffset = TextSize(UInt32(max(0, offset)))
        var found: TaskMarkerLocation?
        root.syntax.withCursor { cursor in
            _ = cursor.visitPreorder { node in
                let range = node.textRange
                guard range.start <= targetOffset, targetOffset <= range.end else {
                    return .skipChildren
                }
                if LiminalLanguage.kind(for: node.rawKind) == .listItem {
                    let handle = node.makeHandle()
                    let item = ListItemSyntax(unchecked: handle)
                    if let markerToken = item.taskMarkerToken,
                       let state = item.taskState {
                        found = TaskMarkerLocation(
                            markerByteRange: markerToken.range,
                            state: state,
                            listItemHandle: handle
                        )
                        return .stop
                    }
                }
                return .continue
            }
        }
        return found
    }

    // MARK: - Sibling traversal

    private enum Direction { case previous, next }

    private static func siblingOffset(
        of offset: Int,
        in root: RootSyntax,
        direction: Direction
    ) -> Int? {
        let targetOffset = TextSize(UInt32(max(0, offset)))
        // Collect the container chain so we can fall back from a deep
        // container (typed-block body, list item) outward if no sibling
        // exists at the inner level. Each entry's children list and the
        // cursor's index in it.
        var siblingsChain: [(siblings: [TextRange], indexAtCursor: Int)] = []

        root.syntax.withCursor { cursor in
            walkContainerChain(
                cursor,
                target: targetOffset,
                into: &siblingsChain
            )
        }

        // Try innermost container first; if no sibling in that direction,
        // pop outward.
        for level in siblingsChain.reversed() {
            let siblings = level.siblings
            let i = level.indexAtCursor
            guard !siblings.isEmpty else { continue }
            switch direction {
            case .previous:
                if i > 0 {
                    return Int(siblings[i - 1].start.rawValue)
                }
            case .next:
                if i + 1 < siblings.count {
                    return Int(siblings[i + 1].start.rawValue)
                }
            }
        }
        return nil
    }

    private static func walkContainerChain(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        target: TextSize,
        into chain: inout [(siblings: [TextRange], indexAtCursor: Int)]
    ) {
        let nodeKind = LiminalLanguage.kind(for: cursor.rawKind)
        if Self.isContainer(nodeKind) {
            let entry = collectSiblings(cursor, cursorOffset: target)
            chain.append(entry)
        }
        // Descend into the child whose range contains `target`.
        cursor.forEachChild { child in
            let range = child.textRange
            if range.start <= target && target <= range.end {
                walkContainerChain(child, target: target, into: &chain)
            }
        }
    }

    private static func collectSiblings(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        cursorOffset: TextSize
    ) -> (siblings: [TextRange], indexAtCursor: Int) {
        var siblings: [TextRange] = []
        var indexAtCursor = -1
        var i = 0
        cursor.forEachChild { child in
            let kind = LiminalLanguage.kind(for: child.rawKind)
            if Self.isDocumentItem(kind) {
                let range = child.textRange
                siblings.append(range)
                if range.start <= cursorOffset && cursorOffset <= range.end {
                    indexAtCursor = i
                }
                i += 1
            }
        }
        // If we couldn't pin the cursor to a specific sibling (it falls
        // between or past them), index is left at -1; callers handle that
        // as "no sibling in this direction within this container."
        return (siblings, indexAtCursor)
    }

    /// Kinds that own a list of document-item children. Used to walk the
    /// container chain for structural `{` / `}`.
    private static func isContainer(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .root, .blockQuote, .listItem, .typedBlock,
             .schemaBlock, .templateBlock, .structuredEmbedBlock:
            return true
        default:
            return false
        }
    }

    /// Kinds that count as siblings for `{` / `}` motion. Excludes
    /// blankLine (we skip blanks when navigating structurally) and
    /// inline kinds.
    private static func isDocumentItem(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .blankLine:
            return false
        case .paragraph, .atxHeading, .frontmatter, .directive,
             .valueDeclaration, .thematicBreak, .list, .listItem,
             .blockQuote, .fencedCodeBlock, .mathBlock, .htmlBlock,
             .commentBlock, .typedBlock, .pipeTable,
             .structuredEmbedBlock, .wikiEmbedBlock,
             .schemaBlock, .templateBlock:
            return true
        default:
            return false
        }
    }
}

/// Locator returned by `StructureCursor.taskListItem(at:in:)`.
public struct TaskMarkerLocation: Sendable {
    public let markerByteRange: TextRange
    public let state: TaskMarkerState
    public let listItemHandle: SyntaxNodeHandle<LiminalLanguage>

    public init(
        markerByteRange: TextRange,
        state: TaskMarkerState,
        listItemHandle: SyntaxNodeHandle<LiminalLanguage>
    ) {
        self.markerByteRange = markerByteRange
        self.state = state
        self.listItemHandle = listItemHandle
    }
}
