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
            "CSTEnter",
            "CSTParent", "CSTFirstChild",
            "CSTNextSibling", "CSTPreviousSibling",
            "CSTExtendForward", "CSTExtendBackward",
            "CSTSwapEnds",
            "CSTFind", "CSTFindLast",
            "CSTPasteSplice", "CSTPasteNest",
            "ToggleTask",
        ]
        let actual = Set(registry.commandNames())
        #expect(expected.isSubset(of: actual),
                "missing commands: \(expected.subtracting(actual))")
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
