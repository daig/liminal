# Liminal Navigation & Editing Spec v0.1 Draft

Status: draft for review

This document defines the navigation and editing interface for the Liminal
editor — vim-flavored modal editing extended with structure-aware motions,
text objects, and actions that consume the typed CST.

The interface inherits the reference implementation
(`liminal-prototype/Vim/`). Architecture, operator/motion/object grammar,
mode model, and standard bindings are intentionally preserved. The
*implementation* is being replaced from scratch on the Cambium-backed parser
infrastructure; the *interface* is being kept and extended in carefully
scoped ways called out as **§ Extension** throughout.

Normative words follow the syntax spec convention: **must**, **should**, **may**.

## 1. Scope

This spec covers:

- Editor modes (Normal, Insert, Visual character, Visual line).
- Motions and counts.
- Text objects.
- Operators.
- Structural extensions: `%` matching, `{` / `}` block motion, structural
  text objects, structural navigation actions.
- Marks and hints.

This spec does NOT cover:

- Rendering / highlighting (covered separately).
- Document-level commands (open, save, close — handled by the host
  document framework).
- Search/replace UI (handled by the host find bar; vim `/` and `?` motions
  do appear here as they affect the cursor).
- Vim's full ex-command surface (`:w`, `:set`, etc.) — out of scope; the
  editor is not a vim emulator beyond the modal core.

## 2. Goals and Non-Goals

### 2.1 Goals

- Preserve the muscle memory of vim users for character / word / line motions,
  operators, and text objects.
- Extend `{` / `}` and `%` so they navigate **typed CST structure** rather
  than raw blank lines or paired ASCII punctuation.
- Generalize the text-object idea to structural shapes: "the contents of
  this heading section," "this typed block's body," "this list item,"
  "this paragraph's inline content."
- Provide a small set of structural editing actions (heading promote /
  demote, task toggle, wrap in emphasis, etc.) that compose with the
  motion/object grammar where reasonable.

### 2.2 Non-Goals

- Not aiming for vim parity. ex-commands, marks beyond a–z, registers,
  macros (`q`), and recordings are out of scope unless explicitly added
  later.
- Not aiming for emacs-style chord-heavy bindings or for a leader-key
  ecosystem. The reference's hardcoded binding table is the model.
- Not aiming to expose every parser node kind as a navigable object —
  only the kinds that map cleanly to user intent ("section,"
  "block," "field," etc.).

## 3. Modes

Four modes; same as the reference.

