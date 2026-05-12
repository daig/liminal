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

    // MARK: - Status / hint presentation

    @Test("initial state: status mode is normal, detail is nil, no snapshot")
    func initialPresentation() {
        let c = VimController()
        #expect(c.statusPresentation.mode == .normal)
        #expect(c.statusPresentation.detailText == nil)
        #expect(c.visibleHintSnapshot == nil)
    }

    @Test("count digit publishes count in status detail")
    func countPublishedInStatus() {
        let c = VimController()
        _ = c.handle(.char("3"))
        #expect(c.statusPresentation.detailText == "3")
    }

    @Test("partial chord shows pending keys in status detail")
    func partialChordPublishedInStatus() {
        let c = VimController()
        _ = c.handle(.special(.space))
        #expect(c.statusPresentation.detailText == "<Space>")
    }

    @Test("status detail clears after dispatch")
    func statusClearsAfterDispatch() {
        let c = VimController()
        _ = c.handle(.char("3"))
        _ = c.handle(.char("h"))
        #expect(c.statusPresentation.detailText == nil)
    }

    @Test("status mode reflects mode switch")
    func statusReflectsMode() {
        let c = VimController()
        _ = c.handle(.char("i"))
        #expect(c.statusPresentation.mode == .insert)
        _ = c.handle(.special(.escape))
        #expect(c.statusPresentation.mode == .normal)
    }

    @Test("with zero onset delay: pending prefix produces visible snapshot synchronously")
    func snapshotSynchronousWithZeroDelay() {
        let c = VimController(
            bindings: VimController.defaultBindings(),
            hintOnsetDelay: .zero
        )
        _ = c.handle(.special(.space))
        let snapshot = c.visibleHintSnapshot
        #expect(snapshot != nil)
        #expect(snapshot?.title == "<Space>")
        let descriptions = snapshot?.items.map(\.description) ?? []
        #expect(descriptions.contains("Toggle task checkbox"))
    }

    @Test("snapshot clears when prefix clears")
    func snapshotClearsAfterDispatch() {
        let c = VimController(
            bindings: VimController.defaultBindings(),
            hintOnsetDelay: .zero
        )
        _ = c.handle(.special(.space))
        #expect(c.visibleHintSnapshot != nil)
        _ = c.handle(.char("t"))
        #expect(c.visibleHintSnapshot == nil)
    }

    @Test("default 200ms delay does NOT publish snapshot synchronously")
    func snapshotDelayedByDefault() {
        let c = VimController() // 200ms default
        _ = c.handle(.special(.space))
        // Status detail updates immediately; snapshot only after delay.
        #expect(c.statusPresentation.detailText == "<Space>")
        #expect(c.visibleHintSnapshot == nil)
    }

    @Test("unmatched key after partial clears the snapshot")
    func unmatchedSubKeyClearsSnapshot() {
        let c = VimController(
            bindings: VimController.defaultBindings(),
            hintOnsetDelay: .zero
        )
        _ = c.handle(.special(.space))
        #expect(c.visibleHintSnapshot != nil)
        _ = c.handle(.char("z")) // not a continuation; clears
        #expect(c.visibleHintSnapshot == nil)
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
