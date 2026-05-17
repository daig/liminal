import CambiumCore
import CambiumSelection

/// Value-typed structural motion vocabulary for ``LiminalForest`` —
/// the Traverse kernel that backs `.visualCST` chord navigation.
///
/// A `ForestMotion` captures `axis × direction × predicate × count-semantics`
/// and is consumed by ``CambiumSelection/SyntaxForest/moved(by:extending:)``
/// (single step) and ``CambiumSelection/SyntaxForest/moved(by:extending:count:)``
/// (looped with saturation).
///
/// One "logical step" of a motion walks along its axis in its direction
/// until the predicate matches or the axis exhausts. So `h` with
/// `.ancestor(.excluding(.glueWrapper))` walks past as many glue
/// ancestors as needed in a single step.
///
/// `ForestMotion` is intentionally NOT `Equatable`/`Hashable`: the
/// `.custom` predicate carries a closure. Motions are transient
/// computation specs, not keys.
public struct ForestMotion: Sendable {

    /// The dimension a motion walks along.
    public enum Axis: Sendable, Equatable, Hashable {
        /// Stay under the same parent; hop by sibling index.
        case sibling
        /// Walk up the parent chain.
        case ancestor
        /// Walk down the first-child chain.
        case descendant
        /// Walk the whole document in source order (descend-first preorder).
        case preorder
        /// Walk preorder forward but bounded by the starting forest's
        /// subtree (the node pointed at by the head). `.forward` returns
        /// the first predicate match; `.backward` returns the last.
        /// Backs vim-style `f` / `F` typed descent.
        case subtreePreorder
    }

    /// Walk direction along the axis. ``Axis/ancestor`` ignores direction
    /// (only "up" exists); ``Axis/descendant`` ignores direction (only
    /// "down" exists). The factory helpers fix `.forward` for those axes.
    public enum Direction: Sendable, Equatable, Hashable {
        case forward, backward
    }

    /// How counts compose. v2 supports only ``CountSemantics/repeatStep``;
    /// `.nthAbsolute` (for `gg`/`G`-style chords) will be added when its
    /// first consumer lands.
    public enum CountSemantics: Sendable, Equatable, Hashable {
        /// Apply the single-step resolver `count` times, saturating at
        /// the last successful position.
        case repeatStep
    }

    /// What counts as a match. Evaluated against a candidate forest's
    /// head-child kind via its ``LiminalStructuralCategory`` set.
    public enum Predicate: Sendable {
        /// Any navigable forest matches.
        case any
        /// `kind.categories.intersection(set)` is non-empty.
        case containingAny(LiminalStructuralCategory)
        /// `kind.categories.isSuperset(of: set)`.
        case containingAll(LiminalStructuralCategory)
        /// `kind.categories.intersection(set)` is empty.
        case excluding(LiminalStructuralCategory)
        /// `set.contains(kind)`.
        case kindIn(Set<LiminalKind>)
        /// Categories masked by `mask` differ from the step's *starting*
        /// forest's categories masked the same way. Backs vim `w`/`b`:
        /// `3w` crosses three independent category boundaries, each
        /// rebased to the new position (snapshot is per-step, not
        /// once-per-resolve).
        case differentFrom(LiminalStructuralCategory)
        /// Escape hatch.
        case custom(@Sendable (LiminalForest) -> Bool)
    }

    public let axis: Axis
    public let direction: Direction
    public let predicate: Predicate
    public let countSemantics: CountSemantics

    public init(
        axis: Axis,
        direction: Direction,
        predicate: Predicate = .any,
        countSemantics: CountSemantics = .repeatStep
    ) {
        self.axis = axis
        self.direction = direction
        self.predicate = predicate
        self.countSemantics = countSemantics
    }
}

// MARK: - Ergonomic factories

public extension ForestMotion {
    static func siblingForward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .sibling, direction: .forward, predicate: predicate)
    }

    static func siblingBackward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .sibling, direction: .backward, predicate: predicate)
    }

    /// Direction is irrelevant for the ancestor axis; `.forward` is a
    /// placeholder so the value-type uniformly carries all four axes.
    static func ancestor(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .ancestor, direction: .forward, predicate: predicate)
    }

    /// Direction is irrelevant for the descendant axis.
    static func descendant(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .descendant, direction: .forward, predicate: predicate)
    }

    static func preorderForward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .preorder, direction: .forward, predicate: predicate)
    }

    static func preorderBackward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .preorder, direction: .backward, predicate: predicate)
    }

    /// `.subtreePreorder` forward — first predicate match inside the
    /// starting forest's head subtree. Backs vim-style `f<kind>` typed descent.
    static func subtreePreorderForward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .subtreePreorder, direction: .forward, predicate: predicate)
    }

    /// `.subtreePreorder` backward — last predicate match inside the
    /// starting forest's head subtree (collected during the same forward
    /// iteration as `.forward`). Backs vim-style `F<kind>`.
    static func subtreePreorderBackward(_ predicate: Predicate = .any) -> ForestMotion {
        ForestMotion(axis: .subtreePreorder, direction: .backward, predicate: predicate)
    }
}

