/// The editor's current modal state. Insert mode behaves like a stock
/// NSTextView; Normal mode suppresses typing and routes keys through the
/// `VimController`'s binding tree. Visual modes extend a selection from
/// an anchor cell as the cursor moves; the binding tree treats them as
/// peers of `.normal` for motion dispatch — *except* for `.visualCST`,
/// which is deliberately excluded from `motionAccepting` (its motions
/// are CST-structural, not text-cursor, and reusing h/j/k/l would
/// silently corrupt the forest selection by moving the text cursor away
/// from the forest's range).
public enum VimMode: Sendable, Equatable, Hashable {
    case normal
    case insert
    case visual         // v
    case visualLine     // V
    case visualBlock    // Ctrl-v
    case visualCST      // gC — selects CST forests (structural)
    case commandLine    // : — typed ex commands, returns to prior mode on Enter/Esc
}

extension VimMode {
    /// True for any of the four visual variants. Used by the
    /// Coordinator's cursor-placement chokepoint to pick the
    /// extend-selection path over set-cursor, and by the mode-leave
    /// observer to clear all selection state on transition to a
    /// non-visual mode. `.commandLine` is intentionally false — it's
    /// a transient interrupt that returns to the prior mode (see the
    /// Coordinator's mode observer for the special-case that preserves
    /// visual state during a `:` round-trip).
    public var isVisual: Bool {
        switch self {
        case .visual, .visualLine, .visualBlock, .visualCST: return true
        case .normal, .insert, .commandLine: return false
        }
    }
}
