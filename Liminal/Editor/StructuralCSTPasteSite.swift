import CambiumCore
import CambiumSelection

enum StructuralCSTPasteTargetScope: Sendable, Equatable {
    case exactCursor
    case rootProjectedFromCursor

    // Future scopes:
    // case parentProjectedFromCursor(levels: Int)
    // case nearestAncestorProjectedFromCursor(kind: LiminalKind)
    // case outermostAncestorProjectedFromCursor(kind: LiminalKind)
    // case selectedTarget(origin: LiminalCSTPath, target: LiminalCSTPath)
    // case markedTarget(name: Character)
    // case explicitPath(LiminalCSTPath)
}

struct StructuralCSTPasteCursorFocus: Sendable, Equatable {
    let parentPath: LiminalCSTPath
    let childPath: LiminalCSTPath
    let childIndex: UInt32
    let parentKind: LiminalKind
    let childKind: LiminalKind
}

struct StructuralCSTPasteProjectedContainer: Sendable, Equatable {
    let containerPath: LiminalCSTPath
    let containerKind: LiminalKind
    let referenceChildIndex: UInt32?
    let referenceChildKind: LiminalKind?
    let referenceChildPath: LiminalCSTPath?
}

struct StructuralCSTPasteSite: Sendable, Equatable {
    enum Target: Sendable, Equatable {
        case exact(StructuralCSTPasteCursorFocus)
        case projectedContainer(StructuralCSTPasteProjectedContainer)
    }

    let scope: StructuralCSTPasteTargetScope
    let originFocus: StructuralCSTPasteCursorFocus?
    let target: Target
}

struct ResolvedStructuralCSTPasteSite {
    let site: StructuralCSTPasteSite
    let originForest: LiminalForest?
    let containerHandle: SyntaxNodeHandle<LiminalLanguage>
    let exactTargetForest: LiminalForest?
}

enum StructuralCSTPasteSiteResolver {
    static func resolve(
        scope: StructuralCSTPasteTargetScope,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite? {
        switch scope {
        case .exactCursor:
            return resolveExactCursor(in: tree, cursorByteOffset: cursorByteOffset)
        case .rootProjectedFromCursor:
            return resolveRootProjectedFromCursor(
                in: tree,
                cursorByteOffset: cursorByteOffset
            )
        }
    }

    private static func resolveExactCursor(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite? {
        guard let focus = cursorFocus(in: tree, cursorByteOffset: cursorByteOffset)
        else { return nil }

        let site = StructuralCSTPasteSite(
            scope: .exactCursor,
            originFocus: focus.value,
            target: .exact(focus.value)
        )
        return ResolvedStructuralCSTPasteSite(
            site: site,
            originForest: focus.forest,
            containerHandle: focus.forest.parent,
            exactTargetForest: focus.forest
        )
    }

    private static func resolveRootProjectedFromCursor(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite {
        let focus = cursorFocus(in: tree, cursorByteOffset: cursorByteOffset)
        return tree.withRoot { root in
            let rootHandle = root.makeHandle()
            let rootPath = root.liminalCSTPath
            let projected = rootProjectedContainer(
                root: root,
                rootPath: rootPath,
                cursorByteOffset: cursorByteOffset
            )
            let site = StructuralCSTPasteSite(
                scope: .rootProjectedFromCursor,
                originFocus: focus?.value,
                target: .projectedContainer(projected)
            )
            return ResolvedStructuralCSTPasteSite(
                site: site,
                originForest: focus?.forest,
                containerHandle: rootHandle,
                exactTargetForest: nil
            )
        }
    }

    private static func cursorFocus(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> (forest: LiminalForest, value: StructuralCSTPasteCursorFocus)? {
        guard let forest = LiminalForest.cursorTarget(
            at: cursorByteOffset,
            in: tree
        ) else {
            return nil
        }

        return forest.parent.withCursor { parent in
            let parentPath = parent.liminalCSTPath
            let childIndex = UInt32(forest.anchorChildIndex)
            let childKind = parent.green { green in
                green.child(at: forest.anchorChildIndex)
            }.kind
            return (
                forest,
                StructuralCSTPasteCursorFocus(
                    parentPath: parentPath,
                    childPath: parentPath.appending(childIndex),
                    childIndex: childIndex,
                    parentKind: parent.kind,
                    childKind: childKind
                )
            )
        }
    }

    private static func rootProjectedContainer(
        root: borrowing SyntaxNodeCursor<LiminalLanguage>,
        rootPath: LiminalCSTPath,
        cursorByteOffset: TextSize
    ) -> StructuralCSTPasteProjectedContainer {
        let count = root.childOrTokenCount
        guard count > 0 else {
            return StructuralCSTPasteProjectedContainer(
                containerPath: rootPath,
                containerKind: root.kind,
                referenceChildIndex: nil,
                referenceChildKind: nil,
                referenceChildPath: nil
            )
        }

        let cursor = min(cursorByteOffset.rawValue, root.textRange.end.rawValue)
        var containingIndex = count - 1
        for index in 0..<count {
            let range = root.childTextRange(at: index)
            if cursor <= range.start.rawValue || cursor < range.end.rawValue {
                containingIndex = index
                break
            }
        }

        let childIndex = UInt32(containingIndex)
        let childKind = root.green { green in
            green.child(at: containingIndex)
        }.kind
        return StructuralCSTPasteProjectedContainer(
            containerPath: rootPath,
            containerKind: root.kind,
            referenceChildIndex: childIndex,
            referenceChildKind: childKind,
            referenceChildPath: rootPath.appending(childIndex)
        )
    }
}
