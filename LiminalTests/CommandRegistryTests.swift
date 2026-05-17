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
            "CSTPasteSplice", "CSTPasteNest",
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
        ]
        let actual = Set(registry.commandNames())
        #expect(expected.isSubset(of: actual),
                "missing commands: \(expected.subtracting(actual))")
    }

    // MARK: - New commands' dispatch shapes

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

    @Test("CSTLastChild dispatches descendant-backward + excluding glueWrapper")
    func lastChildCommand() {
        let registry = VimController.defaultCommands()
        #expect(
            registry.resolve(name: "CSTLastChild", args: [], count: nil)
            == .cstMove(
                descriptor: .init(
                    axis: .descendant,
                    direction: .backward,
                    predicate: .excluding(.glueWrapper),
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
            }
        }
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
