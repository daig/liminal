import AppKit
import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

/// End-to-end checks of visual CST mode: a real `LiminalSourceDocument`
/// drives a wired-up `Coordinator` + `VimTextView` and we verify
/// observable effects on `textView.selectedRange` after CST entry,
/// navigation, and operator dispatch.
///
/// Tests stop short of running through actual `keyDown` events; they
/// call delegate methods directly to keep the harness small. The
/// controller-isolation suite (`VimVisualCSTModeTests`) covers the
/// key → command path.
@Suite("Visual CST integration")
@MainActor
struct LiminalCSTVisualIntegrationTests {

    // MARK: - Entry

    @Test("entering visualCST in a paragraph selects the whole paragraph's bytes")
    func entryAtParagraphSelectsParagraph() throws {
        let fixture = try makeFixture("First paragraph.\n\nSecond paragraph.\n")

        // Cursor at offset 0 (start of first paragraph).
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()

        // The structural selection lives in `cstSelectionRanges` (the
        // custom overlay), not `selectedRange` — the latter only holds
        // a parked caret in .visualCST.
        let sel = try cstSelectionRange(fixture.textView)
        #expect(sel.length > 0, "entry should populate a CST selection")
        // The selection's start should be at byte 0 (paragraph start).
        #expect(sel.location == 0)
        // And it should cover at least "First paragraph." (16 utf16 chars).
        #expect(sel.length >= 16)
        // The system caret is parked at the overlay's start.
        #expect(fixture.textView.selectedRange().location == sel.location)
        #expect(fixture.textView.selectedRange().length == 0)
    }

