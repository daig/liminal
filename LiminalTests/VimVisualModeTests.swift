import Testing
@testable import Liminal

@Suite("Vim visual modes")
@MainActor
struct VimVisualModeTests {

    // MARK: - Entry

    @Test(
        "v / V / Ctrl-v from normal dispatch enterVisualMode with the right kind and flip mode",
        arguments: [
            (VimKey.char("v"), VisualKind.charwise, VimMode.visual),
            (VimKey.char("V"), .linewise, .visualLine),
            (VimKey.char("v", modifiers: [.control]), .blockwise, .visualBlock),
        ] as [(VimKey, VisualKind, VimMode)]
    )
    func enterVisualEntries(_ input: (VimKey, VisualKind, VimMode)) {
        let (key, expectedKind, expectedMode) = input
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy

        _ = c.handle(key)
        #expect(c.mode == expectedMode)
        #expect(spy.enterVisualModeCalls == [expectedKind])
    }

    @Test("Esc returns to normal from any visual mode")
    func escFromVisual() {
        for kind: VimKey in [.char("v"), .char("V"), .char("v", modifiers: [.control])] {
            let c = VimController()
            let spy = VisualSpy()
            c.delegate = spy
            _ = c.handle(kind)
            #expect(c.mode.isVisual)
            _ = c.handle(.special(.escape))
            #expect(c.mode == .normal)
        }
    }

    // MARK: - Operators inside visual modes

    @Test(
        "y in any visual mode dispatches yankSelection and returns to normal",
        arguments: [
            VimKey.char("v"),
            .char("V"),
            .char("v", modifiers: [.control]),
        ]
    )
    func yankFromVisual(_ entry: VimKey) {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(entry)
        _ = c.handle(.char("y"))
        #expect(spy.yankSelectionCallCount == 1)
        #expect(c.mode == .normal)
    }

    @Test(
        "d in any visual mode dispatches deleteSelection and returns to normal",
        arguments: [
            VimKey.char("v"),
            .char("V"),
            .char("v", modifiers: [.control]),
        ]
    )
    func deleteFromVisual(_ entry: VimKey) {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(entry)
        _ = c.handle(.char("d"))
        #expect(spy.deleteSelectionCallCount == 1)
        #expect(c.mode == .normal)
    }

    @Test(
        "c in any visual mode deletes selection and enters insert mode",
        arguments: [
            VimKey.char("v"),
            .char("V"),
            .char("v", modifiers: [.control]),
        ]
    )
    func changeFromVisual(_ entry: VimKey) {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(entry)
        _ = c.handle(.char("c"))
        #expect(spy.deleteSelectionCallCount == 1)
        #expect(c.mode == .insert)
    }

    // MARK: - Paste

    @Test("p in normal dispatches paste(after: true)")
    func pasteAfter() {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(.char("p"))
        #expect(spy.pasteCalls == [true])
        #expect(c.mode == .normal)
    }

    @Test("P in normal dispatches paste(after: false)")
    func pasteBefore() {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(.char("P"))
        #expect(spy.pasteCalls == [false])
        #expect(c.mode == .normal)
    }

    // MARK: - Motions extend in visual mode

    @Test(
        "h/j/k/l motions still dispatch when in any visual mode",
        arguments: [
            VimKey.char("v"),
            .char("V"),
            .char("v", modifiers: [.control]),
        ]
    )
    func motionsFireInVisual(_ entry: VimKey) {
        let c = VimController()
        let spy = VisualSpy()
        c.delegate = spy
        _ = c.handle(entry)
        spy.moveCursorCalls.removeAll()

        _ = c.handle(.char("l"))
        _ = c.handle(.char("j"))
        #expect(spy.moveCursorCalls == [
            .init(motion: .right, count: 1),
            .init(motion: .down, count: 1),
        ])
        #expect(c.mode.isVisual, "stays in visual after motion")
    }

    // MARK: - VimMode.isVisual

    @Test("isVisual is true for the three visual cases and false for normal/insert")
    func isVisualClassification() {
        #expect(VimMode.visual.isVisual)
        #expect(VimMode.visualLine.isVisual)
        #expect(VimMode.visualBlock.isVisual)
        #expect(VimMode.normal.isVisual == false)
        #expect(VimMode.insert.isVisual == false)
        #expect(VimMode.slot.isVisual == false)
    }
}

@MainActor
private final class VisualSpy: VimControllerDelegate {
    struct MoveCall: Equatable {
        let motion: CursorMotion
        let count: Int
    }
    var moveCursorCalls: [MoveCall] = []
    var enterVisualModeCalls: [VisualKind] = []
    var yankSelectionCallCount = 0
    var deleteSelectionCallCount = 0
    var pasteCalls: [Bool] = []

    func moveCursor(motion: CursorMotion, count: Int) {
        moveCursorCalls.append(.init(motion: motion, count: count))
    }
    func structuralMotion(_ motion: StructuralMotion, count: Int) {}
    func viewportMotion(_ motion: ViewportMotion, count: Int) {}
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {}
    func goToDefinitionAtCursor() {}
    func prepareForInsert(at position: InsertPosition) {}
    func enterVisualMode(kind: VisualKind) {
        enterVisualModeCalls.append(kind)
    }
    func yankSelection() { yankSelectionCallCount += 1 }
    func deleteSelection() { deleteSelectionCallCount += 1 }
    func paste(after: Bool) { pasteCalls.append(after) }
    func toggleTaskAtCursor() {}
    func setMark(_ name: Character) {}
    func jumpToMark(_ name: Character) {}
    // Visual CST mode methods inherit no-op defaults from the protocol
    // extension; this spy doesn't record them (see VimVisualCSTModeTests
    // for tests that do).
}
