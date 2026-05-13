/// The editor's current modal state. Insert mode behaves like a stock
/// NSTextView; Normal mode suppresses typing and routes keys through the
/// `VimController`'s binding tree. Visual modes extend a selection from
/// an anchor cell as the cursor moves; the binding tree treats them as
/// peers of `.normal` for motion dispatch.
public enum VimMode: Sendable, Equatable, Hashable {
    case normal
    case insert
    case visual         // v
    case visualLine     // V
    case visualBlock    // Ctrl-v
}

extension VimMode {
    /// True for any of the three visual variants. Used by the
    /// Coordinator's cursor-placement chokepoint to pick the
    /// extend-selection path over set-cursor.
    public var isVisual: Bool {
        switch self {
        case .visual, .visualLine, .visualBlock: return true
        case .normal, .insert: return false
        }
    }
}
