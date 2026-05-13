import Testing
@testable import Liminal

@Suite("Vim operator-pending")
@MainActor
struct VimOperatorPendingTests {

    // MARK: - Operator + motion

    @Test("d w → applyOperator(.delete, .motion(.wordForwardStart), 1)")
    func dw() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        #expect(c.pendingOperator == PendingOperator(kind: .delete, preCount: 1))
        _ = c.handle(.char("w"))
        #expect(c.pendingOperator == nil)
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.wordForwardStart), count: 1)
        ])
        #expect(c.mode == .normal)
    }

    @Test("3 d w → count = 3 (pre-operator count flows through)")
    func preCountDw() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("d"))
        #expect(c.pendingOperator == PendingOperator(kind: .delete, preCount: 3))
        _ = c.handle(.char("w"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.wordForwardStart), count: 3)
        ])
    }

    @Test("d 2 w → count = 2 (post-operator count)")
    func postCountDw() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("2"))
        _ = c.handle(.char("w"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.wordForwardStart), count: 2)
        ])
    }

    @Test("3 d 2 w → count = 6 (counts multiply)")
    func countsMultiply() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("d"))
        _ = c.handle(.char("2"))
        _ = c.handle(.char("w"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.wordForwardStart), count: 6)
        ])
    }

    @Test("d $ → operator + lineEnd motion")
    func dDollar() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("$"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.lineEnd), count: 1)
        ])
    }

    @Test("d g g → operator + documentStart (multi-key motion via the chord prefix)")
    func dgg() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("g"))
        // After `g`, partial chord — pendingOperator still set, no dispatch yet.
        #expect(c.pendingOperator?.kind == .delete)
        #expect(spy.applyOperatorCalls.isEmpty)
        _ = c.handle(.char("g"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.documentStart), count: 1)
        ])
        #expect(c.pendingOperator == nil)
    }

    @Test("d G → operator + documentEnd; default count is Int.max sentinel")
    func dG() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("G"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.documentEnd), count: Int.max)
        ])
    }

    // MARK: - Doubled operator (linewise)

    @Test("d d → applyOperator(.delete, .currentLine, 1)")
    func dd() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("d"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .currentLine, count: 1)
        ])
    }

    @Test("2 d d → count = 2")
    func twoDD() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("2"))
        _ = c.handle(.char("d"))
        _ = c.handle(.char("d"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .currentLine, count: 2)
        ])
    }

    @Test("c c → applyOperator(.change, .currentLine, 1) AND mode == .insert")
    func cc() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("c"))
        _ = c.handle(.char("c"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .change, target: .currentLine, count: 1)
        ])
        #expect(c.mode == .insert)
    }

    @Test("y y → applyOperator(.yank, .currentLine, 1); mode stays .normal")
    func yy() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("y"))
        _ = c.handle(.char("y"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .yank, target: .currentLine, count: 1)
        ])
        #expect(c.mode == .normal)
    }

    // MARK: - Vim's `cw → ce` quirk

    @Test("c w → controller substitutes wordForwardEnd (the cw → ce quirk)")
    func cwIsce() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("c"))
        _ = c.handle(.char("w"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .change, target: .motion(.wordForwardEnd), count: 1)
        ])
        #expect(c.mode == .insert)
    }

    @Test("d w retains wordForwardStart (quirk is change-only)")
    func dwUnchanged() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("w"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .motion(.wordForwardStart), count: 1)
        ])
    }

    // MARK: - Cancellation paths

    @Test("d Esc cancels pending; no dispatch")
    func dEsc() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.special(.escape))
        #expect(c.pendingOperator == nil)
        #expect(c.pendingCount == nil)
        #expect(spy.applyOperatorCalls.isEmpty)
        // No mode flip; insert isn't entered.
        #expect(c.mode == .normal)
    }

    @Test("d i cancels pending; insert mode is NOT entered (vim semantics)")
    func dInsertEntryCancels() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("i"))
        #expect(c.pendingOperator == nil)
        #expect(c.mode == .normal, "i was consumed as cancellation, not as insert-entry")
        #expect(spy.applyOperatorCalls.isEmpty)
        #expect(spy.prepareForInsertCalls.isEmpty)
    }

    @Test("d y cancels pending (different operator)")
    func dDifferentOpCancels() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("d"))
        _ = c.handle(.char("y"))
        #expect(c.pendingOperator == nil)
        #expect(spy.applyOperatorCalls.isEmpty)
    }

    // MARK: - Single-key shortcuts

    @Test("x → applyOperator(.delete, .charsAtCursor(before: false), 1)")
    func xShortcut() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("x"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .charsAtCursor(before: false), count: 1)
        ])
        #expect(c.mode == .normal)
        #expect(c.pendingOperator == nil)
    }

    @Test("3 x → count = 3")
    func xCount() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("x"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .charsAtCursor(before: false), count: 3)
        ])
    }

    @Test("X → applyOperator(.delete, .charsAtCursor(before: true), 1)")
    func XShortcut() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("X"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .charsAtCursor(before: true), count: 1)
        ])
    }

    @Test("D → applyOperator(.delete, .toLineEnd, 1)")
    func DShortcut() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("D"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .delete, target: .toLineEnd, count: 1)
        ])
    }

    @Test("C → applyOperator(.change, .toLineEnd, 1) AND mode == .insert")
    func CShortcut() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("C"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .change, target: .toLineEnd, count: 1)
        ])
        #expect(c.mode == .insert)
    }

    @Test("Y → applyOperator(.yank, .currentLine, 1); mode stays .normal")
    func YShortcut() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("Y"))
        #expect(spy.applyOperatorCalls == [
            .init(op: .yank, target: .currentLine, count: 1)
        ])
        #expect(c.mode == .normal)
    }

    // MARK: - Status presentation

    @Test("after d, status detail is \"d\"")
    func statusJustD() {
        let c = VimController()
        _ = c.handle(.char("d"))
        #expect(c.statusPresentation.detailText == "d")
    }

    @Test("after 3 d, status detail is \"3 d\"")
    func statusPreCountD() {
        let c = VimController()
        _ = c.handle(.char("3"))
        _ = c.handle(.char("d"))
        #expect(c.statusPresentation.detailText == "3 d")
    }

    @Test("after 3 d 2, status detail is \"3 d 2\"")
    func statusPreCountDPostCount() {
        let c = VimController()
        _ = c.handle(.char("3"))
        _ = c.handle(.char("d"))
        _ = c.handle(.char("2"))
        #expect(c.statusPresentation.detailText == "3 d 2")
    }

    @Test("after 3 d 2 w, status detail clears (dispatch happened)")
    func statusClearsAfterDispatch() {
        let c = VimController()
        let spy = OpSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("d"))
        _ = c.handle(.char("2"))
        _ = c.handle(.char("w"))
        #expect(c.statusPresentation.detailText == nil)
    }
}

@MainActor
private final class OpSpy: VimControllerDelegate {
    struct ApplyOperatorCall: Equatable {
        let op: VimOperator
        let target: OperatorTarget
        let count: Int
    }
    var applyOperatorCalls: [ApplyOperatorCall] = []
    var prepareForInsertCalls: [InsertPosition] = []

    func moveCursor(motion: CursorMotion, count: Int) {}
    func structuralMotion(_ motion: StructuralMotion, count: Int) {}
    func viewportMotion(_ motion: ViewportMotion, count: Int) {}
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {}
    func goToDefinitionAtCursor() {}
    func prepareForInsert(at position: InsertPosition) {
        prepareForInsertCalls.append(position)
    }
    func enterVisualMode(kind: VisualKind) {}
    func yankSelection() {}
    func deleteSelection() {}
    func paste(after: Bool) {}
    func applyOperator(
        _ op: VimOperator, target: OperatorTarget, count: Int
    ) {
        applyOperatorCalls.append(.init(op: op, target: target, count: count))
    }
    func toggleTaskAtCursor() {}
    func setMark(_ name: Character) {}
    func jumpToMark(_ name: Character) {}
}
