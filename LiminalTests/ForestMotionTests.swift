import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

@Suite("ForestMotion")
struct ForestMotionTests {

    // MARK: - Sibling axis

    @Test("siblingForward with .any matches Cambium's slidForward exactly")
    func siblingForwardAnyEquivalentToSlidForward() throws {
        let parsed = try LiminalParser().parse(CambiumSource("First.\n\nSecond.\n\nThird.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .siblingForward(), extending: false))
        let viaPrimitive = try #require(start.slidForward())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("siblingBackward with .any matches Cambium's slidBackward")
    func siblingBackwardAnyEquivalentToSlidBackward() throws {
        let source = "First.\n\nSecond.\n\nThird.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let secondOffset = Self.byteOffset(of: "Second", in: source)
        let start = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(UInt32(secondOffset)), in: tree)
        )
        let viaKernel = try #require(start.moved(by: .siblingBackward(), extending: false))
        let viaPrimitive = try #require(start.slidBackward())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("siblingForward with extending: true matches extendedForward")
    func siblingForwardExtendingEquivalentToExtendedForward() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n\nC.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .siblingForward(), extending: true))
        let viaPrimitive = try #require(start.extendedForward())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("siblingForward with .containingAny(.heading) skips non-headings in one logical step")
    func siblingForwardSkipsToCategoryMatch() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n\nC.\n\n# Title\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .siblingForward(.containingAny(.heading)), extending: false)
        )
        #expect(Self.headKind(result) == .atxHeading)
    }

    @Test("siblingForward returns nil when no candidate matches the predicate")
    func siblingForwardNoMatchReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n\nC.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = start.moved(
            by: .siblingForward(.containingAny(.heading)),
            extending: false
        )
        #expect(result == nil)
    }

    // MARK: - Ancestor axis

    @Test("ancestor with .any returns the immediate parentForest")
    func ancestorAnyReachesImmediateParent() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        // Raw position: inlineText under inlineContent (deepest navigable).
        let raw = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        let viaKernel = try #require(raw.moved(by: .ancestor(), extending: false))
        let viaPrimitive = try #require(raw.parentForest())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("ancestor with .excluding(.glueWrapper) skips glue ancestors in one logical step")
    func ancestorExcludingGlueReachesParagraphInOneStep() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello world.\n"))
        let tree = parsed.tree
        let raw = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        #expect(Self.headKind(raw) == .inlineText)
        let result = try #require(
            raw.moved(by: .ancestor(.excluding(.glueWrapper)), extending: false)
        )
        // Canonical `h` semantic: one step skips past .inlineContent
        // (which is .glueWrapper) and lands on .paragraph.
        #expect(Self.headKind(result) == .paragraph)
    }

    @Test("ancestor with extending: true returns nil")
    func ancestorExtendingReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        let raw = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        #expect(raw.moved(by: .ancestor(), extending: true) == nil)
    }

    @Test("ancestor saturates at the outermost navigable position under root")
    func ancestorSaturatesAtRoot() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        let raw = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        let result = try #require(
            raw.moved(by: .ancestor(), extending: false, count: 100)
        )
        // The outermost navigable forest has root as its parent.
        let parentKind = result.parent.withCursor { $0.kind }
        #expect(
            parentKind == .root,
            "Saturated forest's parent should be root; saw \(parentKind)"
        )
    }

    // MARK: - Descendant axis

    @Test("descendant with .any matches firstChildForest")
    func descendantAnyEquivalentToFirstChildForest() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .descendant(), extending: false))
        let viaPrimitive = try #require(start.firstChildForest())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("descendant into a fenced code block returns nil (opaque)")
    func descendantIntoOpaqueReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("```\nlet x = 1\n```\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .fencedCodeBlock)
        let result = start.moved(by: .descendant(), extending: false)
        #expect(result == nil)
    }

    @Test("descendant with extending: true returns nil")
    func descendantExtendingReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(start.moved(by: .descendant(), extending: true) == nil)
    }

    // MARK: - Preorder axis

    @Test("preorder forward descends into the current head before sliding sideways")
    func preorderForwardDescendsBeforeNextSibling() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Foo.\n\nBar.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .paragraph)
        let result = try #require(start.moved(by: .preorderForward(), extending: false))
        // Should descend INTO paragraph (head = .inlineContent), NOT slide
        // to the next root sibling.
        #expect(Self.headKind(result) == .inlineContent)
    }

    @Test("preorder forward eventually crosses sibling boundaries")
    func preorderForwardAcrossSiblings() throws {
        let source = "Foo.\n\nBar.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        // Walk 10 preorder hops; we should certainly cross into Bar's subtree.
        var current = start
        for _ in 0..<10 {
            guard let next = current.moved(by: .preorderForward(), extending: false) else { break }
            current = next
        }
        let barOffset = Self.byteOffset(of: "Bar", in: source)
        #expect(
            Int(current.byteRange.start.rawValue) >= barOffset,
            "Expected to cross into Bar; ended at \(Self.headKind(current)) at byte \(current.byteRange.start.rawValue)"
        )
    }

    @Test("preorder forward with heading predicate finds the next heading")
    func preorderForwardWithHeadingPredicate() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Intro paragraph.\n\n# Section\n\nBody.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .paragraph)
        let result = try #require(
            start.moved(by: .preorderForward(.containingAny(.heading)), extending: false)
        )
        #expect(Self.headKind(result) == .atxHeading)
    }

    @Test("preorder backward with an inline predicate descends into previous content")
    func preorderBackwardDescendsLastDescendantFirst() throws {
        let source = "- First\n- Second\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let secondOffset = Self.byteOffset(of: "Second", in: source)
        let start = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(UInt32(secondOffset)), in: tree)
        )
        // Walk backward via preorder with an inlineText predicate. Should
        // ascend out of listItem1's paragraph, slidBackward to listItem0,
        // then descend through its first-child chain to "First"'s inlineText.
        let result = try #require(
            start.moved(by: .preorderBackward(.kindIn([.inlineText])), extending: false)
        )
        #expect(Self.headKind(result) == .inlineText)
        // Sanity-check we landed on the "First" inlineText, not "Second".
        let bytes = source.utf8
        let firstOffset = Self.byteOffset(of: "First", in: source)
        let resultOffset = Int(result.byteRange.start.rawValue)
        #expect(
            resultOffset < firstOffset + 5 && resultOffset < secondOffset,
            "Expected to land near 'First' (~byte \(firstOffset)); saw \(resultOffset)"
        )
        _ = bytes
    }

    @Test("preorder backward with heading predicate finds the previous heading")
    func preorderBackwardWithHeadingPredicate() throws {
        let source = "# H1\n\nBody paragraph.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let bodyOffset = Self.byteOffset(of: "Body", in: source)
        let start = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(UInt32(bodyOffset)), in: tree)
        )
        let result = try #require(
            start.moved(by: .preorderBackward(.containingAny(.heading)), extending: false)
        )
        #expect(Self.headKind(result) == .atxHeading)
    }

    @Test("preorder with no matching node returns nil")
    func preorderNoMatchReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Just text.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = start.moved(
            by: .preorderForward(.containingAny(.heading)),
            extending: false
        )
        #expect(result == nil)
    }

    // MARK: - Predicate variants

    @Test("containingAll requires every category in the mask")
    func containingAllRequiresAllCategories() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Foo.\n\n# Heading\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        // No sibling has both .heading AND .listy.
        let none = start.moved(
            by: .siblingForward(.containingAll([.heading, .listy])),
            extending: false
        )
        #expect(none == nil)
        // The heading is .blockItem + .heading; containingAll([.heading]) matches.
        let some = try #require(
            start.moved(
                by: .siblingForward(.containingAll([.heading])),
                extending: false
            )
        )
        #expect(Self.headKind(some) == .atxHeading)
    }

    @Test("kindIn matches exact LiminalKind set")
    func kindInExactMatch() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Foo.\n\n# H\n\nBar.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(
                by: .siblingForward(.kindIn([.atxHeading])),
                extending: false
            )
        )
        #expect(Self.headKind(result) == .atxHeading)
    }

    @Test("excluding matches a candidate whose categories don't overlap the mask")
    func excludingMatchesNonExcluded() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Foo.\n\n# Heading\n\nBar.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(
                by: .siblingForward(.excluding(.heading)),
                extending: false
            )
        )
        #expect(!Self.headKind(result).categories.contains(.heading))
    }

    @Test("differentFrom re-snapshots the start per logical step")
    func differentFromRebasesPerStep() throws {
        // Root children (interleaved with blankLines): paragraph "Para1.",
        // atxHeading "H1", atxHeading "H2". Their categories masked by
        // .heading:  paragraph -> [],  blankLine -> [],  atxHeading -> [.heading].
        //
        // Per-step (correct): count=2 from paragraph lands on the blankLine
        // immediately after H1 (re-snapshot at H1 sees blankLine as
        // "different from .heading").
        // Snapshot-once (the bug we're guarding): count=2 would skip the
        // blankLine after H1 (same as paragraph's []) and land on H2.
        let parsed = try LiminalParser().parse(CambiumSource("Para1.\n\n# H1\n\n# H2\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(
                by: .siblingForward(.differentFrom(.heading)),
                extending: false,
                count: 2
            )
        )
        #expect(
            Self.headKind(result) == .blankLine,
            "Per-step rebasing should land on the blankLine after H1; saw \(Self.headKind(result))"
        )
    }

    @Test("custom predicate is invoked for each candidate")
    func customPredicateIsConsulted() throws {
        let parsed = try LiminalParser().parse(CambiumSource("# Heading\n\nBody paragraph here.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let predicate: ForestMotion.Predicate = .custom { forest in
            forest.parent.withCursor { c in
                c.green { $0.child(at: forest.headChildIndex) }.kind
            } == .paragraph
        }
        let result = try #require(
            start.moved(by: .siblingForward(predicate), extending: false)
        )
        #expect(Self.headKind(result) == .paragraph)
    }

    // MARK: - Counts and saturation

    @Test("count > available steps saturates at the last successful position")
    func repeatStepSaturatesAtLastValidPosition() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n\nC.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .siblingForward(), extending: false, count: 99)
        )
        // Saturated at the last sibling: one more forward step yields nil.
        #expect(result.moved(by: .siblingForward(), extending: false) == nil)
    }

    @Test("count > 0 from a position with no progress returns nil")
    func zeroProgressReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        // Walk to the last sibling.
        var cursor = start
        while let next = cursor.moved(by: .siblingForward(), extending: false) {
            cursor = next
        }
        // From the last sibling, forward 5 should yield nil (no progress).
        let result = cursor.moved(by: .siblingForward(), extending: false, count: 5)
        #expect(result == nil)
    }

    @Test("siblingForward extending: true preserves the anchor")
    func extendingPreservesAnchor() throws {
        let parsed = try LiminalParser().parse(CambiumSource("A.\n\nB.\n\nC.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(start.moved(by: .siblingForward(), extending: true))
        #expect(result.anchorChildIndex == start.anchorChildIndex)
        #expect(result.headChildIndex != start.headChildIndex)
    }

    // MARK: - Subtree-bounded preorder

    @Test("subtreePreorder forward finds the first predicate match in the subtree")
    func subtreePreorderForwardFindsFirstMatchInSubtree() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello **bold** and *italic* world.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .subtreePreorderForward(.containingAny(.emphasis)), extending: false)
        )
        // `**bold**` parses to .strong, the first emphasis-family kind.
        #expect(
            Self.headKind(result) == .strong,
            "expected first .emphasis match to be the .strong (**bold**); saw \(Self.headKind(result))"
        )
    }

    @Test("subtreePreorder forward walks past non-matching nodes to find the first match")
    func subtreePreorderForwardSkipsToFirstMatch() throws {
        // Subtree contains inlineContent + leading inlineText + wikilink + trailing inlineText.
        // .containingAny(.reference) skips inlineContent and inlineText and lands on wikilink.
        let parsed = try LiminalParser().parse(CambiumSource("Some text and [[wiki]] more.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .subtreePreorderForward(.containingAny(.reference)), extending: false)
        )
        #expect(Self.headKind(result) == .wikilink)
    }

    @Test("subtreePreorder forward respects the subtree boundary and does not leak into siblings")
    func subtreePreorderForwardStopsAtSubtreeBoundary() throws {
        let parsed = try LiminalParser().parse(CambiumSource("First paragraph.\n\n# Heading\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .paragraph)
        // No heading inside this paragraph; the search must NOT cross into
        // the next root sibling (the actual heading).
        let result = start.moved(
            by: .subtreePreorderForward(.containingAny(.heading)),
            extending: false
        )
        #expect(result == nil, "subtree-bounded search must not leak past the starting head's text range")
    }

    @Test("subtreePreorder backward returns the LAST predicate match in the subtree")
    func subtreePreorderBackwardFindsLastMatchInSubtree() throws {
        let source = "Hello **first** and **second** end.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .subtreePreorderBackward(.containingAny(.emphasis)), extending: false)
        )
        #expect(Self.headKind(result) == .strong)
        let secondStrongStart = Self.byteOffset(of: "**second**", in: source)
        #expect(
            Int(result.byteRange.start.rawValue) == secondStrongStart,
            "backward should land on the SECOND **strong** at byte \(secondStrongStart); saw \(result.byteRange.start.rawValue)"
        )
    }

    @Test("subtreePreorder on a leaf forest returns nil for both directions")
    func subtreePreorderOnEmptySubtreeReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello.\n"))
        let tree = parsed.tree
        // The deepest navigable position — an inlineText leaf with no children.
        let leaf = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        #expect(Self.headKind(leaf) == .inlineText)
        #expect(leaf.moved(by: .subtreePreorderForward(), extending: false) == nil)
        #expect(leaf.moved(by: .subtreePreorderBackward(), extending: false) == nil)
    }

    // MARK: - Heading-level predicate (slice B)

    @Test(".headingLevel(.sameAsStart) lands on the next same-level heading")
    func headingLevelSameAsStart() throws {
        // H1a (level 1) → ## H2a (level 2) → # H1b (level 1).
        // Forward same-level from H1a should skip H2a and land on H1b.
        let source = "# H1a\n\n## H2a\n\n# H1b\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .atxHeading)

        let motion = ForestMotion(
            axis: .preorder,
            direction: .forward,
            predicate: .headingLevel(.sameAsStart)
        )
        let result = try #require(start.moved(by: motion, extending: false))
        let h1bOffset = Self.byteOffset(of: "# H1b", in: source)
        #expect(Int(result.byteRange.start.rawValue) == h1bOffset)
    }

    @Test(".headingLevel(.deeperThanStart) finds the next strictly-deeper heading")
    func headingLevelDeeperThanStart() throws {
        // # H1 → # H1b (same level — skip) → ## H2 (deeper — land).
        let source = "# H1\n\n# H1b\n\n## H2\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))

        let motion = ForestMotion(
            axis: .preorder,
            direction: .forward,
            predicate: .headingLevel(.deeperThanStart)
        )
        let result = try #require(start.moved(by: motion, extending: false))
        let h2Offset = Self.byteOffset(of: "## H2", in: source)
        #expect(Int(result.byteRange.start.rawValue) == h2Offset)
    }

    @Test(".headingLevel falls back to enclosing heading when start isn't a heading")
    func headingLevelUsesEnclosingForNonHeadingStart() throws {
        // From inside the body paragraph (enclosing heading is H1, level 1),
        // sameAsStart forward should land on H2 (also level 1).
        let source = "# H1\n\nBody paragraph.\n\n# H2\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let bodyOffset = Self.byteOffset(of: "Body", in: source)
        let start = try #require(
            LiminalForest.cstVisualEntry(at: TextSize(UInt32(bodyOffset)), in: tree)
        )
        #expect(Self.headKind(start) == .paragraph)

        let motion = ForestMotion(
            axis: .preorder,
            direction: .forward,
            predicate: .headingLevel(.sameAsStart)
        )
        let result = try #require(start.moved(by: motion, extending: false))
        let h2Offset = Self.byteOffset(of: "# H2", in: source)
        #expect(Int(result.byteRange.start.rawValue) == h2Offset)
    }

    @Test(".headingLevel returns nil when no enclosing heading exists")
    func headingLevelNilWithoutEnclosingHeading() throws {
        let source = "Just plain text.\n\nMore text.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))

        let motion = ForestMotion(
            axis: .preorder,
            direction: .forward,
            predicate: .headingLevel(.sameAsStart)
        )
        #expect(start.moved(by: motion, extending: false) == nil)
    }

    @Test(".headingLevel(.shallowerThanStart) finds a strictly-shallower heading")
    func headingLevelShallowerThanStart() throws {
        // ## H2 → ### H3 (skip, deeper) → # H1 (shallower — land).
        let source = "## H2\n\n### H3\n\n# H1\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))

        let motion = ForestMotion(
            axis: .preorder,
            direction: .forward,
            predicate: .headingLevel(.shallowerThanStart)
        )
        let result = try #require(start.moved(by: motion, extending: false))
        let h1Offset = Self.byteOffset(of: "# H1", in: source)
        #expect(Int(result.byteRange.start.rawValue) == h1Offset)
    }

    // MARK: - lastChildForest (single-level primitive)

    @Test("lastChildForest lands on the LAST navigable child (one level)")
    func lastChildForestLandsOnLastSibling() throws {
        let source = "- a\n- b\n- c\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        // cstVisualEntry lands at the listItem level (`list > listItem`);
        // ascend once to put the head on the list so `lastChildForest`
        // descends into the list to find its last item.
        let entry = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(entry) == .listItem)
        let listForest = try #require(entry.parentForest())
        #expect(Self.headKind(listForest) == .list)

        let last = try #require(listForest.lastChildForest())
        #expect(Self.headKind(last) == .listItem)
        let cOffset = Self.byteOffset(of: "- c", in: source)
        #expect(Int(last.byteRange.start.rawValue) == cOffset,
                "expected last list item to start at \(cOffset); saw \(last.byteRange.start.rawValue)")
    }

    @Test("lastChildForest returns nil for a leaf head")
    func lastChildForestNilForLeaf() throws {
        let source = "Hello.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        // Drill down to the inlineText leaf.
        let leaf = try #require(LiminalForest.containing(.zero, in: tree, affinity: .downstream))
        #expect(Self.headKind(leaf) == .inlineText)
        #expect(leaf.lastChildForest() == nil)
    }

    // MARK: - descendant axis with .backward direction
    //
    // Symmetric with the forward case (firstChildForest chain). Loops
    // the single-level lastChildForest primitive at each level, applying
    // the predicate. The `:CSTLastChild` command dispatches this with
    // `.excluding(.glueWrapper)`, so it peels through the same
    // structural-glue wrappers (inlineContent, value, fields, ...) that
    // `:CSTFirstChild` does — but lands on the LAST descendant chain.

    @Test("descendantBackward(.excluding(.glueWrapper)) peels through inlineContent")
    func descendantBackwardPeelsThroughInlineContent() throws {
        // Paragraph wraps a single inlineContent (a glue wrapper) which
        // wraps inline runs. `:CSTLastChild` semantics: stop at the
        // first non-glue descendant via the last-child chain.
        let source = "This is **bold** and *italic* text.\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let entry = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(entry) == .paragraph)

        let last = try #require(
            entry.moved(
                by: .descendantBackward(.excluding(.glueWrapper)),
                extending: false
            )
        )
        // Land on the LAST inlineText run, not the inlineContent wrapper.
        #expect(Self.headKind(last) == .inlineText)
        let trailingOffset = Self.byteOffset(of: " text.", in: source)
        #expect(
            Int(last.byteRange.start.rawValue) == trailingOffset,
            "expected last inline run starting at \(trailingOffset); saw \(last.byteRange.start.rawValue)"
        )
    }

    @Test("descendant forward + backward are symmetric on glue-wrapped inline")
    func descendantForwardBackwardSymmetric() throws {
        let source = "alpha **beta** gamma\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let tree = parsed.tree
        let entry = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(entry) == .paragraph)

        let first = try #require(
            entry.moved(by: .descendant(.excluding(.glueWrapper)), extending: false)
        )
        let last = try #require(
            entry.moved(by: .descendantBackward(.excluding(.glueWrapper)), extending: false)
        )
        #expect(Self.headKind(first) == .inlineText)
        #expect(Self.headKind(last) == .inlineText)
        let alphaOffset = Self.byteOffset(of: "alpha", in: source)
        let gammaOffset = Self.byteOffset(of: " gamma", in: source)
        #expect(Int(first.byteRange.start.rawValue) == alphaOffset)
        #expect(Int(last.byteRange.start.rawValue) == gammaOffset)
    }

    @Test("subtreePreorder with extending: true returns nil for both directions")
    func subtreePreorderExtendingReturnsNil() throws {
        let parsed = try LiminalParser().parse(CambiumSource("Hello **bold** world.\n"))
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(
            start.moved(
                by: .subtreePreorderForward(.containingAny(.emphasis)),
                extending: true
            ) == nil
        )
        #expect(
            start.moved(
                by: .subtreePreorderBackward(.containingAny(.emphasis)),
                extending: true
            ) == nil
        )
    }

    // MARK: - Helpers

    private static func headKind(_ forest: LiminalForest) -> LiminalKind {
        forest.parent.withCursor { cursor in
            cursor.green { green in green.child(at: forest.headChildIndex) }.kind
        }
    }

    private static func byteOffset(of needle: String, in source: String) -> Int {
        guard let range = source.range(of: needle) else {
            Issue.record("Missing substring \(needle)")
            return 0
        }
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
    }
}
