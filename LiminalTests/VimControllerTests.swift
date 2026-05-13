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
        #expect(spy.moveCursorCalls == [.init(motion: .left, count: 1)])
    }

    @Test("3 h dispatches with count 3")
    func countPrefix() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        #expect(c.pendingCount == 3)
        _ = c.handle(.char("h"))
        #expect(spy.moveCursorCalls == [.init(motion: .left, count: 3)])
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
        #expect(spy.moveCursorCalls == [.init(motion: .left, count: 12)])
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

    @Test("H/M/L viewport motions delegate with the right count semantics")
    func viewportMotionsDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("H"))
        #expect(spy.viewportMotionCalls.last == .init(motion: .screenTop, count: 1))

        _ = c.handle(.char("3"))
        _ = c.handle(.char("H"))
        #expect(spy.viewportMotionCalls.last == .init(motion: .screenTop, count: 3))

        _ = c.handle(.char("L"))
        #expect(spy.viewportMotionCalls.last == .init(motion: .screenBottom, count: 1))

        _ = c.handle(.char("9"))
        _ = c.handle(.char("L"))
        #expect(spy.viewportMotionCalls.last == .init(motion: .screenBottom, count: 9))

        // M ignores any count.
        _ = c.handle(.char("5"))
        _ = c.handle(.char("M"))
        #expect(spy.viewportMotionCalls.last == .init(motion: .screenMiddle, count: 1))
    }

    @Test("g-prefix display-line motions delegate with the right semantics")
    func displayLineMotionsDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        // gj / gk: count repeats.
        _ = c.handle(.char("g"))
        _ = c.handle(.char("j"))
        #expect(spy.displayLineMotionCalls.last == .init(motion: .down, count: 1))

        _ = c.handle(.char("4"))
        _ = c.handle(.char("g"))
        _ = c.handle(.char("k"))
        #expect(spy.displayLineMotionCalls.last == .init(motion: .up, count: 4))

        // g0 / g^ / g$: count ignored (vim convention).
        _ = c.handle(.char("9"))
        _ = c.handle(.char("g"))
        _ = c.handle(.char("0"))
        #expect(spy.displayLineMotionCalls.last == .init(motion: .start, count: 1))

        _ = c.handle(.char("g"))
        _ = c.handle(.char("^"))
        #expect(spy.displayLineMotionCalls.last == .init(motion: .firstNonBlank, count: 1))

        _ = c.handle(.char("g"))
        _ = c.handle(.char("$"))
        #expect(spy.displayLineMotionCalls.last == .init(motion: .end, count: 1))
    }

    @Test("gg still resolves to documentStart even with the new g-prefix bindings")
    func ggStillWorks() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("g"))
        #expect(spy.moveCursorCalls.last == .init(motion: .documentStart, count: 1))
    }

    @Test("gh dispatches enclosingHeading; counts repeat for prev/next heading")
    func headingMotionsDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("h"))
        #expect(spy.structuralMotionCalls.last == .init(motion: .enclosingHeading, count: 1))

        _ = c.handle(.char("["))
        _ = c.handle(.char("["))
        #expect(spy.structuralMotionCalls.last == .init(motion: .previousHeading, count: 1))

        _ = c.handle(.char("3"))
        _ = c.handle(.char("]"))
        _ = c.handle(.char("]"))
        #expect(spy.structuralMotionCalls.last == .init(motion: .nextHeading, count: 3))
    }

    @Test("[r / ]r dispatch reference motions with counts")
    func referenceMotionsDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("["))
        _ = c.handle(.char("r"))
        #expect(spy.structuralMotionCalls.last == .init(motion: .previousReference, count: 1))

        _ = c.handle(.char("5"))
        _ = c.handle(.char("]"))
        _ = c.handle(.char("r"))
        #expect(spy.structuralMotionCalls.last == .init(motion: .nextReference, count: 5))
    }

    @Test("gd dispatches goToDefinitionAtCursor")
    func gdDelegated() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("d"))
        #expect(spy.goToDefinitionCallCount == 1)
    }

    @Test(
        "insert-mode entry bindings dispatch the right InsertPosition + flip mode",
        arguments: [
            ("i", InsertPosition.atCursor),
            ("a", .afterCursor),
            ("I", .atLineFirstNonBlank),
            ("A", .atLineEnd),
            ("o", .openLineBelow),
            ("O", .openLineAbove),
            ("s", .substituteChar),
            ("S", .substituteLine)
        ] as [(Character, InsertPosition)]
    )
    func insertEntryBindings(_ input: (Character, InsertPosition)) {
        let (key, expected) = input
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char(key))
        #expect(c.mode == .insert)
        #expect(spy.prepareForInsertCalls == [expected])
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

    // MARK: - Tier A: line / word / document motion

    @Test("0 dispatches lineStart motion")
    func zeroLineStart() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("0"))
        #expect(spy.moveCursorCalls == [.init(motion: .lineStart, count: 1)])
    }

    @Test("0 after a count digit is consumed as the trailing digit")
    func zeroAsCountDigit() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("3"))
        _ = c.handle(.char("0"))
        #expect(c.pendingCount == 30)
        _ = c.handle(.char("j"))
        #expect(spy.moveCursorCalls == [.init(motion: .down, count: 30)])
    }

    @Test("^ dispatches lineFirstNonBlank motion")
    func caretFirstNonBlank() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("^"))
        #expect(spy.moveCursorCalls == [.init(motion: .lineFirstNonBlank, count: 1)])
    }

    @Test("$ dispatches lineEnd motion")
    func dollarLineEnd() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("$"))
        #expect(spy.moveCursorCalls == [.init(motion: .lineEnd, count: 1)])
    }

    @Test("w/b/e dispatch word motions with count")
    func wordMotions() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("w"))
        _ = c.handle(.char("3"))
        _ = c.handle(.char("b"))
        _ = c.handle(.char("e"))
        #expect(spy.moveCursorCalls == [
            .init(motion: .wordForwardStart, count: 1),
            .init(motion: .wordBackward, count: 3),
            .init(motion: .wordForwardEnd, count: 1),
        ])
    }

    @Test("gg with no count targets line 1")
    func ggDefault() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        #expect(c.pendingKeys == [.char("g")])
        _ = c.handle(.char("g"))
        #expect(spy.moveCursorCalls == [.init(motion: .documentStart, count: 1)])
    }

    @Test("5gg targets line 5")
    func ggWithCount() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("5"))
        _ = c.handle(.char("g"))
        _ = c.handle(.char("g"))
        #expect(spy.moveCursorCalls == [.init(motion: .documentStart, count: 5)])
    }

    @Test("G with no count uses Int.max sentinel (last line)")
    func gLastLine() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("G"))
        #expect(spy.moveCursorCalls == [.init(motion: .documentEnd, count: Int.max)])
    }

    @Test("5G targets line 5")
    func gWithCount() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("5"))
        _ = c.handle(.char("G"))
        #expect(spy.moveCursorCalls == [.init(motion: .documentEnd, count: 5)])
    }

    // MARK: - Marks (m / `)

    @Test("m arms pendingCharArgument(.setMark)")
    func mArmsSetMark() {
        let c = VimController()
        _ = c.handle(.char("m"))
        #expect(c.pendingCharArgument == .setMark)
        // pendingKeys cleared since `m` resolved to a (terminal) command.
        #expect(c.pendingKeys.isEmpty)
    }

    @Test("m + a dispatches setMark('a') and clears pending")
    func mAFlow() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("m"))
        _ = c.handle(.char("a"))
        #expect(spy.setMarkCalls == ["a"])
        #expect(c.pendingCharArgument == nil)
    }

    @Test("backtick + a dispatches jumpToMark('a')")
    func backtickAFlow() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("`"))
        #expect(c.pendingCharArgument == .jumpToMark)
        _ = c.handle(.char("z"))
        #expect(spy.jumpToMarkCalls == ["z"])
        #expect(c.pendingCharArgument == nil)
    }

    @Test("Esc cancels pending char argument")
    func escCancelsCharArg() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("m"))
        #expect(c.pendingCharArgument == .setMark)
        _ = c.handle(.special(.escape))
        #expect(c.pendingCharArgument == nil)
        #expect(spy.setMarkCalls.isEmpty)
    }

    @Test("non-letter mark name is silently dropped")
    func invalidMarkNameDropped() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("m"))
        _ = c.handle(.char("5")) // not a valid mark name
        #expect(spy.setMarkCalls.isEmpty)
        #expect(c.pendingCharArgument == nil)
    }

    @Test("upper-case letter mark name is dropped in v1 (a-z only)")
    func uppercaseMarkRejected() {
        let c = VimController()
        let spy = VimDelegateSpy()
        c.delegate = spy

        _ = c.handle(.char("m"))
        _ = c.handle(.char("A"))
        #expect(spy.setMarkCalls.isEmpty)
        #expect(c.pendingCharArgument == nil)
    }

    @Test("status detail surfaces pending char argument")
    func statusReflectsCharArg() {
        let c = VimController()
        _ = c.handle(.char("m"))
        #expect(c.statusPresentation.detailText == "m <a-z>")
    }
}

