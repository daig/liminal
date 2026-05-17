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

    /// Short human-readable description for `:help`-style surfaces (not
    /// yet displayed; reserved for future docs/hints).
    public let description: String

    /// Resolves typed args + an optional count into a dispatchable
    /// `VimCommand`. Args are whitespace-split tokens after the command
    /// name; count is non-nil only when a chord shortcut supplied it
    /// (typing `:Foo 3` does NOT parse `3` as count in v1).
    public let handler: @Sendable ([String], Int?) -> VimCommand?

    public init(
        name: String,
        description: String,
        handler: @escaping @Sendable ([String], Int?) -> VimCommand?
    ) {
        self.name = name
        self.description = description
        self.handler = handler
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
}
