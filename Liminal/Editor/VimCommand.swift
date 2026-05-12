/// A resolved command from the binding tree. Commands are values, not
/// closures — the interpreter on `VimController` switches over them and
/// invokes the relevant delegate or internal helper. Adding new commands
/// is just adding a case here and a binding entry.
public enum VimCommand: Sendable, Equatable {
    case enterInsertMode
    case enterNormalMode
    case moveCursor(CursorMotion, count: Int)
    case structuralMotion(StructuralMotion, count: Int)
    case toggleTaskAtCursor
}

/// Cursor motions that don't change the document. Every case is
/// count-aware via the wrapping `.moveCursor(_:count:)` command; some
/// motions ignore the count (e.g., `.lineStart`), others repeat the
/// step (e.g., `.wordForwardStart`), and a few use the count as an
/// absolute target (e.g., `.documentStart` jumps to line N when
/// count > 0, line 1 otherwise).
public enum CursorMotion: Sendable, Equatable, Hashable {
    // Cardinal (count = repeat)
    case left
    case right
    case up
    case down

    // Line (count ignored for boundaries within the current line)
    case lineStart           // `0`
    case lineFirstNonBlank   // `^`
    case lineEnd             // `$`

    // Word (count = number of word boundaries to traverse)
    case wordForwardStart    // `w`
    case wordBackward        // `b`
    case wordForwardEnd      // `e`

    // Document (count = absolute line number; nil/zero falls back to default)
    case documentStart       // `gg` (default line 1)
    case documentEnd         // `G` (default last line)
}

public enum StructuralMotion: Sendable, Equatable, Hashable {
    case previousSibling
    case nextSibling
}
