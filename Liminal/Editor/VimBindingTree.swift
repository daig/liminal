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

    public func hints(after prefix: [VimKey], mode: VimMode) -> [HintEntry] {
        guard let root = rootsByMode[mode] else { return [] }
        var node = root
        for key in prefix {
            guard let next = node.children[key] else { return [] }
            node = next
        }
        return node.insertionOrderKeys.compactMap { key -> HintEntry? in
            guard let child = node.children[key] else { return nil }
            return HintEntry(key: key, description: child.terminalDescription)
        }
    }
}

extension VimBindingTree {
    public enum Resolution: Sendable, Equatable {
        case command(VimCommand)
        case partial
        case none
    }

    public struct HintEntry: Sendable, Equatable {
        public let key: VimKey
        /// Description of where this key leads — either the bound command's
        /// description if this key terminates, or "..." indicating more
        /// keys follow.
        public let description: String
    }
}

