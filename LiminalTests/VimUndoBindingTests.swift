import Testing
@testable import Liminal

@Suite("Vim undo bindings")
@MainActor
struct VimUndoBindingTests {

    @Test("u in normal dispatches undo(count: 1)")
    func uDispatch() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("u"))
        #expect(spy.undoCalls == [1])
        #expect(c.mode == .normal)
    }

    @Test("3u dispatches undo with count 3")
    func uWithCount() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("u"))
        #expect(spy.undoCalls == [3])
    }

    @Test("Ctrl-r dispatches redo(count: 1)")
    func ctrlRDispatch() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("r", modifiers: [.control]))
        #expect(spy.redoCalls == [1])
    }

    @Test("5 Ctrl-r dispatches redo with count 5")
    func ctrlRWithCount() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("5"))
        _ = c.handle(.char("r", modifiers: [.control]))
        #expect(spy.redoCalls == [5])
    }

    @Test("u in insert mode is unbound — passes through to NSTextView")
    func uInInsertPassesThrough() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("i"))
        #expect(c.mode == .insert)

        let result = c.handle(.char("u"))
        #expect(result == .passthrough,
                "u in insert mode is a literal char, not undo")
        #expect(spy.undoCalls.isEmpty)
    }

    @Test("Esc out of insert dispatches commitInsertSession before mode flips")
    func escFromInsertCommits() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.char("i"))
        #expect(c.mode == .insert)
        _ = c.handle(.special(.escape))
        #expect(c.mode == .normal)
        #expect(spy.commitInsertSessionCallCount == 1)
    }

    @Test("Esc from normal does NOT trigger commitInsertSession")
    func escFromNormalNoCommit() {
        let c = VimController()
        let spy = UndoSpy()
        c.delegate = spy

        _ = c.handle(.special(.escape))
        #expect(spy.commitInsertSessionCallCount == 0)
    }
}

@MainActor
private final class UndoSpy: VimControllerDelegate {
    var undoCalls: [Int] = []
    var redoCalls: [Int] = []
    var commitInsertSessionCallCount = 0

    func moveCursor(motion: CursorMotion, count: Int) {}
    func structuralMotion(_ motion: StructuralMotion, count: Int) {}
    func viewportMotion(_ motion: ViewportMotion, count: Int) {}
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {}
    func goToDefinitionAtCursor() {}
    func prepareForInsert(at position: InsertPosition) {}
    func enterVisualMode(kind: VisualKind) {}
    func yankSelection() {}
    func deleteSelection() {}
    func paste(after: Bool) {}
    func applyOperator(
        _ op: VimOperator, target: OperatorTarget, count: Int
    ) {}
    func undo(count: Int) { undoCalls.append(count) }
    func redo(count: Int) { redoCalls.append(count) }
    func commitInsertSession() { commitInsertSessionCallCount += 1 }
    func toggleTaskAtCursor() {}
    func setMark(_ name: Character) {}
    func jumpToMark(_ name: Character) {}
}