    @Test("entering visualCST at a list marker after a blank line selects the list")
    func entryAtListMarkerAfterBlankLineSelectsList() throws {
        let source = "First paragraph.\n\n- item\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- item", in: source))
        fixture.coordinator.enterCSTVisualMode()

        let sel = try cstSelectionRange(fixture.textView)
        let listOffset = try utf16Offset(of: "- item", in: source)
        #expect(sel.location == listOffset)
        #expect(sel.length >= "- item\n".utf16.count)
    }

    @Test("entering visualCST at first list item content character selects paragraph content")
    func entryAtFirstListItemContentCharacterSelectsParagraph() throws {
        let source = "- foo\n  - bar\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "foo", in: source))
        fixture.coordinator.enterCSTVisualMode()

        #expect(fixture.textView.cstSelectionRanges == [
            NSRange(location: 2, length: 3)
        ])
    }

    @Test("entering visualCST in an empty document forces back to normal mode")
    func entryInEmptyDocumentBailsToNormal() throws {
        let fixture = try makeFixture("")

        // Pre-condition: simulate the controller already flipping to
        // .visualCST (as VimController.dispatch does before calling the
        // delegate). The delegate's bail path should undo that.
        fixture.controller.forceNormalMode()
        // Now manually flip the mode the way `enterCSTVisualMode` is
        // entered in production (mode-first, then delegate).
        // We can't call setMode publicly; emulate by handling the chord.
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        // Coordinator's enterCSTVisualMode runs and should bail because
        // the empty document has no navigable forest. Force-normalMode
        // is the contract.
        #expect(fixture.controller.mode == .normal)
    }

    // MARK: - Slide / Extend / Swap / Ascend / Descend

    @Test("slidForward moves the selection to the next sibling block")
    func slidForwardCrossesParagraphs() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n\nThird.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initialSel = try cstSelectionRange(fixture.textView)

        fixture.coordinator.cstNavigate(.nextSibling, count: 1)
        let afterSel = try cstSelectionRange(fixture.textView)

        // After moving to the next sibling, the selection should start
        // strictly after the original selection.
        #expect(afterSel.location > initialSel.location,
                "next sibling should be later in source")
    }

    @Test("extendedForward grows the selection while keeping the anchor")
    func extendedForwardGrowsSelection() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n\nThird.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initial = try cstSelectionRange(fixture.textView)

        fixture.coordinator.extendCSTSelection(.nextSibling, count: 1)
        let extended = try cstSelectionRange(fixture.textView)

        #expect(extended.location == initial.location, "anchor end unchanged")
        #expect(extended.length > initial.length, "selection grew")
    }

    @Test("parent ascend collapses the selection to a singleton at the parent's slot")
    func parentAscendCollapsesSelection() throws {
        let fixture = try makeFixture("# Heading\n\nA paragraph.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initial = try cstSelectionRange(fixture.textView)

        fixture.coordinator.cstNavigate(.parent, count: 1)
        let parentSel = try cstSelectionRange(fixture.textView)

        // Parent of the heading at root[0] is root. Ascending makes the
        // selection a singleton at the heading's slot in root — same byte
        // range as the heading.
        #expect(parentSel.location <= initial.location,
                "ascend shouldn't move the selection start later")
    }

    @Test("firstChild descend into an opaque fenced code block is a no-op")
    func firstChildOnOpaqueBlockIsNoOp() throws {
        let fixture = try makeFixture("```swift\nlet x = 1\n```\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let before = fixture.textView.cstSelectionRanges

        fixture.coordinator.cstNavigate(.firstChild, count: 1)
        let after = fixture.textView.cstSelectionRanges

        #expect(after == before, "opaque-block descend should not move selection")
    }

    // MARK: - Glue-skip semantics (step 3a)

    @Test("firstChild glue-skips inlineContent and lands on the first inline child")
    func firstChildSkipsInlineContentGlueInOneStep() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let entry = try #require(fixture.coordinator.cstForest)
        #expect(headKind(entry) == .paragraph, "entry should be the paragraph")

        fixture.coordinator.cstNavigate(.firstChild, count: 1)
        let descended = try #require(fixture.coordinator.cstForest)
        #expect(
            headKind(descended) == .inlineText,
            "firstChild should glue-skip inlineContent and land on inlineText; saw \(headKind(descended))"
        )
    }

    @Test("parent glue-skips inlineContent and lands on the enclosing paragraph in one step")
    func parentSkipsInlineContentGlueInOneStep() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        // Descend to inlineText so we have a glue ancestor (inlineContent) to skip.
        fixture.coordinator.cstNavigate(.firstChild, count: 1)
        #expect(headKind(try #require(fixture.coordinator.cstForest)) == .inlineText)

        fixture.coordinator.cstNavigate(.parent, count: 1)
        let ascended = try #require(fixture.coordinator.cstForest)
        #expect(
            headKind(ascended) == .paragraph,
            "parent should glue-skip inlineContent and land on paragraph; saw \(headKind(ascended))"
        )
    }

    @Test("h after l restores the entry kind — one logical hop each way through glue")
    func parentReversesFirstChildInOneStep() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let entryKind = headKind(try #require(fixture.coordinator.cstForest))

        fixture.coordinator.cstNavigate(.firstChild, count: 1)
        fixture.coordinator.cstNavigate(.parent, count: 1)
        let restoredKind = headKind(try #require(fixture.coordinator.cstForest))

        #expect(
            restoredKind == entryKind,
            "h after l should compress back to the entry kind; entry=\(entryKind), restored=\(restoredKind)"
        )
    }

    @Test("extendCSTSelection on .parent is a no-op (kernel returns nil, forest preserved)")
    func extendOnParentIsNoOp() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let before = try #require(fixture.coordinator.cstForest)

        fixture.coordinator.extendCSTSelection(.parent, count: 1)
        let after = try #require(fixture.coordinator.cstForest)
        #expect(after == before, "extend on .parent should leave the forest unchanged")

        fixture.coordinator.extendCSTSelection(.firstChild, count: 1)
        let after2 = try #require(fixture.coordinator.cstForest)
        #expect(after2 == before, "extend on .firstChild should leave the forest unchanged")
    }

    // MARK: - Typed descent (f / F)

    @Test("cstFindKind forward lands on the first matching kind in subtree")
    func findKindForwardLandsOnFirstWikilinkInSubtree() throws {
        let source = "Hello [[first]] and [[second]] end.\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()

        fixture.coordinator.cstFindKind(direction: .forward, kind: .wikilink, count: 1)

        let result = try #require(fixture.coordinator.cstForest)
        #expect(headKind(result) == .wikilink)
        let firstOffset = try utf16Offset(of: "[[first", in: source)
        #expect(
            Int(result.byteRange.start.rawValue) == firstOffset,
            "forward should land on the FIRST wikilink at byte \(firstOffset); saw \(result.byteRange.start.rawValue)"
        )
    }

    @Test("cstFindKind backward lands on the last matching kind in subtree")
    func findKindBackwardLandsOnLastWikilinkInSubtree() throws {
        let source = "Hello [[first]] and [[second]] end.\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()

        fixture.coordinator.cstFindKind(direction: .backward, kind: .wikilink, count: 1)

        let result = try #require(fixture.coordinator.cstForest)
        #expect(headKind(result) == .wikilink)
        let secondOffset = try utf16Offset(of: "[[second", in: source)
        #expect(
            Int(result.byteRange.start.rawValue) == secondOffset,
            "backward should land on the LAST wikilink at byte \(secondOffset); saw \(result.byteRange.start.rawValue)"
        )
    }

    @Test("cstFindKind with no match in subtree leaves the forest unchanged")
    func findKindForwardWithNoMatchIsNoOp() throws {
        let fixture = try makeFixture("Just plain text.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let before = try #require(fixture.coordinator.cstForest)

        fixture.coordinator.cstFindKind(direction: .forward, kind: .heading, count: 1)

        let after = try #require(fixture.coordinator.cstForest)
        #expect(after == before, "no heading in subtree → forest unchanged")
    }

    @Test(":CSTLastChild descends to the last navigable child of the head")
    func lastChildDescendsToLast() throws {
        let source = "- a\n- b\n- c\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        // cstVisualEntry lands at the listItem level; press `h` to
        // ascend to the list so CSTLastChild descends INTO the list
        // (not into the first list item).
        #expect(headKind(try #require(fixture.coordinator.cstForest)) == .listItem)
        _ = fixture.controller.handle(.char("h"))
        #expect(headKind(try #require(fixture.coordinator.cstForest)) == .list)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTLastChild" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        let last = try #require(fixture.coordinator.cstForest)
        #expect(headKind(last) == .listItem)
        let cOffset = try utf16Offset(of: "- c", in: source)
        #expect(
            Int(last.byteRange.start.rawValue) == cOffset,
            "expected last item starting at \(cOffset); saw \(last.byteRange.start.rawValue)"
        )
    }

    @Test(":CSTLastChild on mixed-inline paragraph lands on last inlineText (regression)")
    func lastChildPeelsThroughInlineContentGlue() throws {
        // Regression for the user-reported asymmetry: CSTFirstChild from
        // a paragraph peels through the inlineContent glue wrapper and
        // lands on the FIRST inlineText run ("This is "); CSTLastChild
        // was landing on the inlineContent wrapper itself instead of the
        // LAST inlineText run (" text.").
        //
        // Fix routes both commands through the kernel via descendant axis
        // with .excluding(.glueWrapper): forward + backward symmetric.
        let source = "This is **bold** and *italic* text.\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        #expect(headKind(try #require(fixture.coordinator.cstForest)) == .paragraph)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTLastChild" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        let last = try #require(fixture.coordinator.cstForest)
        #expect(headKind(last) == .inlineText,
                "expected to land on an inlineText leaf, not the inlineContent wrapper")
        let trailingOffset = try utf16Offset(of: " text.", in: source)
        #expect(
            Int(last.byteRange.start.rawValue) == trailingOffset,
            "expected last text run starting at \(trailingOffset); saw \(last.byteRange.start.rawValue)"
        )
    }

    @Test(":CSTDocumentStart from mid-document jumps to the first block")
    func documentStartFromMidDocumentLandsOnFirstBlock() throws {
        // Three paragraphs. Place the cursor inside the second one and
        // confirm :CSTDocumentStart jumps to the first paragraph at the
        // same granularity gC at byte 0 would produce.
        let source = "First paragraph here.\n\nSecond paragraph.\n\nLast paragraph here.\n"
        let fixture = try makeFixture(source)
        let midSecond = try utf16Offset(of: "Second", in: source) + 3
        fixture.placeCursor(atUTF16: midSecond)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTDocumentStart" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        let first = try #require(fixture.coordinator.cstForest)
        #expect(headKind(first) == .paragraph,
                "document start should land on the first block (paragraph)")
        #expect(
            Int(first.byteRange.start.rawValue) == 0,
            "expected first paragraph starting at byte 0; saw \(first.byteRange.start.rawValue)"
        )
    }

    @Test(":CSTDocumentEnd from start of document jumps to the last block")
    func documentEndFromStartLandsOnLastBlock() throws {
        // Confirm :CSTDocumentEnd from byte 0 lands on the last paragraph
        // at the same granularity gC at the document's last content byte
        // would produce, skipping trailing newlines.
        let source = "First paragraph.\n\nMiddle.\n\nLast paragraph here.\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTDocumentEnd" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        let last = try #require(fixture.coordinator.cstForest)
        #expect(headKind(last) == .paragraph,
                "document end should land on the last block (paragraph)")
        let lastParagraphOffset = try utf16Offset(of: "Last paragraph here.", in: source)
        #expect(
            Int(last.byteRange.start.rawValue) == lastParagraphOffset,
            "expected last paragraph at \(lastParagraphOffset); saw \(last.byteRange.start.rawValue)"
        )
    }

    @Test(":CSTNextBlock hops to the next block-level sibling, ascending from inline depth")
    func nextBlockHopsBetweenParagraphs() throws {
        let source = "First paragraph.\n\nSecond paragraph.\n"
        let fixture = try makeFixture(source)
        // Place cursor inside the first paragraph's text.
        let insideOffset = try utf16Offset(of: "paragraph", in: source)
        fixture.placeCursor(atUTF16: insideOffset)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        // Entry should land on the first paragraph (cstVisualEntry skips glue).
        let firstForest = try #require(fixture.coordinator.cstForest)
        #expect(headKind(firstForest) == .paragraph)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTNextBlock" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        let secondForest = try #require(fixture.coordinator.cstForest)
        #expect(headKind(secondForest) == .paragraph)
        let secondOffset = try utf16Offset(of: "Second paragraph", in: source)
        #expect(
            Int(secondForest.byteRange.start.rawValue) == secondOffset,
            "expected second paragraph at \(secondOffset); saw \(secondForest.byteRange.start.rawValue)"
        )
    }

    @Test(":CSTNextSiblingHeading skips deeper-level headings")
    func nextSiblingHeadingSkipsDeeperLevels() throws {
        let source = "# H1a\n\n## H2a\n\n# H1b\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        #expect(headKind(try #require(fixture.coordinator.cstForest)) == .atxHeading)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTNextSiblingHeading" {
            _ = fixture.controller.handle(.char(ch))
        }
        _ = fixture.controller.handle(.special(.returnKey))

        let result = try #require(fixture.coordinator.cstForest)
        #expect(headKind(result) == .atxHeading)
        let h1bOffset = try utf16Offset(of: "# H1b", in: source)
        #expect(
            Int(result.byteRange.start.rawValue) == h1bOffset,
            "expected H1b at \(h1bOffset) — same level as H1a, skipping H2a"
        )
    }

    @Test(":CSTGlobalFind heading jumps to the next heading anywhere in the document")
    func globalFindLeavesSubtree() throws {
        // First paragraph has no heading; the heading is in root's
        // second-after-blankLine position. :CSTFind (subtree-bounded)
        // would return nil. :CSTGlobalFind crosses into the next
        // root sibling and lands on the heading.
        let source = "Intro paragraph.\n\n# The Heading\n\nMore body.\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        #expect(fixture.controller.mode == .visualCST)
        let entryForest = try #require(fixture.coordinator.cstForest)
        #expect(headKind(entryForest) == .paragraph)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTGlobalFind heading" {
            _ = fixture.controller.handle(.char(ch))
        }
        _ = fixture.controller.handle(.special(.returnKey))

        #expect(fixture.controller.mode == .visualCST)
        let after = try #require(fixture.coordinator.cstForest)
        #expect(
            headKind(after) == .atxHeading,
            "global preorder forward should cross root siblings to find the heading; saw \(headKind(after))"
        )
    }

    @Test(":CSTEnter from normal mode lands in .visualCST with cstForest set")
    func enterCSTViaCommandLineFromNormal() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        #expect(fixture.controller.mode == .normal)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTEnter" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        #expect(fixture.controller.mode == .visualCST)
        #expect(
            fixture.coordinator.cstForest != nil,
            "cstForest must be set after :CSTEnter — the async mode observer for the intermediate .normal transition must not nuke the forest the .visualCST delegate just built"
        )
    }

    @Test("entering : from .visualCST and pressing Esc preserves the cstForest")
    func commandLineRoundTripPreservesVisualCSTForest() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        let beforeForest = try #require(fixture.coordinator.cstForest)

        _ = fixture.controller.handle(.char(":"))
        #expect(fixture.controller.mode == .commandLine)

        _ = fixture.controller.handle(.special(.escape))
        #expect(fixture.controller.mode == .visualCST)

        let afterForest = try #require(fixture.coordinator.cstForest)
        #expect(
            afterForest == beforeForest,
            "cstForest must survive the : round-trip — the Coordinator's mode observer special-cases .commandLine"
        )
    }

    @Test(": CSTSwapEnds from .visualCST dispatches and returns to .visualCST")
    func commandLineCSTSwapEndsRoundTrip() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n")
        fixture.placeCursor(atUTF16: 0)
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        // Extend so swap-ends has a visible effect.
        _ = fixture.controller.handle(.char("J"))
        let beforeForest = try #require(fixture.coordinator.cstForest)

        _ = fixture.controller.handle(.char(":"))
        for ch in "CSTSwapEnds" { _ = fixture.controller.handle(.char(ch)) }
        _ = fixture.controller.handle(.special(.returnKey))

        #expect(fixture.controller.mode == .visualCST)
        let afterForest = try #require(fixture.coordinator.cstForest)
        #expect(
            afterForest == beforeForest.withEndsSwapped(),
            "anchor and head should be swapped"
        )
    }

    @Test("pending find argument is canceled by Esc; next key dispatches normally")
    func findKindCancelByEscape() throws {
        let fixture = try makeFixture("Hello world.\n")
        fixture.placeCursor(atUTF16: 0)
        // Enter via the binding tree so the controller's mode flips too
        // (the f / F bindings are mode-scoped to .visualCST).
        _ = fixture.controller.handle(.char("g"))
        _ = fixture.controller.handle(.char("C"))
        #expect(fixture.controller.mode == .visualCST)
        let beforeForest = try #require(fixture.coordinator.cstForest)

        // Arm pending find via key sequence.
        _ = fixture.controller.handle(.char("f"))
        #expect(fixture.controller.pendingCharArgument == .findKindForward)

        // Esc cancels — silent, doesn't dispatch.
        _ = fixture.controller.handle(.special(.escape))
        #expect(fixture.controller.pendingCharArgument == nil)
        let afterEscForest = try #require(fixture.coordinator.cstForest)
        #expect(afterEscForest == beforeForest, "Esc should not have moved the forest")

        // Next keypress should dispatch through the binding tree, not as a typed-descent letter.
        // Press j — single-paragraph doc has no next sibling, so j is a no-op (forest unchanged).
        _ = fixture.controller.handle(.char("j"))
        let afterJForest = try #require(fixture.coordinator.cstForest)
        #expect(afterJForest == beforeForest, "j with no next sibling is a no-op")
    }

    @Test("swapEnds doesn't change the byte range")
    func swapEndsPreservesByteRange() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        fixture.coordinator.extendCSTSelection(.nextSibling, count: 1)
        let before = fixture.textView.cstSelectionRanges

        fixture.coordinator.swapCSTEnds()
        let after = fixture.textView.cstSelectionRanges

        #expect(after == before, "swap is a logical operation, not a range one")
    }

    @Test("block quote CST overlay projects away lifted quote markers")
    func blockQuoteOverlayUsesProjectedRanges() throws {
        let fixture = try makeFixture("> foo\n> bar\n> baz\n")
        fixture.placeCursor(atUTF16: 3)
        fixture.coordinator.enterCSTVisualMode()

        #expect(fixture.textView.cstSelectionRanges == [
            NSRange(location: 2, length: 4),
            NSRange(location: 8, length: 4),
            NSRange(location: 14, length: 4)
        ])
    }

    @Test("nested list item CST overlay projects away base indent")
    func nestedListItemOverlayUsesProjectedRanges() throws {
        let source = """
        - foo
          - bar
            - bax
          - qux
        """
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- bar", in: source))
        fixture.coordinator.enterCSTVisualMode()

        #expect(fixture.textView.cstSelectionRanges == [
            NSRange(location: 8, length: 6),
            NSRange(location: 16, length: 8)
        ])
    }

    @Test("list item paragraph overlay projects away continuation prefix")
    func listItemParagraphOverlayUsesProjectedRanges() throws {
        let source = "- foo\n  bar\n"
        let fixture = try makeFixture(source)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- foo", in: source))
        fixture.coordinator.enterCSTVisualMode()
        fixture.coordinator.cstNavigate(.firstChild, count: 1)

        #expect(fixture.textView.cstSelectionRanges == [
            NSRange(location: 2, length: 4),
            NSRange(location: 8, length: 3)
        ])
    }

    @Test("explicit CST list item paste splices after current list item prefix")
    func explicitCSTListItemPasteSplicesAfterListItemPrefix() throws {
        let originalPasteboard = SystemPasteboard.pasteboard
        SystemPasteboard.pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "dev.sub.liminal.cst-list-paste.tests.\(UUID().uuidString)"
        ))
        defer { SystemPasteboard.pasteboard = originalPasteboard }

        let copySource = "- source\n  - bar\n  - baz\n"
        let parsedCopy = try LiminalParser().parse(copySource)
        let copyForest = try #require(
            firstChildListForestInFirstListItem(in: parsedCopy.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: copyForest,
            source: copySource
        )
        SystemPasteboard.write(
            text: capture.logicalText,
            kind: .cstForest,
            structuralPayloadData: try capture.clipboardPayload.serializedData()
        )

        let target = "- foo\n  - one\n  - two\n"
        let fixture = try makeFixture(target)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- one", in: target))
        fixture.coordinator.pasteCSTSplice(after: true)

        let expected = "- foo\n  - one\n  - bar\n  - baz\n  - two\n"
        #expect(fixture.textView.string == expected)
        #expect(fixture.document.session.source == expected)
    }

    @Test("explicit CST list item paste handles target list item after blank line")
    func explicitCSTListItemPasteHandlesTargetListItemAfterBlankLine() throws {
        let originalPasteboard = SystemPasteboard.pasteboard
        SystemPasteboard.pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "dev.sub.liminal.cst-list-paste-boundary.tests.\(UUID().uuidString)"
        ))
        defer { SystemPasteboard.pasteboard = originalPasteboard }

        let copySource = "- source\n  - bar\n"
        let parsedCopy = try LiminalParser().parse(copySource)
        let copyForest = try #require(
            firstChildListForestInFirstListItem(in: parsedCopy.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: copyForest,
            source: copySource
        )
        #expect(capture.fragment.wrapperKind == .listItem)
        #expect(capture.fragment.childKinds == [.list])
        #expect(capture.projection.kind == .listItemContent)
        SystemPasteboard.write(
            text: capture.logicalText,
            kind: .cstForest,
            structuralPayloadData: try capture.clipboardPayload.serializedData()
        )

        let target = "before\n\n- foo\n- baz\n"
        let fixture = try makeFixture(target)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- foo", in: target))
        fixture.coordinator.pasteCSTSplice(after: true)

        let expected = "before\n\n- foo\n- bar\n- baz\n"
        #expect(fixture.textView.string == expected)
        #expect(fixture.document.session.source == expected)
    }

    @Test("explicit CST list item paste splices into top-level list")
    func explicitCSTListItemPasteSplicesIntoTopLevelList() throws {
        let originalPasteboard = SystemPasteboard.pasteboard
        SystemPasteboard.pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "dev.sub.liminal.cst-root-list-paste.tests.\(UUID().uuidString)"
        ))
        defer { SystemPasteboard.pasteboard = originalPasteboard }

        let copySource = "- bar\n- baz\n"
        let parsedCopy = try LiminalParser().parse(copySource)
        let copyForest = try #require(
            rootListItemsForest(in: parsedCopy.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: copyForest,
            source: copySource
        )
        #expect(capture.fragment.wrapperKind == .list)
        #expect(capture.fragment.childKinds == [.listItem, .listItem])
        SystemPasteboard.write(
            text: capture.logicalText,
            kind: .cstForest,
            structuralPayloadData: try capture.clipboardPayload.serializedData()
        )

        let target = "- foo\n- qux\n"
        let fixture = try makeFixture(target)
        fixture.placeCursor(atUTF16: try utf16Offset(of: "- foo", in: target))
        fixture.coordinator.pasteCSTSplice(after: true)

        let expected = "- foo\n- bar\n- baz\n- qux\n"
        #expect(fixture.textView.string == expected)
        #expect(fixture.document.session.source == expected)
    }

    // MARK: - Safety

    @Test("CST navigation against a stale tree self-clears the forest")
    func staleForestSelfClears() throws {
        let fixture = try makeFixture("First paragraph.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initial = fixture.textView.cstSelectionRanges
        #expect(initial.contains { $0.length > 0 })

        // Programmatically replace the source — the new parse builds a
        // fresh tree, leaving the Coordinator's cstForest referencing
        // the old one. The next navigation call's treeID check should
        // self-clear without crashing.
        try fixture.document.session.replaceSource("Completely different text.\n")

        fixture.coordinator.cstNavigate(.nextSibling, count: 1)
        // Navigation early-returns because ensureForestIsLive() cleared
        // the stale forest. The overlay range is left as it was (the
        // mode is still .visualCST until the user Escs — a known v1
        // limitation documented in the plan). The contract under test
        // is "no crash."
        let final = fixture.textView.cstSelectionRanges
        #expect(final == initial || final.isEmpty,
                "stale-forest navigation should be safe (no crash, range either preserved or cleared)")
    }
}

