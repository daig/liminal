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
    /// Explicit target-intent paste: splice a compatible CST clipboard
    /// payload into a strict child-sequence target.
    case pasteCSTSplice(after: Bool)
    /// Explicit target-intent paste: nest a compatible CST clipboard
    /// payload inside a strict container target.
    case pasteCSTNest(after: Bool)
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

    // MARK: - Visual CST mode

    /// `gC` from normal: enter ``VimMode/visualCST`` at the current
    /// cursor. The delegate builds a ``LiminalForest`` covering the
    /// cursor (block-level entry) and mirrors it into the text view.
    case enterCSTVisualMode

    /// CST-structural motion that *slides* the forest selection to a
    /// new singleton in the named direction. The motion may be
    /// repeated `count` times; if any step has no successor the move
    /// stops at the last valid position rather than failing.
    case cstNavigate(CSTMotion, count: Int)

    /// CST-structural motion that *extends* the forest's head endpoint
    /// in the named direction, leaving the anchor fixed. Only
    /// `.nextSibling` / `.previousSibling` are meaningful here; the
    /// other cases are no-ops (extend doesn't make sense for parent
    /// or descend).
    case extendCSTSelection(CSTMotion, count: Int)

    /// Swap the forest's anchor and head endpoints. Vim's `o` in
    /// visual mode.
    case swapCSTEnds

    /// `f` / `F` in `.visualCST`: arm the pending char-argument state
    /// awaiting a letter that identifies a kind to search for inside
    /// the current forest's subtree.
    case awaitFindKind(direction: FindDirection)

    /// Resolved find chord after the letter argument: search the
    /// current forest's subtree for a forest matching `kind`. Forward
    /// returns the first match in preorder; backward returns the last.
    case cstFindKind(direction: FindDirection, kind: TypedDescentKind, count: Int)

    /// Generic forest-motion dispatch — used by every CST command
    /// that doesn't fit the fixed `CSTMotion` enum (e.g. global find,
    /// ancestor-by-kind, kind-runs, sibling endpoints). Carries an
    /// equatable `ForestMotion.Descriptor` instead of a full
    /// `ForestMotion` (which can't be Equatable because of `.custom`).
    case cstMove(descriptor: ForestMotion.Descriptor, extending: Bool)

    /// Block-peer hop. Ascends until the head is a `.blockItem` (if
    /// it isn't already), then slides to the next/previous `.blockItem`
    /// sibling. Backs `:CSTNextBlock` / `:CSTPreviousBlock` (the
    /// `}` / `{` family in the old proposal).
    case cstBlockPeer(direction: ForestMotion.Direction, extending: Bool)

    /// Descend to the LAST navigable child of the head. Mirrors
    /// `.cstNavigate(.firstChild, ...)` but lands on the last sibling.
    /// Backs `:CSTLastChild`.
    case cstLastChild(extending: Bool)

    // MARK: - Command-line mode

    /// `:` from normal / visual / .visualCST: flip the controller into
    /// `.commandLine` mode and start collecting a typed command. The
    /// prior mode is captured for return on Enter / Esc.
    case enterCommandLine

    /// Dispatched after `:` Enter (or by a chord shortcut). Looks up
    /// `name` in the `CommandRegistry`, passes `args` + `count`, and
    /// dispatches the returned `VimCommand`. Silently drops if the
    /// name is unregistered or the handler returns nil.
    case executeNamedCommand(name: String, args: [String], count: Int?)
}

/// Direction parameter for typed-descent chords (`f` vs `F`).
public enum FindDirection: Sendable, Equatable, Hashable {
    case forward
    case backward

    public var statusLabel: String {
        switch self {
        case .forward:  return "f"
        case .backward: return "F"
        }
    }
}

