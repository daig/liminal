import Testing
@testable import Liminal

@Suite("Vim visual CST mode")
@MainActor
struct VimVisualCSTModeTests {

    // MARK: - Entry / exit

    @Test("gC from normal flips to .visualCST and dispatches enterCSTVisualMode")
    func gCEntersVisualCST() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        #expect(c.mode == .visualCST)
        #expect(spy.enterCSTVisualModeCallCount == 1)
    }

    @Test("Esc from .visualCST returns to normal")
    func escFromVisualCST() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        #expect(c.mode == .visualCST)
        _ = c.handle(.special(.escape))
        #expect(c.mode == .normal)
    }

    // MARK: - Operators

    @Test(
        "y / d / c in .visualCST dispatch the existing visual-operator delegate calls",
        arguments: [
            (VimKey.char("y"), VisualOp.yank),
            (.char("d"), .delete),
            (.char("c"), .change),
        ] as [(VimKey, VisualOp)]
    )
    func operatorsInVisualCST(_ args: (VimKey, VisualOp)) {
        let (key, op) = args
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy

        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        _ = c.handle(key)

        switch op {
        case .yank:
            #expect(spy.yankSelectionCallCount == 1)
            #expect(c.mode == .normal)
        case .delete:
            #expect(spy.deleteSelectionCallCount == 1)
            #expect(c.mode == .normal)
        case .change:
            // change deletes then enters insert mode
            #expect(spy.deleteSelectionCallCount == 1)
            #expect(c.mode == .insert)
        }
    }

    // MARK: - Navigation motions

    @Test(
        "h / l / j / k slide the forest via cstNavigate with the right motion",
        arguments: [
            (VimKey.char("h"), CSTMotion.parent),
            (.char("l"), .firstChild),
            (.char("j"), .nextSibling),
            (.char("k"), .previousSibling),
        ] as [(VimKey, CSTMotion)]
    )
    func navigationDispatchesMotion(_ args: (VimKey, CSTMotion)) {
        let (key, expectedMotion) = args
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        spy.cstNavigateCalls.removeAll()

        _ = c.handle(key)

        #expect(spy.cstNavigateCalls == [.init(motion: expectedMotion, count: 1)])
        #expect(c.mode == .visualCST, "still in visualCST after navigation")
    }

    @Test("a count digit prefixes a sibling slide (3j → cstNavigate(.nextSibling, 3))")
    func countPrefixesSiblingSlide() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        spy.cstNavigateCalls.removeAll()

        _ = c.handle(.char("3"))
        _ = c.handle(.char("j"))

        #expect(spy.cstNavigateCalls == [.init(motion: .nextSibling, count: 3)])
    }

    @Test(
        "J / K extend the selection via extendCSTSelection",
        arguments: [
            (VimKey.char("J"), CSTMotion.nextSibling),
            (.char("K"), .previousSibling),
        ] as [(VimKey, CSTMotion)]
    )
    func extendDispatchesMotion(_ args: (VimKey, CSTMotion)) {
        let (key, expectedMotion) = args
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        spy.extendCalls.removeAll()

        _ = c.handle(key)

        #expect(spy.extendCalls == [.init(motion: expectedMotion, count: 1)])
        #expect(c.mode == .visualCST)
    }

    @Test("o swaps anchor/head via swapCSTEnds")
    func oSwapsEnds() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char("o"))

        #expect(spy.swapCSTEndsCallCount == 1)
        #expect(c.mode == .visualCST)
    }

    // MARK: - Typed descent (f / F)

    @Test("f arms pending findKindForward")
    func fArmsPendingFindForward() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char("f"))

        #expect(c.pendingCharArgument == .findKindForward)
    }

    @Test("F arms pending findKindBackward")
    func FArmsPendingFindBackward() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char("F"))

        #expect(c.pendingCharArgument == .findKindBackward)
    }

    @Test("f then valid letter dispatches cstFindKind to the delegate")
    func fThenLetterDispatchesCSTFindKind() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        spy.findKindCalls.removeAll()

        _ = c.handle(.char("f"))
        _ = c.handle(.char("h"))

        #expect(spy.findKindCalls == [
            .init(direction: .forward, kind: .heading, count: 1)
        ])
        #expect(c.pendingCharArgument == nil, "pending cleared after dispatch")
    }

    @Test("pending find drops an unmapped letter without dispatching")
    func pendingFindIgnoresInvalidLetter() {
        let c = VimController()
        let spy = CSTSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        spy.findKindCalls.removeAll()

        _ = c.handle(.char("f"))
        _ = c.handle(.char("q"))  // q is not in the letter mnemonic table

        #expect(spy.findKindCalls.isEmpty)
        #expect(c.pendingCharArgument == nil, "pending cleared even on invalid letter")
    }

    // MARK: - Mode classification

    @Test("isVisual includes .visualCST")
    func isVisualIncludesCST() {
        #expect(VimMode.visualCST.isVisual)
        #expect(VimMode.slot.isVisual == false)
    }
}

