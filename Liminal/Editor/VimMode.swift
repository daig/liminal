/// The editor's current modal state. Insert mode behaves like a stock
/// NSTextView; Normal mode suppresses typing and routes keys through the
/// `VimController`'s binding tree.
///
/// Visual modes (`character`, `line`) are reserved for the part-2 slice
/// that introduces selection-based operators and the anchor/head model.
/// Adding cases here is the only schema change required; the rest of the
/// vim infrastructure (binding tree, command interpreter) already
/// dispatches on a generic `VimMode`.
public enum VimMode: Sendable, Equatable, Hashable {
    case normal
    case insert
}
