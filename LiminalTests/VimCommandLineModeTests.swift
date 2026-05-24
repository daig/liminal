import Testing
@testable import Liminal

@Suite("Vim command-line mode")
@MainActor
struct VimCommandLineModeTests {

    // MARK: - Entry

    @Test("colon from normal mode enters .commandLine and captures normal as return")
    func colonInNormalEntersCommandLine() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        #expect(c.mode == .commandLine)
        #expect(c.commandLineInput == "")
    }

    @Test("colon from .visualCST enters .commandLine with .visualCST as return mode")
    func colonInVisualCSTEntersCommandLine() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        // Enter visualCST via the binding tree.
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))
        #expect(c.mode == .visualCST)

        _ = c.handle(.char(":"))
        #expect(c.mode == .commandLine)
    }

    // MARK: - Input accumulation

    @Test("typed letters accumulate into commandLineInput")
    func lettersAccumulateInBuffer() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        _ = c.handle(.char("a"))
        _ = c.handle(.char("b"))
        _ = c.handle(.char("c"))
        #expect(c.commandLineInput == "abc")
    }

    @Test("backspace removes the last char of commandLineInput")
    func backspaceRemovesLastChar() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        for ch in "CSTE" { _ = c.handle(.char(ch)) }
        #expect(c.commandLineInput == "CSTE")
        _ = c.handle(.special(.backspace))
        #expect(c.commandLineInput == "CST")
    }

    @Test("backspace on empty buffer cancels and returns to prior mode")
    func backspaceOnEmptyCancels() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        _ = c.handle(.special(.backspace))
        #expect(c.mode == .normal)
        #expect(c.commandLineInput == "")
    }

    @Test("space is appended into the buffer (for arg separation)")
    func spaceIsAppended() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        for ch in "Foo" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.space))
        for ch in "bar" { _ = c.handle(.char(ch)) }
        #expect(c.commandLineInput == "Foo bar")
    }

    // MARK: - Exit (Enter / Esc)

    @Test("Esc clears the buffer and returns to prior mode without dispatching")
    func escClearsAndReturnsToPriorMode() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        for ch in "Foo" { _ = c.handle(.char(ch)) }

        _ = c.handle(.special(.escape))

        #expect(c.mode == .normal)
        #expect(c.commandLineInput == "")
        #expect(spy.swapCSTEndsCallCount == 0)
        #expect(spy.enterCSTVisualModeCallCount == 0)
    }

    @Test("Enter on a registered command dispatches via the registry")
    func enterDispatchesAndReturns() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy

        // Land in .visualCST first so :CSTSwapEnds has something
        // meaningful to do (delegate is called regardless of forest state).
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char(":"))
        for ch in "CSTSwapEnds" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.returnKey))

        #expect(spy.swapCSTEndsCallCount == 1)
        #expect(c.mode == .visualCST, "returns to prior mode after dispatch")
        #expect(c.commandLineInput == "")
    }

    @Test(":CSTPasteBlock dispatches structural block paste")
    func enterCSTPasteBlockDispatches() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy

        _ = c.handle(.char(":"))
        for ch in "CSTPasteBlock" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.returnKey))

        #expect(spy.pasteCSTBlockCalls == [true])
        #expect(c.mode == .normal)
    }

    @Test("Enter on an unknown command returns silently without dispatch")
    func enterWithUnknownCommandReturnsSilently() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        for ch in "Bogus" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.returnKey))

        #expect(c.mode == .normal)
        #expect(c.commandLineInput == "")
        #expect(spy.swapCSTEndsCallCount == 0)
    }

    @Test("Enter on empty input is a clean no-op")
    func enterOnEmptyInputIsNoOp() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        _ = c.handle(.special(.returnKey))

        #expect(c.mode == .normal)
        #expect(c.commandLineInput == "")
    }

    @Test(":CSTFind with kind arg dispatches cstFindKind to delegate")
    func enterCSTFindDispatchesFindKind() {
        let c = VimController()
        let spy = CommandLineSpy()
        c.delegate = spy
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char(":"))
        for ch in "CSTFind heading" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.returnKey))

        #expect(spy.findKindCalls == [
            CommandLineSpy.FindKindCall(
                direction: .forward, kind: .heading, count: 1
            )
        ])
        #expect(c.mode == .visualCST)
    }

    // MARK: - Mode classification

    @Test("count digits typed in .commandLine are accumulated as input, not as count")
    func commandLineNotInMotionAccepting() {
        let c = VimController()
        c.delegate = CommandLineSpy()
        _ = c.handle(.char(":"))
        _ = c.handle(.char("3"))
        // The "3" should be part of commandLineInput, NOT pendingCount.
        #expect(c.commandLineInput == "3")
        #expect(c.pendingCount == nil)
    }

    @Test("VimStatusPresentation.make for .commandLine carries commandLineInput")
    func commandLineInputAppearsInStatusPresentation() {
        let presentation = VimStatusPresentation.make(
            mode: .commandLine,
            pendingKeys: [],
            pendingCount: nil,
            commandLineInput: "CSTFind hea"
        )
        #expect(presentation.commandLineInput == "CSTFind hea")
        #expect(presentation.detailText == nil)
        #expect(presentation.mode == .commandLine)
    }
}

// MARK: - Spy

@MainActor
private final class CommandLineSpy: VimControllerDelegate {
    struct FindKindCall: Equatable {
        let direction: FindDirection
        let kind: TypedDescentKind
        let count: Int
    }

    var enterCSTVisualModeCallCount = 0
    var swapCSTEndsCallCount = 0
    var findKindCalls: [FindKindCall] = []
    var pasteCSTBlockCalls: [Bool] = []

    // Methods we observe.
    func enterCSTVisualMode() { enterCSTVisualModeCallCount += 1 }
    func swapCSTEnds() { swapCSTEndsCallCount += 1 }
    func cstFindKind(direction: FindDirection, kind: TypedDescentKind, count: Int) {
        findKindCalls.append(.init(direction: direction, kind: kind, count: count))
    }
    func pasteCSTBlock(after: Bool) { pasteCSTBlockCalls.append(after) }

    // Protocol stubs we don't care about.
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
    func toggleTaskAtCursor() {}
    func setMark(_ name: Character) {}
    func jumpToMark(_ name: Character) {}
    func cstNavigate(_ motion: CSTMotion, count: Int) {}
    func extendCSTSelection(_ motion: CSTMotion, count: Int) {}
}
