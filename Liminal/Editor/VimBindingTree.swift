/// Lookup tree mapping `VimKey` sequences (per mode) to command
/// factories. The factory receives the current pending count (or nil) and
/// returns the dispatched `VimCommand`. Counts are accumulated by the
/// controller outside this tree.
///
/// The tree is per-mode: typing the same key sequence in Normal and
/// Insert can map to different commands. This slice's Insert table is
/// tiny (just `<Esc>` → `enterNormalMode`); future modes will register
/// their own subtrees.
public struct VimBindingTree {
    private final class Node {
        var commandFactory: (@Sendable (Int?) -> VimCommand)?
        var description: String?
        var children: [VimKey: Node] = [:]
        var insertionOrderKeys: [VimKey] = []

        /// What the user sees in the hint list for this node:
        /// the bound description if terminal; `"…"` if it's a prefix to
        /// further bindings; or empty if neither.
        var terminalDescription: String {
            if let d = description { return d }
            if !children.isEmpty { return "…" }
            return ""
        }
    }

    private var rootsByMode: [VimMode: Node] = [:]

    public init() {}

    /// Register a binding. Repeated calls with the same `(mode, sequence)`
    /// overwrite the previous binding.
    public mutating func bind(
        _ mode: VimMode,
        _ sequence: [VimKey],
        description: String,
        command: @escaping @Sendable (Int?) -> VimCommand
    ) {
        precondition(!sequence.isEmpty, "Cannot bind an empty key sequence")
        let root = rootsByMode[mode] ?? Node()
        rootsByMode[mode] = root

        var node = root
        for key in sequence {
            if let next = node.children[key] {
                node = next
            } else {
                let next = Node()
                node.children[key] = next
                node.insertionOrderKeys.append(key)
                node = next
            }
        }
        node.commandFactory = command
        node.description = description
    }

    public func resolve(_ keys: [VimKey], mode: VimMode, count: Int?) -> Resolution {
        guard !keys.isEmpty else { return .none }
        guard let root = rootsByMode[mode] else { return .none }

        var node = root
        for key in keys {
            guard let next = node.children[key] else { return .none }
            node = next
        }
        if let factory = node.commandFactory {
            return .command(factory(count))
        }
        if !node.children.isEmpty {
            return .partial
        }
        return .none
    }

    /// One terminal binding discovered by ``enumerateBindings(mode:)``.
    /// Used to build the chord-hint reverse map for the command-line
    /// completion popup.
    public struct EnumeratedBinding: Sendable {
        public let sequence: [VimKey]
        public let description: String?
        public let command: VimCommand
    }

    /// Depth-first walk of all terminal bindings registered for `mode`.
    /// Each terminal node's `commandFactory` is evaluated with `nil`
    /// count to produce a representative `VimCommand` (chord-shortcut
    /// bindings produce `.executeNamedCommand(...)`, which the caller
    /// matches on to build the reverse map).
    public func enumerateBindings(mode: VimMode) -> [EnumeratedBinding] {
        guard let root = rootsByMode[mode] else { return [] }
        var result: [EnumeratedBinding] = []
        walk(node: root, prefix: [], into: &result)
        return result
    }

    private func walk(
        node: Node,
        prefix: [VimKey],
        into result: inout [EnumeratedBinding]
    ) {
        if let factory = node.commandFactory {
            result.append(EnumeratedBinding(
                sequence: prefix,
                description: node.description,
                command: factory(nil)
            ))
        }
        for key in node.insertionOrderKeys {
            guard let child = node.children[key] else { continue }
            walk(node: child, prefix: prefix + [key], into: &result)
        }
    }

    public func hints(after prefix: [VimKey], mode: VimMode) -> [VimHintItem] {
        guard let root = rootsByMode[mode] else { return [] }
        var node = root
        for key in prefix {
            guard let next = node.children[key] else { return [] }
            node = next
        }
        return node.insertionOrderKeys.compactMap { key -> VimHintItem? in
            guard let child = node.children[key] else { return nil }
            let kind: VimHintItem.Kind = child.children.isEmpty ? .action : .group
            return VimHintItem(
                key: key,
                description: child.terminalDescription,
                kind: kind
            )
        }
    }
}

extension VimBindingTree {
    public enum Resolution: Sendable, Equatable {
        case command(VimCommand)
        case partial
        case none
    }

    /// Convenience for bindings that should resolve identically in
    /// multiple modes — typically motions, which are valid in
    /// `.normal` and any visual mode. Equivalent to a `bind` per
    /// mode but lets call sites express the cross-mode set once.
    public mutating func bindInModes(
        _ modes: [VimMode],
        _ sequence: [VimKey],
        description: String,
        command: @escaping @Sendable (Int?) -> VimCommand
    ) {
        for mode in modes {
            bind(mode, sequence, description: description, command: command)
        }
    }
}

extension VimMode {
    /// Modes that share normal mode's motion vocabulary. Visual
    /// modes use motions to extend the selection rather than place
    /// the cursor; the binding tree treats them as peers of
    /// `.normal` for motion dispatch.
    public static let motionAccepting: [VimMode] = [
        .normal, .visual, .visualLine, .visualBlock
    ]
}

