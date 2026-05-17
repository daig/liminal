import Testing
@testable import Liminal

/// End-to-end checks of the command-line popup driven through the
/// VimController: keystrokes go in, `commandLineCompletions` and
/// `commandLineHighlightedIndex` are observed, delegate spies confirm
/// the right `VimCommand` ends up dispatched.
@Suite("Command-line popup integration")
@MainActor
struct CommandLinePopupIntegrationTests {

    // MARK: - Entry + filter

    @Test("pressing : populates completions with ALL registered commands, no highlight")
    func enteringCommandLinePopulatesAllCommands() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))

        let registeredCount = VimController.defaultCommands().commandNames().count
        #expect(c.commandLineCompletions.count == registeredCount)
        #expect(c.commandLineHighlightedIndex == nil)
        // Every entry should have a non-empty display starting with ":".
        for entry in c.commandLineCompletions {
            #expect(entry.display.hasPrefix(":"))
        }
    }

    @Test("typing narrows the completion list to fuzzy-matching commands")
    func typingNarrowsCompletions() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        for ch in "cst" { _ = c.handle(.char(ch)) }
        // All CST commands match; ToggleTask doesn't contain c-s-t in order.
        #expect(c.commandLineCompletions.count >= 10)
        for entry in c.commandLineCompletions {
            #expect(entry.display.hasPrefix(":CST"),
                    "expected only CST-prefixed matches; saw \(entry.display)")
        }
        // First entry is highlighted as soon as the user starts typing.
        #expect(c.commandLineHighlightedIndex == 0)
    }

    @Test("typing a non-matching string leaves an empty completion list")
    func nonMatchingNarrowsToEmpty() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        for ch in "zzzz" { _ = c.handle(.char(ch)) }
        #expect(c.commandLineCompletions.isEmpty)
        #expect(c.commandLineHighlightedIndex == nil)
    }

    // MARK: - Navigation

    @Test("Down arrow moves highlight; wraps at end")
    func downArrowMovesHighlight() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        // Empty input → no highlight. Down lands on 0.
        _ = c.handle(.special(.down))
        #expect(c.commandLineHighlightedIndex == 0)
        _ = c.handle(.special(.down))
        #expect(c.commandLineHighlightedIndex == 1)
    }

    @Test("Up arrow moves highlight backward; wraps from no-highlight to last")
    func upArrowWrapsFromNoHighlight() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        let total = c.commandLineCompletions.count
        _ = c.handle(.special(.up))
        #expect(c.commandLineHighlightedIndex == total - 1)
    }

    @Test("Tab moves highlight down")
    func tabMovesHighlightDown() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        _ = c.handle(.special(.tab))
        #expect(c.commandLineHighlightedIndex == 0)
    }

    @Test("Shift-Tab moves highlight up")
    func shiftTabMovesHighlightUp() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        _ = c.handle(.special(.tab, modifiers: [.shift]))
        let total = c.commandLineCompletions.count
        #expect(c.commandLineHighlightedIndex == total - 1)
    }

    // MARK: - Dispatch via highlight

    @Test("Enter on a highlighted no-arg command dispatches the registered command")
    func enterOnHighlightedNoArgCommandDispatches() {
        let c = VimController()
        let spy = PopupSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        for ch in "swap" { _ = c.handle(.char(ch)) }
        // "swap" fuzzy-matches CSTSwapEnds — should be the first/only match.
        #expect(c.commandLineCompletions.first?.acceptValue == "CSTSwapEnds")
        _ = c.handle(.special(.returnKey))

        #expect(spy.swapCSTEndsCallCount == 1)
        #expect(c.mode == .normal)
        #expect(c.commandLineInput == "")
    }

    @Test("Enter on a highlighted command with args advances to arg stage instead of dispatching")
    func enterOnHighlightedArgCommandAdvancesToArgStage() {
        let c = VimController()
        let spy = PopupSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        for ch in "find" { _ = c.handle(.char(ch)) }
        // "find" matches both CSTFind and CSTFindLast; first highlighted.
        let highlighted = c.commandLineCompletions[c.commandLineHighlightedIndex!]
        #expect(highlighted.acceptValue == "CSTFind"
                || highlighted.acceptValue == "CSTFindLast",
                "expected a find variant first; saw \(highlighted.acceptValue)")

        _ = c.handle(.special(.returnKey))

        // Should still be in .commandLine, buffer = "CSTFind " (or "CSTFindLast ").
        #expect(c.mode == .commandLine)
        #expect(c.commandLineInput.hasSuffix(" "),
                "advance to arg stage should append a trailing space; saw \(c.commandLineInput)")
        // Completions should now be the arg options (kind list).
        let kinds = c.commandLineCompletions.map(\.acceptValue)
        #expect(kinds.contains("heading"))
        #expect(kinds.contains("code"))
        #expect(spy.findKindCalls.isEmpty,
                "should NOT have dispatched yet — we're in arg stage")
    }

    @Test("end-to-end :CSTFind heading via popup keystrokes")
    func endToEndCSTFindHeading() {
        let c = VimController()
        let spy = PopupSpy()
        c.delegate = spy
        // Enter visualCST first so cstFindKind has the right context
        // (the delegate doesn't actually check this, but it makes the
        // scenario realistic).
        _ = c.handle(.char("g"))
        _ = c.handle(.char("C"))

        _ = c.handle(.char(":"))
        for ch in "CSTFind" { _ = c.handle(.char(ch)) }
        // Enter advances to arg stage.
        _ = c.handle(.special(.returnKey))
        #expect(c.mode == .commandLine)

        for ch in "heading" { _ = c.handle(.char(ch)) }
        _ = c.handle(.special(.returnKey))

        #expect(spy.findKindCalls == [
            PopupSpy.FindKindCall(direction: .forward, kind: .heading, count: 1)
        ])
        #expect(c.mode == .visualCST)
    }

    @Test("Enter with no highlight (empty input) is a clean no-op")
    func enterWithNoHighlightIsNoOp() {
        let c = VimController()
        let spy = PopupSpy()
        c.delegate = spy
        _ = c.handle(.char(":"))
        _ = c.handle(.special(.returnKey))
        #expect(c.mode == .normal)
        #expect(spy.swapCSTEndsCallCount == 0)
    }

    // MARK: - Chord hints

    @Test("completions for chord-shortcutted commands carry the chord hint")
    func chordHintPopulatedForCSTEnter() {
        let c = VimController()
        c.delegate = PopupSpy()
        _ = c.handle(.char(":"))
        let cstEnter = c.commandLineCompletions.first { $0.acceptValue == "CSTEnter" }
        #expect(cstEnter != nil)
        #expect(cstEnter?.chordHint == "gC",
                "expected :CSTEnter to surface its gC chord; saw \(cstEnter?.chordHint ?? "nil")")
    }

    @Test("chordsForCommand returns the chord for a bound command")
    func chordsForBoundCommand() {
        let c = VimController()
        #expect(c.chordsForCommand(named: "CSTEnter") == ["gC"])
    }

    @Test("chordsForCommand returns empty for an unregistered name")
    func chordsForUnknownCommand() {
        let c = VimController()
        #expect(c.chordsForCommand(named: "DefinitelyNotBound") == [])
    }
}

// MARK: - Spy

@MainActor
private final class PopupSpy: VimControllerDelegate {
    struct FindKindCall: Equatable {
        let direction: FindDirection
        let kind: TypedDescentKind
        let count: Int
    }

    var swapCSTEndsCallCount = 0
    var findKindCalls: [FindKindCall] = []

    func swapCSTEnds() { swapCSTEndsCallCount += 1 }
    func cstFindKind(direction: FindDirection, kind: TypedDescentKind, count: Int) {
        findKindCalls.append(.init(direction: direction, kind: kind, count: count))
    }

    // Stubs.
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
    func enterCSTVisualMode() {}
    func cstNavigate(_ motion: CSTMotion, count: Int) {}
    func extendCSTSelection(_ motion: CSTMotion, count: Int) {}
}