/// Kinds the `f` / `F` chord letter argument resolves to. Each maps to
/// a ``LiminalStructuralCategory`` predicate that the kernel applies
/// while walking the current subtree in preorder.
public enum TypedDescentKind: Sendable, Equatable, Hashable {
    case heading       // h
    case code          // c
    case math          // m
    case reference     // r — any reference (link, embed, wikilink, ...)
    case markdownLink  // l — mdLink + autolink
    case wikilink      // w
    case embed         // e
    case typedBlock    // k
    case blockAnchor   // b

    /// The category predicate the kernel will match against.
    public var category: LiminalStructuralCategory {
        switch self {
        case .heading:      return .heading
        case .code:         return .code
        case .math:         return .math
        case .reference:    return .reference
        case .markdownLink: return .link
        case .wikilink:     return .wikilinkRef
        case .embed:        return .embed
        case .typedBlock:   return .typed
        case .blockAnchor:  return .blockAnchor
        }
    }

    /// Resolve a single character to a typed-descent kind, or nil if
    /// the character isn't bound in the table.
    public init?(letter: Character) {
        switch letter {
        case "h": self = .heading
        case "c": self = .code
        case "m": self = .math
        case "r": self = .reference
        case "l": self = .markdownLink
        case "w": self = .wikilink
        case "e": self = .embed
        case "k": self = .typedBlock
        case "b": self = .blockAnchor
        default:  return nil
        }
    }

    /// Lowercase string identifier used as the `:CSTFind <kind>` arg.
    /// Round-trips through `init?(commandArgument:)`.
    public var commandArgument: String {
        switch self {
        case .heading:      return "heading"
        case .code:         return "code"
        case .math:         return "math"
        case .reference:    return "reference"
        case .markdownLink: return "markdownlink"
        case .wikilink:     return "wikilink"
        case .embed:        return "embed"
        case .typedBlock:   return "typedblock"
        case .blockAnchor:  return "blockanchor"
        }
    }

    /// Resolve a lowercase string identifier (the `:CSTFind` arg) to a
    /// kind. Returns nil for unknown names.
    public init?(commandArgument: String) {
        switch commandArgument {
        case "heading":      self = .heading
        case "code":         self = .code
        case "math":         self = .math
        case "reference":    self = .reference
        case "markdownlink": self = .markdownLink
        case "wikilink":     self = .wikilink
        case "embed":        self = .embed
        case "typedblock":   self = .typedBlock
        case "blockanchor":  self = .blockAnchor
        default:             return nil
        }
    }

    /// Argument options surfaced in the `:CSTFind` / `:CSTFindLast`
    /// completion popup. Order is the canonical display order.
    public static let argOptions: [ArgOption] = [
        .init(value: "heading",      description: "Headings (atxHeading kind)"),
        .init(value: "code",         description: "Code blocks and inline code spans"),
        .init(value: "math",         description: "Math blocks and inline math"),
        .init(value: "reference",    description: "Any reference (link, embed, wikilink, …)"),
        .init(value: "markdownlink", description: "Markdown-style links (mdLink, autolink)"),
        .init(value: "wikilink",     description: "Wikilinks ([[name]])"),
        .init(value: "embed",        description: "Embeds (images, wiki embeds, structured embeds)"),
        .init(value: "typedblock",   description: "Typed-construct family (typedBlock, typedInline, …)"),
        .init(value: "blockanchor",  description: "Block-id anchors (^name)"),
    ]
}

/// Structural motions specific to ``VimMode/visualCST``. Distinct from
/// ``StructuralMotion`` (which moves the text cursor in normal mode);
/// CST motions navigate the forest selection itself.
public enum CSTMotion: Sendable, Equatable, Hashable {
    /// Ascend: replace the forest with a singleton at its parent.
    case parent
    /// Descend: replace the forest with a singleton at the head's
    /// first navigable child. No-op when the head points at a token
    /// or at an opaque-policy parent.
    case firstChild
    /// Slide forward: next navigable sibling under the same parent.
    case nextSibling
    /// Slide backward: previous navigable sibling under the same parent.
    case previousSibling
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
