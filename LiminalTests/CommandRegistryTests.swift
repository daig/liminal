import Testing
@testable import Liminal

@Suite("CommandRegistry")
struct CommandRegistryTests {

    @Test("register + resolve by exact name returns the handler's result")
    func registerAndResolveByName() {
        let registry = CommandRegistry()
        registry.register(.init(
            name: "Echo",
            description: "test"
        ) { _, _ in .enterCSTVisualMode })

        let resolved = registry.resolve(name: "Echo", args: [], count: nil)
        #expect(resolved == .enterCSTVisualMode)
    }

    @Test("resolve of unknown name returns nil")
    func resolveUnknownNameReturnsNil() {
        let registry = CommandRegistry()
        #expect(registry.resolve(name: "Nope", args: [], count: nil) == nil)
    }

    @Test("args list is passed to the handler verbatim")
    func argsPassedToHandler() {
        let registry = CommandRegistry()
        // Handler returns .enterCSTVisualMode if args == ["alpha", "beta"],
        // .enterNormalMode otherwise — observed via the resolve result.
        registry.register(.init(
            name: "Sponge",
            description: "test"
        ) { args, _ in
            args == ["alpha", "beta"] ? .enterCSTVisualMode : .enterNormalMode
        })

        #expect(
            registry.resolve(name: "Sponge", args: ["alpha", "beta"], count: nil)
            == .enterCSTVisualMode
        )
        #expect(
            registry.resolve(name: "Sponge", args: ["other"], count: nil)
            == .enterNormalMode
        )
    }

    @Test("count is passed to the handler verbatim")
    func countPassedToHandler() {
        let registry = CommandRegistry()
        // Handler echoes count via the count parameter of cstNavigate.
        registry.register(.init(
            name: "Counter",
            description: "test"
        ) { _, count in
            .cstNavigate(.nextSibling, count: count ?? -1)
        })

        let resolved = registry.resolve(name: "Counter", args: [], count: 42)
        #expect(resolved == .cstNavigate(.nextSibling, count: 42))

        let noCount = registry.resolve(name: "Counter", args: [], count: nil)
        #expect(noCount == .cstNavigate(.nextSibling, count: -1))
    }

    @Test("default registry has every CST-aware command")
    func defaultRegistryHasAllCSTCommands() {
        let registry = VimController.defaultCommands()
        let expected: Set<String> = [
            // Original 13
            "CSTEnter",
            "CSTParent", "CSTFirstChild",
            "CSTNextSibling", "CSTPreviousSibling",
            "CSTExtendForward", "CSTExtendBackward",
            "CSTSwapEnds",
            "CSTFind", "CSTFindLast",
            "CSTPasteBlock", "CSTPasteSplice", "CSTPasteNest",
            "ToggleTask",
            // Added in the trivial-wiring slice
            "CSTFirstSibling", "CSTLastSibling",
            "Undo", "Redo",
            "CSTYank", "CSTDelete", "CSTChange",
            "CSTGlobalFind", "CSTGlobalFindLast",
            "CSTAncestor", "CSTDescendant",
            "CSTKindRunForward", "CSTKindRunBackward",
            // Added in slice B
            "CSTNextSiblingHeading", "CSTPreviousSiblingHeading",
            "CSTNextDeeperHeading", "CSTPreviousDeeperHeading",
            "CSTNextShallowerHeading", "CSTPreviousShallowerHeading",
            "CSTNextBlock", "CSTPreviousBlock",
            "CSTLastChild",
            // Document endpoints — finishing the A/B slice
            "CSTDocumentStart", "CSTDocumentEnd",
            // Slice C — forest marks
            "CSTMark", "CSTJumpToMark", "CSTUnmark",
            // CST slot mode
            "CSTSlot", "CSTSlotMark",
            // Slice D — smart-expand / smart-narrow
            "CSTExpand", "CSTNarrow",
            // Slice E — ex / file commands
            "Write", "Quit", "Edit",
            // Slice G — iCloud Tier 2 (manual reload entry point)
            "Reload",
            // Slice H — remaining ex/file commands
            "WriteAs", "OpenVault",
        ]
        let actual = Set(registry.commandNames())
        #expect(expected.isSubset(of: actual),
                "missing commands: \(expected.subtracting(actual))")
    }

    // MARK: - New commands' dispatch shapes

    @Test("CST paste commands dispatch explicit structural paste modes")
    func cstPasteCommandsDispatch() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTPasteBlock", args: [], count: nil)
            == .pasteCSTBlock(after: true)
        )
        #expect(
            registry.resolve(name: "CSTPasteSplice", args: [], count: nil)
            == .pasteCSTSplice(after: true)
        )
        #expect(
            registry.resolve(name: "CSTPasteNest", args: [], count: nil)
            == .pasteCSTNest(after: true)
        )
    }

    @Test("CSTFirstSibling / CSTLastSibling produce saturating sibling navigates")
    func siblingEndpointsSaturate() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTFirstSibling", args: [], count: nil)
            == .cstNavigate(.previousSibling, count: .max)
        )
        #expect(
            registry.resolve(name: "CSTLastSibling", args: [], count: nil)
            == .cstNavigate(.nextSibling, count: .max)
        )
    }

    @Test("Undo / Redo thread count through their dispatched VimCommand")
    func undoRedoThreadCount() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "Undo", args: [], count: 3)
            == .undo(count: 3)
        )
        #expect(
            registry.resolve(name: "Redo", args: [], count: nil)
            == .redo(count: 1)
        )
    }

    @Test("CSTYank / CSTDelete / CSTChange resolve to the visual-operator commands")
    func visualOperatorsExposed() {
        let registry = VimController.defaultCommands()
        #expect(registry.resolve(name: "CSTYank", args: [], count: nil) == .yankSelection)
        #expect(registry.resolve(name: "CSTDelete", args: [], count: nil) == .deleteSelection)
        #expect(registry.resolve(name: "CSTChange", args: [], count: nil) == .changeSelection)
    }

    @Test("CSTGlobalFind dispatches a global-preorder cstMove with .containingAny(kind)")
    func globalFindUsesPreorderForward() {
        let registry = VimController.defaultCommands()
        let resolved = registry.resolve(name: "CSTGlobalFind", args: ["heading"], count: nil)
        #expect(resolved == .cstMove(
            descriptor: .init(
                axis: .preorder,
                direction: .forward,
                predicate: .containingAny(.heading),
                count: 1
            ),
            extending: false
        ))
    }

    @Test("CSTGlobalFindLast dispatches preorder backward")
    func globalFindLastUsesPreorderBackward() {
        let registry = VimController.defaultCommands()
        let resolved = registry.resolve(name: "CSTGlobalFindLast", args: ["code"], count: 2)
        #expect(resolved == .cstMove(
            descriptor: .init(
                axis: .preorder,
                direction: .backward,
                predicate: .containingAny(.code),
                count: 2
            ),
            extending: false
        ))
    }

    @Test("CSTAncestor dispatches ancestor-axis cstMove with the kind predicate")
    func ancestorByKindShape() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTAncestor", args: ["heading"], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .ancestor,
                    direction: .forward,
                    predicate: .containingAny(.heading),
                    count: 1
                ),
                extending: false
            )
        )
    }

    @Test("CSTDescendant dispatches descendant-axis cstMove with the kind predicate")
    func descendantByKindShape() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTDescendant", args: ["wikilink"], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .descendant,
                    direction: .forward,
                    predicate: .containingAny(.wikilinkRef),
                    count: 1
                ),
                extending: false
            )
        )
    }

    @Test("CSTKindRunForward dispatches sibling+differentFrom(.all)")
    func kindRunForwardShape() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTKindRunForward", args: [], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .sibling,
                    direction: .forward,
                    predicate: .differentFrom(.all),
                    count: 1
                ),
                extending: false
            )
        )
    }

    @Test("CSTKindRunBackward symmetric to forward")
    func kindRunBackwardShape() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTKindRunBackward", args: [], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .sibling,
                    direction: .backward,
                    predicate: .differentFrom(.all),
                    count: 1
                ),
                extending: false
            )
        )
    }

    @Test("heading-level commands dispatch cstMove with the right level match")
    func headingLevelCommandShapes() {
        let registry = VimController.defaultCommands()
        let cases: [(name: String, direction: ForestMotion.Direction, match: ForestMotion.HeadingLevelMatch)] = [
            ("CSTNextSiblingHeading",         .forward,  .sameAsStart),
            ("CSTPreviousSiblingHeading",     .backward, .sameAsStart),
            ("CSTNextDeeperHeading",          .forward,  .deeperThanStart),
            ("CSTPreviousDeeperHeading",      .backward, .deeperThanStart),
            ("CSTNextShallowerHeading",       .forward,  .shallowerThanStart),
            ("CSTPreviousShallowerHeading",   .backward, .shallowerThanStart),
        ]
        for (name, direction, match) in cases {
            let resolved = registry.resolve(name: name, args: [], count: nil)
            #expect(resolved == .cstMove(
                descriptor: .init(
                    axis: .preorder,
                    direction: direction,
                    predicate: .headingLevel(match),
                    count: 1
                ),
                extending: false
            ), "wrong dispatch for \(name)")
        }
    }

    @Test("CSTNextBlock / CSTPreviousBlock dispatch cstBlockPeer")
    func blockPeerCommands() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTNextBlock", args: [], count: nil)
            == .cstBlockPeer(direction: .forward, extending: false)
        )
        #expect(
            registry.resolve(name: "CSTPreviousBlock", args: [], count: nil)
            == .cstBlockPeer(direction: .backward, extending: false)
        )
    }

    @Test("CSTDocumentStart / CSTDocumentEnd dispatch cstDocumentEndpoint")
    func documentEndpointCommands() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTDocumentStart", args: [], count: nil)
            == .cstDocumentEndpoint(end: .start, extending: false)
        )
        #expect(
            registry.resolve(name: "CSTDocumentEnd", args: [], count: nil)
            == .cstDocumentEndpoint(end: .end, extending: false)
        )
    }

    @Test("CSTLastChild dispatches descendant-backward (one AST level)")
    func lastChildCommand() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTLastChild", args: [], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .descendant,
                    direction: .backward,
                    predicate: .any,
                    count: 1
                ),
                extending: false
            )
        )
    }

    @Test("global / ancestor / descendant commands surface the kind argSpec for popup completion")
    func motionByKindCommandsHaveKindArgSpec() {
        let registry = VimController.defaultCommands()
        for name in ["CSTGlobalFind", "CSTGlobalFindLast", "CSTAncestor", "CSTDescendant"] {
            let cmd = try! #require(registry.command(named: name))
            switch cmd.argSpec {
            case .single(let label, let options):
                #expect(label == "kind")
                #expect(options.count == 9, "expected the full 9-kind option list for \(name)")
            case .none:
                Issue.record("\(name) should have .single argSpec, not .none")
            case .dynamicSingle:
                Issue.record("\(name) should have .single argSpec, not .dynamicSingle")
            }
        }
    }

    @Test("CSTMark argSpec lists all 52 letters (a-z + A-Z)")
    func cstMarkArgSpecListsAllLetters() throws {
        let registry = VimController.defaultCommands()
        let cmd = try #require(registry.command(named: "CSTMark"))
        switch cmd.argSpec {
        case .single(let label, let options):
            #expect(label == "letter")
            #expect(options.count == 52, "expected 26 lowercase + 26 uppercase letter options")
            #expect(options.contains(where: { $0.value == "a" }))
            #expect(options.contains(where: { $0.value == "Z" }))
        case .none, .dynamicSingle:
            Issue.record("CSTMark should have .single argSpec with letter options")
        }
    }

    @Test("CSTJumpToMark and CSTUnmark use .dynamicSingle for their options")
    func jumpAndUnmarkUseDynamicSingle() throws {
        let registry = VimController.defaultCommands()
        for name in ["CSTJumpToMark", "CSTUnmark"] {
            let cmd = try #require(registry.command(named: name))
            switch cmd.argSpec {
            case .dynamicSingle(let label):
                #expect(label == "mark", "expected dynamic label 'mark' for \(name)")
            case .single, .none:
                Issue.record("\(name) should have .dynamicSingle argSpec")
            }
        }
    }

    @Test("CSTMark handler dispatches setForestMark with the letter")
    func cstMarkHandlerDispatches() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTMark", args: ["a"], count: nil)
            == .setForestMark(letter: "a")
        )
        // Non-letter arg → handler returns nil → registry returns nil.
        #expect(registry.resolve(name: "CSTMark", args: ["1"], count: nil) == nil)
    }

    @Test("CSTSlot handler dispatches all four slot selectors")
    func cstSlotHandlerDispatches() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTSlot", args: ["prepend"], count: nil)
            == .enterCSTSlotMode(selector: .prepend)
        )
        #expect(
            registry.resolve(name: "CSTSlot", args: ["append"], count: nil)
            == .enterCSTSlotMode(selector: .append)
        )
        #expect(
            registry.resolve(name: "CSTSlot", args: ["before"], count: nil)
            == .enterCSTSlotMode(selector: .before)
        )
        #expect(
            registry.resolve(name: "CSTSlot", args: ["after"], count: nil)
            == .enterCSTSlotMode(selector: .after)
        )
        #expect(registry.resolve(name: "CSTSlot", args: ["middle"], count: nil) == nil)
    }

    @Test("CSTSlot and CSTSlotMark expose static arg options")
    func cstSlotCommandsExposeArgOptions() throws {
        let registry = VimController.defaultCommands()

        let slot = try #require(registry.command(named: "CSTSlot"))
        switch slot.argSpec {
        case .single(let label, let options):
            #expect(label == "selector")
            #expect(options.map(\.value) == ["prepend", "append", "before", "after"])
        case .none, .dynamicSingle:
            Issue.record("CSTSlot should have .single selector options")
        }

        let mark = try #require(registry.command(named: "CSTSlotMark"))
        switch mark.argSpec {
        case .single(let label, let options):
            #expect(label == "letter")
            #expect(options.count == 52)
            #expect(options.contains(where: { $0.value == "a" }))
            #expect(options.contains(where: { $0.value == "Z" }))
        case .none, .dynamicSingle:
            Issue.record("CSTSlotMark should have .single letter options")
        }
    }

    @Test("CSTSlotMark handler dispatches setCSTSlotMark with the letter")
    func cstSlotMarkHandlerDispatches() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTSlotMark", args: ["Z"], count: nil)
            == .setCSTSlotMark(letter: "Z")
        )
        #expect(registry.resolve(name: "CSTSlotMark", args: ["1"], count: nil) == nil)
    }

    @Test("CSTJumpToMark handler dispatches jumpToForestMark with the letter")
    func cstJumpToMarkHandlerDispatches() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTJumpToMark", args: ["B"], count: nil)
            == .jumpToForestMark(letter: "B")
        )
    }

    @Test("CSTUnmark handler dispatches unsetForestMark with the letter")
    func cstUnmarkHandlerDispatches() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTUnmark", args: ["m"], count: nil)
            == .unsetForestMark(letter: "m")
        )
    }

    @Test("Write / Quit / Reload dispatch the ex-file VimCommands without args")
    func exFileNoArgCommandsDispatch() {
        let registry = VimController.defaultCommands()
        #expect(registry.resolve(name: "Write", args: [], count: nil) == .writeCurrentFile)
        #expect(registry.resolve(name: "Quit", args: [], count: nil) == .quitCurrent)
        #expect(registry.resolve(name: "Reload", args: [], count: nil) == .reloadCurrentFile)
    }

    @Test("Edit dispatches editPath with the typed path arg")
    func editCommandDispatchesPath() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "Edit", args: ["foo/bar"], count: nil)
            == .editPath(path: "foo/bar")
        )
        // Empty arg returns nil so the literal-text fallback doesn't
        // dispatch an empty path.
        #expect(registry.resolve(name: "Edit", args: [""], count: nil) == nil)
        #expect(registry.resolve(name: "Edit", args: [], count: nil) == nil)
    }

    @Test("WriteAs dispatches writeAsPath with the typed path arg")
    func writeAsCommandDispatchesPath() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "WriteAs", args: ["foo/bar"], count: nil)
            == .writeAsPath(path: "foo/bar")
        )
        #expect(registry.resolve(name: "WriteAs", args: [""], count: nil) == nil)
        #expect(registry.resolve(name: "WriteAs", args: [], count: nil) == nil)
    }

    @Test("OpenVault accepts an empty path (panel without pre-fill) and a typed path")
    func openVaultCommandDispatchesPath() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "OpenVault", args: ["/Users/x/vault"], count: nil)
            == .openVaultPath(path: "/Users/x/vault")
        )
        #expect(
            registry.resolve(name: "OpenVault", args: [], count: nil)
            == .openVaultPath(path: "")
        )
    }

    @Test("WriteAs and OpenVault use .dynamicSingle argSpec for free-form path input")
    func writeAsAndOpenVaultUseDynamicSingle() throws {
        let registry = VimController.defaultCommands()
        for name in ["WriteAs", "OpenVault"] {
            let cmd = try #require(registry.command(named: name))
            switch cmd.argSpec {
            case .dynamicSingle(let label):
                #expect(label == "path", "expected dynamic label 'path' for \(name)")
            case .single, .none:
                Issue.record("\(name) should have .dynamicSingle argSpec")
            }
        }
    }

    @Test("Edit uses .dynamicSingle so the popup arg stage shows no static options")
    func editUsesDynamicSingleArgSpec() throws {
        let registry = VimController.defaultCommands()
        let cmd = try #require(registry.command(named: "Edit"))
        switch cmd.argSpec {
        case .dynamicSingle(let label):
            #expect(label == "path")
        case .single, .none:
            Issue.record("Edit should have .dynamicSingle argSpec for free-form path input")
        }
    }

    @Test("CSTExpand / CSTNarrow thread count through their dispatched VimCommand")
    func smartExpandNarrowThreadCount() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTExpand", args: [], count: nil)
            == .cstExpand(count: 1)
        )
        #expect(
            registry.resolve(name: "CSTExpand", args: [], count: 3)
            == .cstExpand(count: 3)
        )
        #expect(
            registry.resolve(name: "CSTNarrow", args: [], count: nil)
            == .cstNarrow(count: 1)
        )
        #expect(
            registry.resolve(name: "CSTNarrow", args: [], count: 4)
            == .cstNarrow(count: 4)
        )
    }

    @Test("CSTFind handler parses the kind arg into the right VimCommand")
    func cstFindArgParsesKindName() {
        let registry = VimController.defaultCommands()
        let resolved = registry.resolve(name: "CSTFind", args: ["heading"], count: nil)
        #expect(resolved == .cstFindKind(direction: .forward, kind: .heading, count: 1))

        // Unknown kind name → handler returns nil → registry returns nil.
        let unknown = registry.resolve(name: "CSTFind", args: ["nonsense"], count: nil)
        #expect(unknown == nil)
    }

    @Test("CSTFindLast threads count through the handler")
    func cstFindLastCountThreaded() {
        let registry = VimController.defaultCommands()
        let resolved = registry.resolve(
            name: "CSTFindLast", args: ["wikilink"], count: 5
        )
        #expect(resolved == .cstFindKind(direction: .backward, kind: .wikilink, count: 5))
    }
}