// MARK: - Test fixture

/// Wires a `LiminalSourceDocument`, `Coordinator`, and `VimTextView`
/// together with just enough plumbing to drive CST mode by calling
/// `Coordinator` methods directly. Held strongly by the test (the
/// Coordinator's `textView` is `weak`).
@MainActor
private final class CSTFixture {
    let document: LiminalSourceDocument
    let coordinator: LiminalTextView.Coordinator
    let textView: VimTextView
    let controller: VimController

    init(source: String) throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource(source)
        self.document = document
        self.controller = document.vimController

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(textContainer)
        let textView = VimTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400),
                                   textContainer: textContainer)
        textView.string = source
        self.textView = textView

        let coordinator = LiminalTextView.Coordinator(document: document)
        coordinator.textView = textView
        self.coordinator = coordinator

        // Wire the controller's delegate so forceNormalMode + mode
        // observers behave like production.
        controller.delegate = coordinator
    }

    func placeCursor(atUTF16 location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }
}

@MainActor
private func makeFixture(_ source: String) throws -> CSTFixture {
    try CSTFixture(source: source)
}

@MainActor
private func cstSelectionRange(_ textView: VimTextView) throws -> NSRange {
    try #require(textView.cstSelectionRanges.first)
}

private func utf16Offset(of needle: String, in source: String) throws -> Int {
    let range = try #require(source.range(of: needle))
    return source.utf16.distance(from: source.utf16.startIndex, to: range.lowerBound)
}