enum VisualOp { case yank, delete, change }

@MainActor
private final class CSTSpy: VimControllerDelegate {
    struct CSTNavigateCall: Equatable {
        let motion: CSTMotion
        let count: Int
    }

    struct FindKindCall: Equatable {
        let direction: FindDirection
        let kind: TypedDescentKind
        let count: Int
    }

    var enterCSTVisualModeCallCount = 0
    var cstNavigateCalls: [CSTNavigateCall] = []
    var extendCalls: [CSTNavigateCall] = []
    var swapCSTEndsCallCount = 0
    var yankSelectionCallCount = 0
    var deleteSelectionCallCount = 0
    var findKindCalls: [FindKindCall] = []
    var enterCSTSlotModeCalls: [CSTSlotSelector] = []
    var enterCSTSlotModeShouldSucceed = true
    var leaveCSTSlotModeCallCount = 0
    var leaveCSTSlotModeShouldSucceed = true
    var decayCSTSlotToInsertCallCount = 0
    var decayCSTSlotToInsertShouldSucceed = true
    var setCSTSlotMarkCalls: [Character] = []

    // Visual-CST methods the tests care about.
    func enterCSTVisualMode() { enterCSTVisualModeCallCount += 1 }
    func enterCSTSlotMode(selector: CSTSlotSelector) -> Bool {
        enterCSTSlotModeCalls.append(selector)
        return enterCSTSlotModeShouldSucceed
    }
    func leaveCSTSlotMode() -> Bool {
        leaveCSTSlotModeCallCount += 1
        return leaveCSTSlotModeShouldSucceed
    }
    func decayCSTSlotToInsert() -> Bool {
        decayCSTSlotToInsertCallCount += 1
        return decayCSTSlotToInsertShouldSucceed
    }
    func cstNavigate(_ motion: CSTMotion, count: Int) {
        cstNavigateCalls.append(.init(motion: motion, count: count))
    }
    func extendCSTSelection(_ motion: CSTMotion, count: Int) {
        extendCalls.append(.init(motion: motion, count: count))
    }
    func swapCSTEnds() { swapCSTEndsCallCount += 1 }
    func cstFindKind(direction: FindDirection, kind: TypedDescentKind, count: Int) {
        findKindCalls.append(.init(direction: direction, kind: kind, count: count))
    }

    // Required protocol methods we don't care about.
    func moveCursor(motion: CursorMotion, count: Int) {}
    func structuralMotion(_ motion: StructuralMotion, count: Int) {}
    func viewportMotion(_ motion: ViewportMotion, count: Int) {}
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {}
    func goToDefinitionAtCursor() {}
    func prepareForInsert(at position: InsertPosition) {}
    func enterVisualMode(kind: VisualKind) {}
    func yankSelection() { yankSelectionCallCount += 1 }
    func deleteSelection() { deleteSelectionCallCount += 1 }
    func paste(after: Bool) {}
    func toggleTaskAtCursor() {}
    func setMark(_ name: Character) {}
    func jumpToMark(_ name: Character) {}
    func setCSTSlotMark(letter: Character) {
        setCSTSlotMarkCalls.append(letter)
    }
}
