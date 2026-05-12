import Testing
@testable import Liminal

@Suite("VimController")
@MainActor
struct VimControllerTests {

    @Test("initial mode is normal")
    func initialMode() {
        let c = VimController()
        #expect(c.mode == .normal)
        #expect(c.pendingKeys.isEmpty)
        #expect(c.pendingCount == nil)
    }

    @Test("i transitions to insert; Esc transitions back to normal")
    func modeTransitions() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("i"))
        #expect(c.mode == .insert)

        _ = c.handle(.special(.escape))
        #expect(c.mode == .normal)
    }

    @Test("h in Normal dispatches moveCursor(.left, count: 1)")
    func motionDispatch() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("h"))
        #expect(spy.moveCursorCalls == [.init(direction: .left, count: 1)])
    }

    @Test("3 h dispatches with count 3")
    func countPrefix() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        #expect(c.pendingCount == 3)
        _ = c.handle(.char("h"))
        #expect(spy.moveCursorCalls == [.init(direction: .left, count: 3)])
        #expect(c.pendingCount == nil)
    }

    @Test("multi-digit count accumulates")
    func multiDigitCount() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("1"))
        _ = c.handle(.char("2"))
        _ = c.handle(.char("h"))
        #expect(spy.moveCursorCalls == [.init(direction: .left, count: 12)])
    }

    @Test("Space + t dispatches toggleTaskAtCursor")
    func leaderChord() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.special(.space))
        #expect(c.pendingKeys == [.special(.space)])
        _ = c.handle(.char("t"))
        #expect(spy.toggleTaskCallCount == 1)
        #expect(c.pendingKeys.isEmpty)
    }

    @Test("unmatched key from Normal mode is consumed and clears pending")
    func unmatchedNormalKey() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        let result = c.handle(.char("z"))
        #expect(result == .consumed)
        #expect(c.pendingKeys.isEmpty)
        #expect(c.pendingCount == nil)
    }

    @Test("unmatched key in Insert mode passes through")
    func unmatchedInsertKey() {
        let c = VimController()
        _ = c.handle(.char("i"))
        #expect(c.mode == .insert)

        let result = c.handle(.char("a"))
        #expect(result == .passthrough)
    }

    @Test("Esc consumed in Insert mode")
    func escConsumedInInsert() {
        let c = VimController()
        _ = c.handle(.char("i"))
        let result = c.handle(.special(.escape))
        #expect(result == .consumed)
        #expect(c.mode == .normal)
    }

    @Test("mode change clears any pending state")
    func modeChangeClearsPending() {
        let c = VimController()
        _ = c.handle(.char("3"))
        #expect(c.pendingCount == 3)
        _ = c.handle(.char("i"))
        #expect(c.pendingCount == nil)
        #expect(c.pendingKeys.isEmpty)
    }

    @Test("structural motion delegates with count")
    func structuralMotionDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("}"))
        #expect(spy.structuralMotionCalls == [.init(motion: .nextSibling, count: 1)])

        _ = c.handle(.char("2"))
        _ = c.handle(.char("{"))
        #expect(spy.structuralMotionCalls.last == .init(motion: .previousSibling, count: 2))
    }
}

@MainActor
private final class VimDelegateSpy: VimControllerDelegate {
    struct MoveCall: Equatable {
        let direction: MoveDirection
        let count: Int
    }
    struct StructuralCall: Equatable {
        let motion: StructuralMotion
        let count: Int
    }

    var moveCursorCalls: [MoveCall] = []
    var structuralMotionCalls: [StructuralCall] = []
    var toggleTaskCallCount = 0

    func moveCursor(direction: MoveDirection, count: Int) {
        moveCursorCalls.append(.init(direction: direction, count: count))
    }
    func structuralMotion(_ motion: StructuralMotion, count: Int) {
        structuralMotionCalls.append(.init(motion: motion, count: count))
    }
    func toggleTaskAtCursor() {
        toggleTaskCallCount += 1
    }
}
