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
