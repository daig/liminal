import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

@Suite("ForestMotion")
struct ForestMotionTests {

    // MARK: - Sibling axis

    @Test("siblingForward with .any matches Cambium's slidForward exactly")
    func siblingForwardAnyEquivalentToSlidForward() throws {
        let parsed = try LiminalParser().parse("First.\n\nSecond.\n\nThird.\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .siblingForward(), extending: false))
        let viaPrimitive = try #require(start.slidForward())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("siblingBackward with .any matches Cambium's slidBackward")
    func siblingBackwardAnyEquivalentToSlidBackward() throws {
        let source = "First.\n\nSecond.\n\nThird.\n"
        let parsed = try LiminalParser().parse(source)
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
        let parsed = try LiminalParser().parse("A.\n\nB.\n\nC.\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .siblingForward(), extending: true))
        let viaPrimitive = try #require(start.extendedForward())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("siblingForward with .containingAny(.heading) skips non-headings in one logical step")
    func siblingForwardSkipsToCategoryMatch() throws {
        let parsed = try LiminalParser().parse("A.\n\nB.\n\nC.\n\n# Title\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(
            start.moved(by: .siblingForward(.containingAny(.heading)), extending: false)
        )
        #expect(Self.headKind(result) == .atxHeading)
    }

    @Test("siblingForward returns nil when no candidate matches the predicate")
    func siblingForwardNoMatchReturnsNil() throws {
        let parsed = try LiminalParser().parse("A.\n\nB.\n\nC.\n")
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
        let parsed = try LiminalParser().parse("Hello.\n")
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
        let parsed = try LiminalParser().parse("Hello world.\n")
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
        let parsed = try LiminalParser().parse("Hello.\n")
        let tree = parsed.tree
        let raw = try #require(
            LiminalForest.containing(.zero, in: tree, affinity: .downstream)
        )
        #expect(raw.moved(by: .ancestor(), extending: true) == nil)
    }

    @Test("ancestor saturates at the outermost navigable position under root")
    func ancestorSaturatesAtRoot() throws {
        let parsed = try LiminalParser().parse("Hello.\n")
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
        let parsed = try LiminalParser().parse("Hello.\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let viaKernel = try #require(start.moved(by: .descendant(), extending: false))
        let viaPrimitive = try #require(start.firstChildForest())
        #expect(viaKernel == viaPrimitive)
    }

    @Test("descendant into a fenced code block returns nil (opaque)")
    func descendantIntoOpaqueReturnsNil() throws {
        let parsed = try LiminalParser().parse("```\nlet x = 1\n```\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(Self.headKind(start) == .fencedCodeBlock)
        let result = start.moved(by: .descendant(), extending: false)
        #expect(result == nil)
    }

    @Test("descendant with extending: true returns nil")
    func descendantExtendingReturnsNil() throws {
        let parsed = try LiminalParser().parse("Hello.\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        #expect(start.moved(by: .descendant(), extending: true) == nil)
    }

    // MARK: - Preorder axis

    @Test("preorder forward descends into the current head before sliding sideways")
    func preorderForwardDescendsBeforeNextSibling() throws {
        let parsed = try LiminalParser().parse("Foo.\n\nBar.\n")
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
        let parsed = try LiminalParser().parse(source)
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
        let parsed = try LiminalParser().parse("Intro paragraph.\n\n# Section\n\nBody.\n")
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
        let parsed = try LiminalParser().parse(source)
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
        let parsed = try LiminalParser().parse(source)
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
        let parsed = try LiminalParser().parse("Just text.\n")
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
        let parsed = try LiminalParser().parse("Foo.\n\n# Heading\n")
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
        let parsed = try LiminalParser().parse("Foo.\n\n# H\n\nBar.\n")
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
        let parsed = try LiminalParser().parse("Foo.\n\n# Heading\n\nBar.\n")
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
        let parsed = try LiminalParser().parse("Para1.\n\n# H1\n\n# H2\n")
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
        let parsed = try LiminalParser().parse("# Heading\n\nBody paragraph here.\n")
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
        let parsed = try LiminalParser().parse("A.\n\nB.\n\nC.\n")
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
        let parsed = try LiminalParser().parse("A.\n\nB.\n")
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
        let parsed = try LiminalParser().parse("A.\n\nB.\n\nC.\n")
        let tree = parsed.tree
        let start = try #require(LiminalForest.cstVisualEntry(at: .zero, in: tree))
        let result = try #require(start.moved(by: .siblingForward(), extending: true))
        #expect(result.anchorChildIndex == start.anchorChildIndex)
        #expect(result.headChildIndex != start.headChildIndex)
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