@MainActor
private final class VimDelegateSpy: VimControllerDelegate {
    struct MoveCall: Equatable {
        let motion: CursorMotion
        let count: Int
    }
    struct StructuralCall: Equatable {
        let motion: StructuralMotion
        let count: Int
    }
    struct ViewportCall: Equatable {
        let motion: ViewportMotion
        let count: Int
    }
    struct DisplayLineCall: Equatable {
        let motion: DisplayLineMotion
        let count: Int
    }

    struct ApplyOperatorCall: Equatable {
        let op: VimOperator
        let target: OperatorTarget
        let count: Int
    }

    var moveCursorCalls: [MoveCall] = []
    var structuralMotionCalls: [StructuralCall] = []
    var viewportMotionCalls: [ViewportCall] = []
    var displayLineMotionCalls: [DisplayLineCall] = []
    var goToDefinitionCallCount = 0
    var prepareForInsertCalls: [InsertPosition] = []
    var enterVisualModeCalls: [VisualKind] = []
    var yankSelectionCallCount = 0
    var deleteSelectionCallCount = 0
    var pasteCalls: [Bool] = []
    var applyOperatorCalls: [ApplyOperatorCall] = []
    var toggleTaskCallCount = 0
    var setMarkCalls: [Character] = []
    var jumpToMarkCalls: [Character] = []