private func headKind(_ forest: LiminalForest) -> LiminalKind {
    forest.parent.withCursor { cursor in
        cursor.green { green in green.child(at: forest.headChildIndex) }.kind
    }
}

private func firstChildListForestInFirstListItem(
    in tree: SharedSyntaxTree<LiminalLanguage>
) -> LiminalForest? {
    tree.withRoot { root in
        for rootIndex in 0..<root.childOrTokenCount {
            let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
            guard rootChildKind == .list else { continue }

            return root.withChildNode(atRawIndex: rootIndex) { list in
                list.withChildNode(atRawIndex: 0) { item in
                    for childIndex in 0..<item.childOrTokenCount {
                        let childKind = item.green { $0.child(at: childIndex) }.kind
                        guard childKind == .list else { continue }
                        return LiminalForest(
                            parent: item.makeHandle(),
                            anchorChildIndex: childIndex,
                            headChildIndex: childIndex
                        )
                    }
                    return nil
                } ?? nil
            } ?? nil
        }
        return nil
    }
}

private func rootListItemsForest(
    in tree: SharedSyntaxTree<LiminalLanguage>
) -> LiminalForest? {
    tree.withRoot { root in
        for rootIndex in 0..<root.childOrTokenCount {
            let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
            guard rootChildKind == .list else { continue }

            return root.withChildNode(atRawIndex: rootIndex) { list in
                guard list.childOrTokenCount > 0 else { return nil }
                return LiminalForest(
                    parent: list.makeHandle(),
                    anchorChildIndex: 0,
                    headChildIndex: list.childOrTokenCount - 1
                )
            } ?? nil
        }
        return nil
    }
}