// MARK: - Resolver

public extension SyntaxForest where Policy == LiminalCSTPolicy {

    /// Apply one logical step of `motion`. A step walks the axis in the
    /// motion's direction until the predicate matches; for `.any`, that's
    /// exactly one primitive hop, but a filtering predicate may cross
    /// multiple raw hops in a single step (e.g. glue-skip on `h`).
    ///
    /// `extending: true` is only meaningful for ``ForestMotion/Axis/sibling``;
    /// it returns `nil` for every other axis (the dispatch site treats
    /// that as a no-op, matching the existing Coordinator's
    /// `extendCSTSelection` behavior for `.parent`/`.firstChild`).
    ///
    /// Returns `nil` when the axis exhausts without a match.
    func moved(by motion: ForestMotion, extending: Bool) -> SyntaxForest<Policy>? {
        Self.singleStep(motion: motion, extending: extending, current: self, start: self)
    }

    /// Repeat ``moved(by:extending:)`` `count` times (clamped to at least
    /// 1), saturating at the last successful position. Returns `nil`
    /// only when the *first* step returns nil (no progress at all).
    ///
    /// Each iteration re-snapshots the per-step start, so a count > 1
    /// with ``ForestMotion/Predicate/differentFrom(_:)`` rebases the
    /// comparison from the new head each time — backing vim's `Nw`/`Nb`.
    func moved(
        by motion: ForestMotion,
        extending: Bool,
        count: Int
    ) -> SyntaxForest<Policy>? {
        let iterations = max(1, count)
        var current = self
        var anyProgress = false
        for _ in 0..<iterations {
            guard let next = Self.singleStep(
                motion: motion,
                extending: extending,
                current: current,
                start: current
            ) else { break }
            current = next
            anyProgress = true
        }
        return anyProgress ? current : nil
    }

    // MARK: - Single-step dispatch

    private static func singleStep(
        motion: ForestMotion,
        extending: Bool,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        switch motion.axis {
        case .sibling:
            return siblingStep(
                direction: motion.direction,
                predicate: motion.predicate,
                extending: extending,
                current: current,
                start: start
            )
        case .ancestor:
            guard !extending else { return nil }
            return ancestorStep(
                predicate: motion.predicate,
                current: current,
                start: start
            )
        case .descendant:
            guard !extending else { return nil }
            return descendantStep(
                predicate: motion.predicate,
                current: current,
                start: start
            )
        case .preorder:
            guard !extending else { return nil }
            return preorderStep(
                direction: motion.direction,
                predicate: motion.predicate,
                current: current,
                start: start
            )
        case .subtreePreorder:
            guard !extending else { return nil }
            return subtreePreorderStep(
                direction: motion.direction,
                predicate: motion.predicate,
                current: current,
                start: start
            )
        }
    }

    // MARK: - Axis implementations

    private static func siblingStep(
        direction: ForestMotion.Direction,
        predicate: ForestMotion.Predicate,
        extending: Bool,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        var cursor = current
        while let next = siblingPrimitive(
            from: cursor,
            direction: direction,
            extending: extending
        ) {
            if evaluate(predicate, candidate: next, start: start) {
                return next
            }
            cursor = next
        }
        return nil
    }

    private static func siblingPrimitive(
        from forest: SyntaxForest<Policy>,
        direction: ForestMotion.Direction,
        extending: Bool
    ) -> SyntaxForest<Policy>? {
        switch (direction, extending) {
        case (.forward,  false): return forest.slidForward()
        case (.backward, false): return forest.slidBackward()
        case (.forward,  true):  return forest.extendedForward()
        case (.backward, true):  return forest.extendedBackward()
        }
    }

    private static func ancestorStep(
        predicate: ForestMotion.Predicate,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        var cursor = current
        while let parent = cursor.parentForest() {
            if evaluate(predicate, candidate: parent, start: start) {
                return parent
            }
            cursor = parent
        }
        return nil
    }

    private static func descendantStep(
        predicate: ForestMotion.Predicate,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        var cursor = current
        while let child = cursor.firstChildForest() {
            if evaluate(predicate, candidate: child, start: start) {
                return child
            }
            cursor = child
        }
        return nil
    }

