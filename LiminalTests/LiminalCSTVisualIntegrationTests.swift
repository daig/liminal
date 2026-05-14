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

        // The structural selection lives in `cstSelectionRange` (the
        // custom overlay), not `selectedRange` — the latter only holds
        // a parked caret in .visualCST.
        let sel = try #require(fixture.textView.cstSelectionRange)
        #expect(sel.length > 0, "entry should populate a CST selection")
        // The selection's start should be at byte 0 (paragraph start).
        #expect(sel.location == 0)
        // And it should cover at least "First paragraph." (16 utf16 chars).
        #expect(sel.length >= 16)
        // The system caret is parked at the overlay's start.
        #expect(fixture.textView.selectedRange().location == sel.location)
        #expect(fixture.textView.selectedRange().length == 0)
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
        let initialSel = try #require(fixture.textView.cstSelectionRange)

        fixture.coordinator.cstNavigate(.nextSibling, count: 1)
        let afterSel = try #require(fixture.textView.cstSelectionRange)

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
        let initial = try #require(fixture.textView.cstSelectionRange)

        fixture.coordinator.extendCSTSelection(.nextSibling, count: 1)
        let extended = try #require(fixture.textView.cstSelectionRange)

        #expect(extended.location == initial.location, "anchor end unchanged")
        #expect(extended.length > initial.length, "selection grew")
    }

    @Test("parent ascend collapses the selection to a singleton at the parent's slot")
    func parentAscendCollapsesSelection() throws {
        let fixture = try makeFixture("# Heading\n\nA paragraph.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initial = try #require(fixture.textView.cstSelectionRange)

        fixture.coordinator.cstNavigate(.parent, count: 1)
        let parentSel = try #require(fixture.textView.cstSelectionRange)

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
        let before = try #require(fixture.textView.cstSelectionRange)

        fixture.coordinator.cstNavigate(.firstChild, count: 1)
        let after = try #require(fixture.textView.cstSelectionRange)

        #expect(after == before, "opaque-block descend should not move selection")
    }

    @Test("swapEnds doesn't change the byte range")
    func swapEndsPreservesByteRange() throws {
        let fixture = try makeFixture("First.\n\nSecond.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        fixture.coordinator.extendCSTSelection(.nextSibling, count: 1)
        let before = try #require(fixture.textView.cstSelectionRange)

        fixture.coordinator.swapCSTEnds()
        let after = try #require(fixture.textView.cstSelectionRange)

        #expect(after == before, "swap is a logical operation, not a range one")
    }

    // MARK: - Safety

    @Test("CST navigation against a stale tree self-clears the forest")
    func staleForestSelfClears() throws {
        let fixture = try makeFixture("First paragraph.\n")
        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.enterCSTVisualMode()
        let initial = try #require(fixture.textView.cstSelectionRange)
        #expect(initial.length > 0)

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
        let final = fixture.textView.cstSelectionRange
        #expect(final == initial || final == nil,
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
