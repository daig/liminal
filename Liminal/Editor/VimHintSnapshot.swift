/// One row in the hint overlay: a key the user can press next, plus
/// the description of where that key leads. Equatable so view diffing
/// works; Sendable so snapshots can cross actor boundaries (the
/// controller's @Published values are read from SwiftUI's main-thread
/// rendering pipeline).
public struct VimHintItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Pressing this key fires a command. Description is the command's label.
        case action
        /// Pressing this key drills into another prefix. Description is the
        /// label of that prefix's purpose (or the auto-generated "…" placeholder
        /// when no explicit label is registered).
        case group
    }

    public let key: VimKey
    public let description: String
    public let kind: Kind

    public init(key: VimKey, description: String, kind: Kind = .action) {
        self.key = key
        self.description = description
        self.kind = kind
    }

    /// Stable identity for SwiftUI's `ForEach`. The key + description tuple
    /// is sufficient — bindings don't register two distinct items with the
    /// same key, and re-renders with the same key shouldn't change identity.
    public var id: String { "\(key.displayString)|\(description)" }
}

/// A snapshot of what the hint overlay should show at one instant. The
/// title surfaces the chord-prefix already pressed (e.g., `<Space>` or
/// `<Space>g`); the items list enumerates the next-key choices.
///
/// Built by the controller from `VimBindingTree.hints(after:mode:)` plus
/// formatted pending-keys, and gated by the hint-onset delay state
/// machine before being assigned to the published `visibleHintSnapshot`.
public struct VimHintSnapshot: Sendable, Equatable {
    public let title: String?
    public let items: [VimHintItem]

    public init(title: String? = nil, items: [VimHintItem]) {
        self.title = title
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
}
