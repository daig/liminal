/// A resolved command from the binding tree. Commands are values, not
/// closures — the interpreter on `VimController` switches over them and
/// invokes the relevant delegate or internal helper. Adding new commands
/// is just adding a case here and a binding entry.
public enum VimCommand: Sendable, Equatable {
    case enterInsertMode(at: InsertPosition)
    case enterNormalMode
    case enterVisualMode(VisualKind)

    /// `y` in visual: copy selection to system clipboard, return to
    /// normal at the start of the previous selection.
    case yankSelection
    /// `d` in visual: yank then delete; return to normal at the
    /// position the selection used to start.
    case deleteSelection
    /// `c` in visual: delete the selection then enter insert mode
    /// at the deletion site.
    case changeSelection
    /// `p` / `P` in normal: paste from system clipboard. `after`
    /// distinguishes `p` (after cursor / below line) from `P`.
    case paste(after: Bool)
    case moveCursor(CursorMotion, count: Int)
    case structuralMotion(StructuralMotion, count: Int)
    case viewportMotion(ViewportMotion, count: Int)
    case displayLineMotion(DisplayLineMotion, count: Int)
    case toggleTaskAtCursor

    /// `gd`: navigate to the definition of the reference at cursor
    /// (Cmd-click semantics, but keyboard-driven). The Coordinator
    /// reuses the existing `CmdClickHandler` activation flow, which
    /// handles every reference kind including external URLs (so
    /// there's no separate `gx` — `gd` opens URLs too).
    case goToDefinitionAtCursor

    // Marks. `awaitMarkName` arms the char-argument-pending state; the
    // next keypress is consumed as the mark name and dispatched as
    // `setMark` or `jumpToMark`.
    case awaitMarkName(MarkOp)
    case setMark(Character)
    case jumpToMark(Character)

    /// `d` / `c` / `y` in normal: arm the operator-pending state. The
    /// dispatch interceptor consumes the next motion (or doubled
    /// operator) into a single `.applyOperator` and routes that to the
    /// delegate; this case itself never reaches the delegate. The
    /// `preCount` carries any digit count typed before the operator
    /// (`3d` → preCount = 3). Default 1.
    case enterPendingOperator(VimOperator, preCount: Int)

    /// Resolved operator + target + count. Dispatched both by the
    /// operator-pending interceptor (after `dw` / `dd` / `cw` / etc.)
    /// and by the single-key shortcuts (`x` / `X` / `D` / `C` / `Y`).
    /// The delegate is responsible for materializing the range and
    /// applying the edit.
    case applyOperator(VimOperator, target: OperatorTarget, count: Int)

    /// Vim's `u` — walk back `count` snapshots in the CST-aware
    /// undo history.
    case undo(count: Int)
    /// Vim's `<C-r>` — walk forward `count` snapshots.
    case redo(count: Int)
}

/// Vim's three text-mutating operators. Indent / case / format
/// operators are deliberately absent from v1 (they have a different
/// output type — whitespace, casing, layout — and warrant their own
/// `OperatorRange.Result` shape).
public enum VimOperator: Sendable, Equatable, Hashable {
    case delete  // d / x / X / D
    case change  // c / C
    case yank    // y / Y

    /// Single-letter label surfaced in the status bar while the
    /// operator is pending (e.g. `"d"` after `d`).
    public var statusLabel: String {
        switch self {
        case .delete: return "d"
        case .change: return "c"
        case .yank:   return "y"
        }
    }
}

/// What an operator should consume — either a motion target (the
/// usual `dw` / `cb` / `y$` shape), or one of the canonical "implicit
/// target" shapes that vim collapses into a single keystroke
/// (`dd` / `x` / `D` / etc.).
public enum OperatorTarget: Sendable, Equatable, Hashable {
    /// Operator + motion (`dw`, `cb`, `y$`, ...). The delegate
    /// computes the motion target and builds a range from cursor →
    /// target subject to the motion's inclusivity.
    case motion(CursorMotion)
    /// Operator + display-line motion (`dgj`, `cg$`, ...).
    case displayLineMotion(DisplayLineMotion)
    /// Operator + structural motion (`d]]`, `cgh`, ...).
    case structuralMotion(StructuralMotion)
    /// Operator + viewport motion (`dH`, `dL`, ...).
    case viewportMotion(ViewportMotion)
    /// Doubled operator (`dd` / `cc` / `yy`) — count is the number of
    /// lines starting at the cursor's line.
    case currentLine
    /// `x` / `X` — the count chars at the cursor (or before it).
    case charsAtCursor(before: Bool)
    /// `D` / `C` — from the cursor to line content end.
    case toLineEnd
}

public enum MarkOp: Sendable, Equatable, Hashable {
    case set
    case jump
}

/// Which visual-mode flavor to enter. Each maps 1:1 to a VimMode
/// case (`.visual` / `.visualLine` / `.visualBlock`).
public enum VisualKind: Sendable, Equatable, Hashable {
    case charwise   // v
    case linewise   // V
    case blockwise  // Ctrl-v
}

/// Where to position the cursor (and which preliminary edit, if
/// any, to apply) when entering insert mode. Vim's `i` / `I` /
/// `a` / `A` / `o` / `O` / `s` / `S` map onto these.
public enum InsertPosition: Sendable, Equatable, Hashable {
    case atCursor              // i
    case afterCursor           // a
    case atLineFirstNonBlank   // I
    case atLineEnd             // A
    case openLineBelow         // o
    case openLineAbove         // O
    case substituteChar        // s
    case substituteLine        // S
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

    // Heading-aware motions backed by `DocumentIndex.headings`.
    case enclosingHeading      // `gh`
    case previousHeading       // `[[`
    case nextHeading           // `]]`

    // Reference-aware motions backed by `DocumentIndex.references`.
    case previousReference     // `[r`
    case nextReference         // `]r`
}

/// Cursor motions whose target depends on the visible viewport, not
/// the document text. Vim's `H` / `M` / `L` jump to the top / middle
/// / bottom line currently on screen. Dispatched via a delegate
/// hop (like `StructuralMotion`) so the coordinator can read the
/// layout manager's visible glyph range.
public enum ViewportMotion: Sendable, Equatable, Hashable {
    case screenTop      // `H`
    case screenMiddle   // `M`
    case screenBottom   // `L`
}

/// Cursor motions whose target depends on visual line layout, not
/// logical (newline-delimited) source lines. Vim's `g`-prefixed
/// motions navigate by display row — the row your eye sees after
/// soft-wrap — instead of by source line. Dispatched via a delegate
/// hop because `NSLayoutManager` owns the layout truth.
///
/// These are *visual*, not structural: the CST doesn't know about
/// soft-wrap geometry, so there's no CST-aware reinterpretation
/// that would feel like the same command. Future `g`-prefix
/// commands can layer CST awareness (e.g., `gp` for parent block,
/// `gd` for go-to-definition) as separate motions.
public enum DisplayLineMotion: Sendable, Equatable, Hashable {
    case down            // `gj`
    case up              // `gk`
    case start           // `g0`
    case firstNonBlank   // `g^`
    case end             // `g$`
}
