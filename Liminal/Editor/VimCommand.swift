/// A resolved command from the binding tree. Commands are values, not
/// closures — the interpreter on `VimController` switches over them and
/// invokes the relevant delegate or internal helper. Adding new commands
/// is just adding a case here and a binding entry.
public enum VimCommand: Sendable, Equatable {
    case enterInsertMode
    case enterNormalMode
    case moveCursor(MoveDirection, count: Int)
    case structuralMotion(StructuralMotion, count: Int)
    case toggleTaskAtCursor
}

public enum MoveDirection: Sendable, Equatable, Hashable {
    case left
    case right
    case up
    case down
}

public enum StructuralMotion: Sendable, Equatable, Hashable {
    case previousSibling
    case nextSibling
}