    private static func preorderStep(
        direction: ForestMotion.Direction,
        predicate: ForestMotion.Predicate,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        var cursor = current
        while let next = preorderNext(from: cursor, direction: direction) {
            if evaluate(predicate, candidate: next, start: start) {
                return next
            }
            cursor = next
        }
        return nil
    }

    /// Bounded preorder forward through the start head's subtree.
    /// `.forward` returns the first predicate match; `.backward` returns
    /// the LAST predicate match (collected during the same forward walk).
    /// The bound is the byte position where the start head's pointed
    /// child's text range ends; any candidate at or past that byte has
    /// exited the subtree.
    private static func subtreePreorderStep(
        direction: ForestMotion.Direction,
        predicate: ForestMotion.Predicate,
        current: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy>? {
        let subtreeEnd = start.parent.withCursor { cursor in
            cursor.childTextRange(at: start.headChildIndex).end
        }
        var cursor = current
        var lastMatch: SyntaxForest<Policy>? = nil
        while let next = preorderNext(from: cursor, direction: .forward) {
            if next.byteRange.start >= subtreeEnd { break }
            if evaluate(predicate, candidate: next, start: start) {
                switch direction {
                case .forward:
                    return next
                case .backward:
                    lastMatch = next
                }
            }
            cursor = next
        }
        return lastMatch
    }

    /// One preorder hop in the requested direction. Returns the next
    /// (or previous, in backward) navigable forest in document source
    /// order, or `nil` past the document boundary.
    ///
    /// Forward (descend-first preorder):
    /// 1. Try to descend into the head's first navigable child.
    /// 2. Else try the next sibling under the current parent.
    /// 3. Else ascend, trying the next sibling at each ancestor level
    ///    until something works or the root exhausts.
    ///
    /// Backward (mirror-symmetric):
    /// - If a previous sibling exists, walk to its last navigable
    ///   descendant — that's the preorder predecessor.
    /// - Else the parent itself is the predecessor; return it.
    private static func preorderNext(
        from forest: SyntaxForest<Policy>,
        direction: ForestMotion.Direction
    ) -> SyntaxForest<Policy>? {
        switch direction {
        case .forward:
            if let descended = forest.firstChildForest() { return descended }
            if let sibling = forest.slidForward() { return sibling }
            var cursor: SyntaxForest<Policy>? = forest.parentForest()
            while let ancestor = cursor {
                if let sibling = ancestor.slidForward() { return sibling }
                cursor = ancestor.parentForest()
            }
            return nil
        case .backward:
            if let prevSibling = forest.slidBackward() {
                return lastNavigableDescendantInclusive(of: prevSibling)
            }
            return forest.parentForest()
        }
    }

    /// Walk first-child descents repeatedly, sliding to the last sibling
    /// at each level. Returns the deepest "last leaf" forest under
    /// `forest`, or `forest` itself when no navigable descendant exists.
    /// Used for backward preorder where we need to land on the previous
    /// sibling's deepest preorder predecessor.
    private static func lastNavigableDescendantInclusive(
        of forest: SyntaxForest<Policy>
    ) -> SyntaxForest<Policy> {
        var cursor = forest
        while let firstChild = cursor.firstChildForest() {
            var head = firstChild
            while let nextSibling = head.slidForward() {
                head = nextSibling
            }
            cursor = head
        }
        return cursor
    }

    // MARK: - Predicate evaluation

    private static func evaluate(
        _ predicate: ForestMotion.Predicate,
        candidate: SyntaxForest<Policy>,
        start: SyntaxForest<Policy>
    ) -> Bool {
        switch predicate {
        case .any:
            return true
        case .containingAny(let mask):
            return !headCategories(of: candidate).intersection(mask).isEmpty
        case .containingAll(let mask):
            return headCategories(of: candidate).isSuperset(of: mask)
        case .excluding(let mask):
            return headCategories(of: candidate).intersection(mask).isEmpty
        case .kindIn(let kinds):
            return kinds.contains(headKind(of: candidate))
        case .differentFrom(let mask):
            let startMasked = headCategories(of: start).intersection(mask)
            let candidateMasked = headCategories(of: candidate).intersection(mask)
            return startMasked != candidateMasked
        case .custom(let fn):
            return fn(candidate)
        }
    }

    private static func headKind(of forest: SyntaxForest<Policy>) -> LiminalKind {
        forest.parent.withCursor { cursor in
            cursor.green { green in green.child(at: forest.headChildIndex) }.kind
        }
    }

    private static func headCategories(of forest: SyntaxForest<Policy>) -> LiminalStructuralCategory {
        headKind(of: forest).categories
    }
}
