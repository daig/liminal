import CambiumCore
import CambiumSelection

enum StructuralCSTPasteTargetScope: Sendable, Equatable {
    case exactCursor
    case rootProjectedFromCursor
    case parentProjectedFromCursor(levels: UInt32)
    case nearestAncestorProjectedFromCursor(kind: LiminalKind)

    // Future scopes:
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
    private struct CursorFocus {
        let forest: LiminalForest
        let value: StructuralCSTPasteCursorFocus
    }

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
        case .parentProjectedFromCursor(let levels):
            return resolveParentProjectedFromCursor(
                levels: levels,
                in: tree,
                cursorByteOffset: cursorByteOffset
            )
        case .nearestAncestorProjectedFromCursor(let kind):
            return resolveNearestAncestorProjectedFromCursor(
                kind: kind,
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

    private static func resolveParentProjectedFromCursor(
        levels: UInt32,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite? {
        guard levels > 0,
              let focus = cursorFocus(in: tree, cursorByteOffset: cursorByteOffset)
        else { return nil }

        let childPath = focus.value.childPath
        guard Int(levels) <= childPath.depth else { return nil }

        let targetDepth = childPath.depth - Int(levels)
        let containerPath = LiminalCSTPath(
            Array(childPath.rawValue.prefix(targetDepth))
        )
        guard let referenceChildIndex = containerPath.projectedChildIndex(
            containing: childPath
        ) else { return nil }

        return resolveProjectedContainer(
            scope: .parentProjectedFromCursor(levels: levels),
            focus: focus,
            in: tree,
            containerPath: containerPath,
            referenceChildIndex: referenceChildIndex
        )
    }

    private static func resolveNearestAncestorProjectedFromCursor(
        kind: LiminalKind,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite? {
        guard let focus = cursorFocus(in: tree, cursorByteOffset: cursorByteOffset)
        else { return nil }

        let childPath = focus.value.childPath
        for depth in stride(from: childPath.depth, through: 0, by: -1) {
            let containerPath = LiminalCSTPath(
                Array(childPath.rawValue.prefix(depth))
            )
            let isExactFocusedChild = containerPath == childPath
            let referenceChildIndex = isExactFocusedChild
                ? nil
                : containerPath.projectedChildIndex(containing: childPath)

            guard let resolved = resolveProjectedContainer(
                scope: .nearestAncestorProjectedFromCursor(kind: kind),
                focus: focus,
                in: tree,
                containerPath: containerPath,
                referenceChildIndex: referenceChildIndex,
                cursorByteOffsetForExactContainer: isExactFocusedChild
                    ? cursorByteOffset
                    : nil
            ) else { continue }

            guard case .projectedContainer(let projected) = resolved.site.target,
                  projected.containerKind == kind
            else { continue }
            if isExactFocusedChild,
               projected.referenceChildIndex == nil
            {
                continue
            }

            return resolved
        }
        return nil
    }

    private static func resolveRootProjectedFromCursor(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> ResolvedStructuralCSTPasteSite? {
        let focus = cursorFocus(in: tree, cursorByteOffset: cursorByteOffset)
        return tree.withRoot { root in
            let rootPath = root.liminalCSTPath
            let referenceChildIndex = projectedReferenceChildIndex(
                in: root,
                cursorByteOffset: cursorByteOffset
            )
            return resolvedProjectedSite(
                scope: .rootProjectedFromCursor,
                focus: focus,
                container: root,
                containerPath: rootPath,
                referenceChildIndex: referenceChildIndex
            )
        }
    }

    private static func cursorFocus(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> CursorFocus? {
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
            return CursorFocus(
                forest: forest,
                value: StructuralCSTPasteCursorFocus(
                    parentPath: parentPath,
                    childPath: parentPath.appending(childIndex),
                    childIndex: childIndex,
                    parentKind: parent.kind,
                    childKind: childKind
                )
            )
        }
    }

    private static func resolveProjectedContainer(
        scope: StructuralCSTPasteTargetScope,
        focus: CursorFocus,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        containerPath: LiminalCSTPath,
        referenceChildIndex: UInt32?,
        cursorByteOffsetForExactContainer: TextSize? = nil
    ) -> ResolvedStructuralCSTPasteSite? {
        tree.withRoot { root in
            if containerPath.isRoot {
                let referenceChildIndex = cursorByteOffsetForExactContainer.map {
                    projectedReferenceChildIndex(
                        in: root,
                        cursorByteOffset: $0
                    )
                } ?? referenceChildIndex
                return resolvedProjectedSite(
                    scope: scope,
                    focus: focus,
                    container: root,
                    containerPath: containerPath,
                    referenceChildIndex: referenceChildIndex
                )
            }

            return root.withDescendant(atPath: containerPath.rawValue) {
                container -> ResolvedStructuralCSTPasteSite? in
                let referenceChildIndex = cursorByteOffsetForExactContainer.map {
                    projectedReferenceChildIndex(
                        in: container,
                        cursorByteOffset: $0
                    )
                } ?? referenceChildIndex
                return resolvedProjectedSite(
                    scope: scope,
                    focus: focus,
                    container: container,
                    containerPath: containerPath,
                    referenceChildIndex: referenceChildIndex
                )
            } ?? nil
        }
    }

    private static func resolvedProjectedSite(
        scope: StructuralCSTPasteTargetScope,
        focus: CursorFocus?,
        container: borrowing SyntaxNodeCursor<LiminalLanguage>,
        containerPath: LiminalCSTPath,
        referenceChildIndex: UInt32?
    ) -> ResolvedStructuralCSTPasteSite? {
        guard let projected = projectedContainer(
            container: container,
            containerPath: containerPath,
            referenceChildIndex: referenceChildIndex
        ) else { return nil }

        let site = StructuralCSTPasteSite(
            scope: scope,
            originFocus: focus?.value,
            target: .projectedContainer(projected)
        )
        return ResolvedStructuralCSTPasteSite(
            site: site,
            originForest: focus?.forest,
            containerHandle: container.makeHandle(),
            exactTargetForest: nil
        )
    }

    private static func projectedReferenceChildIndex(
        in container: borrowing SyntaxNodeCursor<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> UInt32? {
        let count = container.childOrTokenCount
        guard count > 0 else { return nil }

        let cursor = min(cursorByteOffset.rawValue, container.textRange.end.rawValue)
        var containingIndex = count - 1
        for index in 0..<count {
            let range = container.childTextRange(at: index)
            if cursor <= range.start.rawValue || cursor < range.end.rawValue {
                containingIndex = index
                break
            }
        }
        return UInt32(containingIndex)
    }

    private static func projectedContainer(
        container: borrowing SyntaxNodeCursor<LiminalLanguage>,
        containerPath: LiminalCSTPath,
        referenceChildIndex: UInt32?
    ) -> StructuralCSTPasteProjectedContainer? {
        guard let referenceChildIndex else {
            return StructuralCSTPasteProjectedContainer(
                containerPath: containerPath,
                containerKind: container.kind,
                referenceChildIndex: nil,
                referenceChildKind: nil,
                referenceChildPath: nil
            )
        }

        let index = Int(referenceChildIndex)
        guard index < container.childOrTokenCount else { return nil }

        let childKind = container.green { green in
            green.child(at: index)
        }.kind
        return StructuralCSTPasteProjectedContainer(
            containerPath: containerPath,
            containerKind: container.kind,
            referenceChildIndex: referenceChildIndex,
            referenceChildKind: childKind,
            referenceChildPath: containerPath.appending(referenceChildIndex)
        )
    }
}
