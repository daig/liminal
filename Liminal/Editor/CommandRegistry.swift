/// A named, typed command resolvable from `:` mode input.
///
/// Commands are the canonical surface for CST-aware actions:
/// `:CSTEnter`, `:CSTFind heading`, `:CSTSwapEnds`, etc. Chord bindings
/// dispatch through the registry by name (via `VimCommand.executeNamedCommand`),
/// so adding a new command (or renaming one) doesn't require touching
/// chord wiring or the dispatch interpreter — just `defaultCommands()`.
///
/// The handler returns a `VimCommand` that the controller then dispatches
/// through its existing interpreter. Returning `nil` signals a parse
/// failure (unknown kind name, malformed args) — currently dropped
/// silently; future error surfacing is layered on top.
public struct LiminalCommand: Sendable {
    /// Vim-convention name: starts with a capital letter, no spaces.
    public let name: String

    /// Short human-readable description, shown in the command-line
    /// popup and (future) `:help`-style surfaces.
    public let description: String

    /// What argument(s) the command expects, drives the popup's
    /// argument-completion stage. `.none` for the majority of
    /// commands; structured options for ones with a fixed argument
    /// vocabulary (e.g. `:CSTFind <kind>`).
    public let argSpec: ArgSpec

    /// Resolves typed args + an optional count into a dispatchable
    /// `VimCommand`. Args are whitespace-split tokens after the command
    /// name; count is non-nil only when a chord shortcut supplied it
    /// (typing `:Foo 3` does NOT parse `3` as count in v1).
    public let handler: @Sendable ([String], Int?) -> VimCommand?

    public init(
        name: String,
        description: String,
        argSpec: ArgSpec = .none,
        handler: @escaping @Sendable ([String], Int?) -> VimCommand?
    ) {
        self.name = name
        self.description = description
        self.argSpec = argSpec
        self.handler = handler
    }
}

/// Describes what a `:` command expects after its name. Drives the
/// argument-completion stage of the popup. Kept narrow on purpose —
/// only `.single` is needed for the current CST-aware vocabulary;
/// multi-arg shapes can be added when a consumer demands them.
public enum ArgSpec: Sendable, Equatable {
    /// Command takes no arguments. Accepting it dispatches immediately.
    case none
    /// Command takes exactly one positional argument chosen from
    /// `options`. `label` is the human-readable name shown in the
    /// popup header (e.g. `"kind"` for `:CSTFind kind`).
    case single(label: String, options: [ArgOption])
}

/// One option in a `.single` argument spec.
public struct ArgOption: Sendable, Equatable {
    /// The string inserted into the input buffer / passed as the
    /// argument (e.g. `"heading"`).
    public let value: String
    /// Short human-readable description, shown next to the value in
    /// the popup (e.g. `"Headings (any level)"`).
    public let description: String

    public init(value: String, description: String) {
        self.value = value
        self.description = description
    }
}

/// Lookup table mapping `:` command names to `LiminalCommand`s. Owned by
/// `VimController`; populated via `VimController.defaultCommands()`.
///
/// Mutable so tests can register additional commands. Not `@MainActor`-
/// isolated — handlers are `@Sendable` so lookup is safe from any actor.
public final class CommandRegistry: @unchecked Sendable {
    private var commands: [String: LiminalCommand] = [:]

    public init() {}

    public func register(_ command: LiminalCommand) {
        commands[command.name] = command
    }

    /// Resolve a typed input into a dispatchable `VimCommand`. Returns
    /// `nil` if the name isn't registered or the handler rejects the
    /// args. The caller is responsible for whitespace-splitting the
    /// typed input into (name, args) — see `VimController.dispatchNamedCommand`.
    public func resolve(name: String, args: [String], count: Int?) -> VimCommand? {
        commands[name]?.handler(args, count)
    }

    /// All registered command names, alphabetized. Reserved for future
    /// tab-completion / `:help` surfaces.
    public func commandNames() -> [String] {
        commands.keys.sorted()
    }

    /// Look up a registered command by its exact name. Returns `nil`
    /// for unknown names; case-sensitive.
    public func command(named name: String) -> LiminalCommand? {
        commands[name]
    }

    /// All registered commands, in alphabetical order by name. Used by
    /// the command-line completion popup to enumerate candidates.
    public func allCommands() -> [LiminalCommand] {
        commands.keys.sorted().compactMap { commands[$0] }
    }
}
