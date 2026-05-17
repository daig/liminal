import Foundation

/// One step in the pending `:CSTNarrow` chain. After the user has
/// pressed `:CSTExpand` N times, the chain has N entries; the
/// next-to-pop entry has `ordinal == 1`.
///
/// Exists purely so the in-editor narrow-chain visualizer has
/// something serializable to render. The actual descent state lives
/// in `LiminalTextView.Coordinator.cstDescentStack` as raw
/// `[Int]` — this struct is the user-facing projection of it.
public struct NarrowChainEntry: Sendable, Equatable, Identifiable, Hashable {
    /// 1-indexed press count. Entry with ordinal 1 is consumed by
    /// the *next* `:CSTNarrow` press, ordinal 2 by the press after
    /// that, and so on.
    public let ordinal: Int

    /// User-facing kind name of the node that the corresponding
    /// `:CSTNarrow` press will land on (e.g. "Paragraph", "Inline
    /// Text"). Computed from the resolved forest at each step via
    /// `LiminalKind.displayName`.
    public let kindDisplay: String

    /// Raw full-child-index stored in the descent stack at this
    /// position. Surfaced for transparency — the visualizer exists to
    /// clear up "what's actually in memory" confusion, so we expose
    /// it directly.
    public let childIndex: Int

    public var id: Int { ordinal }

    public init(ordinal: Int, kindDisplay: String, childIndex: Int) {
        self.ordinal = ordinal
        self.kindDisplay = kindDisplay
        self.childIndex = childIndex
    }
}