| Mode | Enters via | Leaves via | Behavior |
|---|---|---|---|
| Normal | App launch, Esc, Cmd-[ | i, a, I, A, o, O, v, V | Motions move cursor; operators wait for motion/object |
| Insert | i, a, I, A, o, O | Esc, Ctrl-C | Keystrokes insert text; arrow keys move cursor |
| Visual (character) | v (from Normal); v (from Visual line toggles) | v, Esc, Cmd-[, operator | Motions extend a characterwise selection |
| Visual (line) | V (from Normal or Visual char) | V, Esc, Cmd-[, operator | Motions extend a linewise selection |

Mode indicator should be visible somewhere (status bar, cursor shape, or
both). The reference uses cursor shape; Liminal v0.1 **should** match.

### 3.1 Entry-from-Normal bindings

| Key | Action |
|---|---|
| `i` | Insert at cursor |
| `a` | Insert after cursor (cursor moves right one byte unless at line end) |
| `I` | Insert at first non-blank of current line |
| `A` | Insert at end of current line |
| `o` | Open new line below current; enter Insert |
| `O` | Open new line above current; enter Insert |
| `v` | Enter Visual (characterwise); anchor at current cursor |
| `V` | Enter Visual (linewise); anchor on current line |
| `s` | Delete character at cursor; enter Insert (= `cl`) |
| `S` | Delete current line; enter Insert (= `cc`) |
| `c<motion>` / `c<object>` | Delete range; enter Insert |
| `C` | Delete from cursor to line end; enter Insert (= `c$`) |

## 4. Motions

All motions accept a count prefix (`3w`, `5j`). Default count is 1.

Motions are categorized by what they reference:

### 4.1 Character / line

| Key(s) | Motion |
|---|---|
| `h` / Left | One byte left within line |
| `l` / Right | One byte right within line |
| `j` / Down | One logical line down, preserve column |
| `k` / Up | One logical line up, preserve column |
| `0` | First column of current line |
| `^` | First non-blank of current line |
| `$` | Last column of current line; with count, end of line `N-1` lines below |

### 4.2 Word

| Key | Motion |
|---|---|
| `w` | Start of next word |
| `W` | Start of next WORD (whitespace-delimited token) |
| `b` | Start of previous word |
| `B` | Start of previous WORD |
| `e` | End of current/next word |
| `E` | End of current/next WORD |
| `ge` | End of previous word |
| `gE` | End of previous WORD |

### 4.3 File

| Key | Motion |
|---|---|
| `gg` | First line, first non-blank. With count `Ngg`: line `N` |
| `G` | Last line, first non-blank. With count `NG`: line `N` |

### 4.4 In-line character search

| Key | Motion |
|---|---|
| `f<c>` | Forward to next occurrence of `c` on this line |
| `F<c>` | Backward to previous occurrence of `c` on this line |
| `t<c>` | Forward to just before next `c` on this line |
| `T<c>` | Backward to just after previous `c` on this line |
| `;` | Repeat last `f`/`F`/`t`/`T` in the same direction |
| `,` | Repeat last `f`/`F`/`t`/`T` in the opposite direction |

### 4.5 View-relative

These move within the visible viewport. Counts are interpreted as
"N-th line from the relevant edge" where applicable.

| Key | Motion |
|---|---|
| `H` | Top visible line, first non-blank. With count: `N`-th from top |
| `M` | Middle visible line |
| `L` | Bottom visible line. With count: `N`-th from bottom |
| Ctrl-U | Half-page up |
| Ctrl-D | Half-page down |
| Ctrl-B | Full-page up |
| Ctrl-F | Full-page down |
| `gj` | One screen line down (wrapped-aware) |
| `gk` | One screen line up (wrapped-aware) |
| `g0` | Start of screen line |
| `g^` | First non-blank of screen line |
| `g$` | End of screen line |
| `zt` | Scroll so current line is at top |
| `zz` | Scroll so current line is centered |
| `zb` | Scroll so current line is at bottom |

### 4.6 Block motion — **§ Extension: structure-aware `{` / `}`**

The reference uses blank-line boundaries for `{` / `}`. Liminal v0.1
**must** use the typed CST: each `{` / `}` jumps to the start of the
previous / next *sibling document-item* at the cursor's current container
level.

Concretely: given the parsed root, walk to the smallest enclosing container
(root, blockquote, list item, typed-block body, etc.) and treat that
container's direct children as the candidate set for `{` / `}`. The cursor
moves to the start of the previous (`{`) or next (`}`) child relative to
its current position.

Rationale: the reference's blank-line-based motion is unreliable for
typed-block-heavy documents (e.g., a `:::Callout` block with no internal
blank lines is one giant "paragraph" to the blank-line motion, but four
document items to the structure-aware motion).

With count: `3}` jumps to the third following sibling.

If the cursor is on a child boundary, `}` moves to the *next* sibling (not
the current one); `{` moves to the *previous*. Cursor at root start: `{`
no-ops. Cursor at root end: `}` no-ops.

### 4.7 Section motion — **§ Extension: heading-aware `[[` / `]]` and `[]` / `][`**

Section motions are vim's existing keys with new structural meanings.

| Key | Motion |
|---|---|
| `]]` | Next ATX heading (any level) |
| `[[` | Previous ATX heading (any level) |
| `][` | Next heading at the *same level* as the nearest enclosing heading, or any heading if not in one |
| `[]` | Previous heading at the same level |
| `]h` | Next heading at strictly higher level (more `#`'s)   — newly added |
| `[h` | Previous heading at strictly higher level — newly added |

(The `]h` / `[h` additions are open for naming; the underlying motion
"next/previous heading at a level deeper than current" is the requirement.)

### 4.8 Mark jump

| Key | Motion |
|---|---|
| `` `<a-z> `` | Exact position of local mark `a–z` |
| `m<a-z>` | Set local mark `a–z` at cursor (not a motion; included here for completeness) |

Reference's mark store is per-document, lowercase only. Global marks
(uppercase) are not in v0.1.

### 4.9 Structural navigation actions — **§ Extension**

These are *not* motions in the operator-pending sense; they're standalone
actions in Normal mode that jump to a parser-discovered target.

| Key | Action |
|---|---|
| `gf` | Follow wikilink under cursor (reference impl already supports this) |
| `]w` / `[w` | Next / previous wikilink in source order |
| `]l` / `[l` | Next / previous markdown link `[…](…)` |
| `]e` / `[e` | Next / previous embed (wiki embed or structured embed) |
| `]b` / `[b` | Next / previous block-id anchor `^name` |
| `]d` / `[d` | Next / previous diagnostic (parser error or warning) |

`gd` (goto definition) is *deferred* until vault/workspace navigation lands —
the reference doesn't implement it either.

## 5. Text Objects

Text objects come in `i<obj>` (inner) and `a<obj>` (around) flavors and
compose with operators: `d`, `c`, `y`, plus visual selection (`v` then
`<obj>`). Counts compose.

### 5.1 Standard objects (migrated)

| Object | `i` (inner) | `a` (around) |
|---|---|---|
| `w` | Word | Word + trailing whitespace |
| `W` | WORD | WORD + trailing whitespace |
| `s` | Sentence | Sentence + trailing whitespace |
| `p` | Paragraph | Paragraph + trailing blank line |
| `b` / `(` / `)` | Inside `(…)` | Including `(…)` |
| `B` / `{` / `}` | Inside `{…}` | Including `{…}` |
| `[` / `]` | Inside `[…]` | Including `[…]` |
| `<` / `>` | Inside `<…>` | Including `<…>` |
| `t` | Inside `<tag>…</tag>` | Including the tags |
| `"` | Inside `"…"` | Including `"…"` |
| `'` | Inside `'…'` | Including `'…'` |
| `` ` `` | Inside `` `…` `` (markdown code span) | Including backticks |

For the bracket pairs, the inner / around distinction is the standard vim
distinction: `iB` selects between the braces; `aB` includes them.

### 5.2 Structural objects — **§ Extension: tree-aware text objects**

These are new. Each one resolves against the typed CST at the cursor
position, finding the smallest enclosing node of the relevant kind. The
selection is the source range of that node.

The single-character mnemonics extend the existing object grammar:

| Object | `i` (inner) | `a` (around) | Notes |
|---|---|---|---|
| `h` | Inline content of the enclosing heading | Whole heading line including `#` markers and trailing newline | "h" = heading |
| `H` | Heading section content (all items between this heading and the next at the same or higher level), excluding the heading itself | The section including the heading | "H" = section. Uppercase H to distinguish from heading-line `ih` |
| `e` | Inline content of the enclosing paragraph (without trailing blockId / newline) | Whole paragraph including trailing newline | "e" = element. Need to confirm letter doesn't collide |
| `c` | Inner code-span / fenced-code-block body (just the payload) | Including delimiters / fence | Code |
| `m` | Inner math-block / math-inline payload | Including delimiters | Math |
| `k` | Inner typed block body (between header and close fence) | Including header + close fence | "k" = block; reuses the parser's "typed block" framing |
| `f` | Inner fields list of nearest typed constructor — selects the field-record interior `…` from `{…}` | Including the braces | "f" = fields |
| `v` | Inner field value at cursor (single field's value range) | Including field name + `:` + value | "v" = value |
| `l` | Inner wikilink target (between `[[` and `]]` or pipe) | Whole `[[…]]` | Link |
| `L` | Inner markdown link destination (between `(…)` after `[…]`) | Whole `[…](…)` | Markdown link |
| `n` | Inner list-item content (everything after the marker and trailing newline) | Whole list item including marker | "n" = node (list item) |
| `q` | Inner blockquote body | Whole blockquote including `>` markers | Quote |

Open questions on letter mnemonics:

- `ie` / `ae` might collide with anything obvious. Could be `iE` / `aE` for
  "element" if needed.
- `ik` / `ak` is a vim text-object convention sometimes used for a generic
  "block" — we should confirm no conflict.
- `if` / `af` reads naturally for "fields"; `iv` / `av` for "value" pairs
  with it.

The structural-object grammar should resolve **smallest enclosing** at the
cursor. If the cursor isn't inside the relevant kind, the object is
inapplicable; for visual-mode chord, this should be a no-op with a status
beep / dimmed highlight rather than a crash.

### 5.3 Counts on structural objects

Counts on a structural object **must** expand outward by sibling /
ancestor: `2iH` selects the current section *plus* the next sibling section
at the same level. `2ik` selects the current typed block plus its parent
typed block.

This generalizes vim's count-on-bracket behavior (where `2i(` selects two
nested parens) to tree structure.

## 6. Operators

| Operator | Effect | Doubled |
|---|---|---|
| `d` | Delete; copy to clipboard | `dd` deletes the current line |
| `c` | Delete + enter Insert; copy to clipboard | `cc` deletes current line, enters Insert |
| `y` | Yank (copy without deleting); cursor unchanged | `yy` yanks current line |

Standalone aliases that don't take a motion:

| Key | Equivalent |
|---|---|
| `D` | `d$` (delete to line end) |
| `C` | `c$` (change to line end) |
| `Y` | `yy` (yank line) |
| `x` | `dl` (delete forward char) |
| `X` | `dh` (delete backward char) |
| `s` | `cl` (substitute char) |
| `S` | `cc` (substitute line) |

All operators write to the system clipboard. No vim registers (`"a`, `"+`,
etc.) in v0.1.

### 6.1 Paste

| Key | Action |
|---|---|
| `p` | Paste after cursor (characterwise) or below current line (linewise) |
| `P` | Paste before cursor or above current line |

Linewise vs characterwise paste is determined by the clipboard contents'
last-yank context, matching reference behavior.

## 7. Matching delimiter — **§ Extension: structure-aware `%`**

The reference does not implement `%`. Liminal v0.1 **must** implement
structure-aware `%`:

- If the cursor is on an opening delimiter (`(`, `[`, `{`, `<`), jump to
  the matching closing delimiter. If on a closing one, jump to the matching
  opening one.
- If the cursor is on a typed-block fence (`:::` opener or closer), jump
  to the matching fence.
- If the cursor is on a code-block fence (`` ``` ``), jump to the matching
  fence.
- If the cursor is on a math-block fence, jump to the matching fence.
- If the cursor is anywhere inside a markdown link, wikilink, or embed
  syntax, jump between the structural boundaries (`[`/`]`, `[[`/`]]`,
  `(`/`)`).
- If the cursor is on the marker of a heading (`#`/`##`/etc.) or list
  item (`-`, `1.`, `[ ]`), jump to the end of that block (and back).

The intent is "`%` always means: take me to the structural counterpart of
this position." If no structural counterpart exists (e.g., cursor is in
the middle of plain text), `%` is a no-op.

## 8. Structural actions

These are standalone bindings in Normal mode that perform a structural edit
via the `replaceSubtree` primitive. They are not motion-composable —
each one is its own atomic command.

| Key | Action |
|---|---|
| `<C-]>` | Promote heading: increase `#` count by 1 (max 6) |
| `<C-[>` | Demote heading: decrease `#` count by 1 (min 1; `#` → no-op or convert to paragraph?) |
| `<Space>t` | Toggle task checkbox at cursor: `[ ]` ↔ `[x]` |
| `<Space>e` | Wrap selection in emphasis (`*…*`); if already emphasized, unwrap |
| `<Space>s` | Wrap selection in strong (`**…**`); unwrap if already |
| `<Space>k` | Wrap selection in code-span (`` `…` ``); unwrap if already |
| `<Space>l` | Insert wikilink at cursor; if word is selected, wrap it as target |
| `<C-S-K>` | Move current block up |
| `<C-S-J>` | Move current block down |

The leader binding (`<Space>`) is **open** — vim convention uses `\` but
many modern vim-flavored editors use `<Space>` for discoverability. Liminal
v0.1 **should** use `<Space>` and surface available actions via a hint
overlay (cf. `VimHints` in the reference).

Open questions:

- Promote at `######` and demote at `#`: should they wrap, no-op, or
  convert to a different block kind (e.g., demote `#` → paragraph)?
- Should there be a generic "cycle through heading levels" binding
  (e.g., Tab while in Normal on a heading line) similar to org-mode?
- Should structural actions register in the undo stack as structural
  edits (their own diff) or as the equivalent textual edit? See §10.

## 9. Marks

| Key | Action |
|---|---|
| `m<a-z>` | Set mark `a–z` at cursor position |
| `` `<a-z> `` | Jump to mark `a–z` exact position |
| `'<a-z>` | Jump to mark `a–z` first non-blank of the marked line |

Only lowercase local marks in v0.1. The marks **must** be tracked in
byte-offset coordinates and migrate through structural edits (the
`ReplacementWitness` from Cambium's `tree.replacing(...)` carries enough
information to translate paths across edits; marks **should** use this).

Mark palette (showing marks visually) optional in v0.1; reference
implements it.

## 10. Hints

After any prefix key (`d`, `c`, `y`, `g`, `z`, `m`, `` ` ``, `<Space>`),
the editor **should** display a hint overlay showing the available
follow-up keys and their meaning. The reference's `VimHints.swift` is the
model.

For structural objects (`ih`, `iH`, `ik`, etc.), the hint overlay **should**
optionally preview the resolution boundary (a subtle outline around what
the selection would become) — so users can see "this is the section I'm
about to delete" before pressing the operator.

## 11. Undo

Each motion / operator / structural-action invocation is one undo step.
Insert mode aggregates keystrokes into a single undo step that ends when
Insert is left (matching reference and vim behavior).

Structural actions (heading promote, task toggle, emphasis wrap)
**must** register their inverse in the undo manager. Whether the inverse
is recorded as a structural edit (replay the inverse `replaceSubtree`)
or as a textual diff (replay the inverse `applyTextEdits`) is an
implementation choice; the user-visible effect must be identical, and
mixed structural/textual undo histories must not desync.

## 12. Selection model

Selections are byte ranges into the source text. Visual character mode
maintains an anchor + head byte pair. Visual line mode rounds both
endpoints to line starts.

The cursor position is a byte offset; on display it converts to a
UTF-16 NSRange for NSTextView (see `LiminalTextView.byteRangeToNSRange`).
All motion math **should** operate in byte coordinates and convert at the
display boundary.

### 12.1 Smart expansion — **§ Extension**

In Visual character mode, pressing `<Tab>` (or another reserved key —
open) **should** expand the current selection to the smallest enclosing
structural node, then to its parent on subsequent presses. This is the
"expand selection by tree depth" feature found in some IDEs. Inverse with
`<S-Tab>`.

This is purely a visual-mode convenience; the underlying selection is
still a byte range, just one whose endpoints align with a tree node's
range.

## 13. Open questions

- **Letter mnemonics for structural objects** (§5.2). Several candidates
  collide with existing or planned uses; we should pin these down before
  building muscle memory.
- **Demote-past-`#`** (§8): drop to paragraph, no-op, or wrap to `######`?
- **`<Space>` vs `\` as leader** (§8). `<Space>` matches modern editors;
  `\` is vim-default.
- **Diagnostic navigation** (§4.9): `]d`/`[d` cycles diagnostics. Does the
  motion include unresolved-reference diagnostics from the workspace
  index, or only parser-side diagnostics?
- **Structural objects in operator-pending mode** (§5.2). `d` + structural
  object should delete the structural region. Test that `dik` deletes the
  typed block body without breaking the fence; `dak` deletes the whole
  typed block including fences. These edges need spec'd test cases.
- **Smart expansion key** (§12.1). `<Tab>` is fine but conflicts with
  insert-mode tab. `<C-Space>` is another option. Open.
- **Heading section operator targets** (§5.2, `iH` / `aH`). When the
  cursor is *not* inside a heading section (e.g., a leading paragraph
  before the first heading), what should `iH` / `aH` do?
- **Block move** (§8, `<C-S-J>` / `<C-S-K>`). Across what scope — within
  the current parent, or document-globally?

## 14. Out of scope for v0.1

- Vim ex-commands (`:w`, `:set`, etc.).
- Macros (`q<a>`).
- Registers beyond the system clipboard.
- Window splits.
- Folding (`zf`, `zo`, `zc`).
- Buffer / tab management.
- Vim's `.` (repeat last command).
- Visual block mode (`Ctrl-V`).

These may come back later; not in the initial cut.

## 15. Glossary

- **Motion**: a cursor-moving binding (h, w, gg, etc.). Composes with
  operators.
- **Operator**: a binding that takes a motion or text object and performs
  an action over the resulting range (d, c, y).
- **Text object**: a range-selecting binding used after an operator or in
  Visual mode (iw, ip, i(, ih).
- **Structural**: relating to the typed CST (parser-emitted tree). A
  "structural motion" navigates by tree structure; a "structural text
  object" selects a tree-defined region.
- **Container**: in §4.6, the smallest enclosing CST node that owns a
  list of document-item children (root, blockquote, list item, typed
  block body).
- **Section**: in §4.7, a region from an ATX heading to the next heading
  at the same or higher level.