    func moveCursor(motion: CursorMotion, count: Int) {
        moveCursorCalls.append(.init(motion: motion, count: count))
    }
    func structuralMotion(_ motion: StructuralMotion, count: Int) {
        structuralMotionCalls.append(.init(motion: motion, count: count))
    }
    func viewportMotion(_ motion: ViewportMotion, count: Int) {
        viewportMotionCalls.append(.init(motion: motion, count: count))
    }
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {
        displayLineMotionCalls.append(.init(motion: motion, count: count))
    }
    func goToDefinitionAtCursor() {
        goToDefinitionCallCount += 1
    }
    func prepareForInsert(at position: InsertPosition) {
        prepareForInsertCalls.append(position)
    }
    func enterVisualMode(kind: VisualKind) {
        enterVisualModeCalls.append(kind)
    }
    func yankSelection() {
        yankSelectionCallCount += 1
    }
    func deleteSelection() {
        deleteSelectionCallCount += 1
    }
    func paste(after: Bool) {
        pasteCalls.append(after)
    }
    func applyOperator(
        _ op: VimOperator,
        target: OperatorTarget,
        count: Int
    ) {
        applyOperatorCalls.append(.init(op: op, target: target, count: count))
    }
    func toggleTaskAtCursor() {
        toggleTaskCallCount += 1
    }
    func setMark(_ name: Character) {
        setMarkCalls.append(name)
    }
    func jumpToMark(_ name: Character) {
        jumpToMarkCalls.append(name)
    }
}
