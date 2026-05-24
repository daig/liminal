# Custom Text Engine Migration Roadmap

## Context — why we are doing this

Liminal's editor is **CST-oriented, not text-oriented**. The document of record
is a Cambium concrete syntax tree over a rope (`CambiumSource`); the on-screen
text is a *projection* of that model. Everything on the near- and mid-term
roadmap pushes against the assumption that the document is one linear attributed
string:

- **Display ≠ source** (the original motivation): conceal markup, align/pad
  tables, virtual text, block widgets. Cambium's tree is strictly lossless, so
  display-only content *can never live in the tree* — it must live in a
  presentation layer.
- **Structural accessibility:** voice/assistive navigation should map to syntax
  anchors (headings, list items, table cells) and structural commands
  (promote, toggle task), not text ranges. The macOS Accessibility API is
  *already* a semantic element tree — a near-perfect match for a CST.
- **Custom cursor/selection, multi-cursor (visual-block insert), folding** — all
  the modal-editing surface lives on the "replace NSTextView's core behavior"
  side.

We evaluated **TextKit 1** (today, inherited/implicit — forced by manually
constructing `NSLayoutManager` in `LiminalTextView.swift:86-92`, never a
deliberate choice), **TextKit 2**, and a **fully custom engine**. The decision
record:

- TK1 is Apple's legacy/compatibility path; building new display≠source
  infrastructure on it is investing in a dead end.
- TK2's `textParagraph` substitution is the right hook *for styling-class*
  display≠source, but the moment we want a custom cursor, custom selection
  rendering, a CST-shaped accessibility tree, multi-cursor, or folding, we are
  overriding the very NSTextView internals we adopted it for — the
  "worst of both worlds" zone — while also inheriting TK2's version churn.
- A **custom Core Text engine** has *exact* model fit, no perpetual
  framework-fighting tax, and a rock-stable base. Its only real costs are **IME**
  and **accessibility** — and both are deferrable and, for accessibility,
  a place we can *exceed* native by projecting the CST into the AX tree.

Input is de-risked, which removed the last objection to custom:

- **Math input** (vim digraphs / Agda `\`-mnemonics) is *our own layer*, never the
  OS input method — engine-agnostic, and cleaner on custom (no contention with OS
  marked text).
- **Chinese** is the lone genuine OS-IME dependency — deferrable *without boxing
  ourselves in*, provided we adopt the `NSTextInputClient` seam from day one
  (English-correct now, CJK-correct later — a fill-in, not a re-architecture).
- **English** direct input is trivial on either substrate.

**Conclusion:** migrate to a fully custom Core Text engine. This roadmap
sequences that migration, with the deferred subsystems seeded as *seams* in
Phase 1 so they never become retrofits.

---

## End-goal architecture

A layered model in which **everything above the view is substrate-independent**
(operates on byte offsets / CST, never on layout glyphs), and the view is a
swappable engine:

```
SwiftUI host (NSViewRepresentable wrapper)  ── unchanged
  + SwiftUI overlays/chrome (hints, narrow chain, command line, inspectors) ── unchanged
        │
        ▼
Custom editor NSView (Core Text)
  ├─ Layout engine  ── Core Text line layout, soft-wrap, viewport-lazy, line-fragment cache
  ├─ Renderer       ── CG/CALayer first pass  → (later) GPU/Metal or CALayer-per-line
  ├─ Geometry seam  ── the ~6 queries (below); renderer-agnostic
  ├─ Caret/selection rendering ── block/bar/underline cursor, visual highlights, CST overlays
  ├─ Input seam     ── NSTextInputClient (English now) + CompositionSession abstraction
  └─ AX adaptation  ── (later) CST → NSAccessibilityElement tree + custom rotors + actions
        │  reads through ▼
Projection layer (display ≠ source)  ── identity in Phase 1
  ├─ Decoration computation  ── pure CST → [Decoration]; cached in Cambium SyntaxMetadataStore
  └─ ProjectionMap           ── source ↔ display offset mapping
        │
        ▼
Document model (source of truth)
  ├─ Cambium CST + rope (CambiumSource) ── lossless; display content never in tree
  └─ Structural engine ── CST queries (motions, %, structural objects, diagnostics)
                          → one engine, three consumers: vim motions · a11y rotors · voice actions
```

**Reused as-is** (already substrate-independent): `CursorMotionEngine` (pure rope
math, UTF-16 in/out — `CursorMotionEngine.swift:32`), `StructureCursor`,
`ForestMotion`, `DocumentIndex` heading/reference nav, `VimController`,
`MarkRegistry`/`ForestMarkRegistry` (byte-offset marks), `CSTUndoHistory`,
`PasteEngine`, all of `Syntax/`·`Semantics/`·`Workspace/`, `LiminalHighlighter`
(span computation), and the SwiftUI overlays (zero TextKit references).

### Coordinate systems

Three units coexist and must be reconciled:

- **Model — UTF-8 byte offsets** (Cambium `TextSize`). The source of truth; CST
  ranges, marks, edits, and undo are all byte-based.
- **Layout — UTF-16 code units.** Core Text's index API is UTF-16 (`CFString` /
  `CTLine` indices), exactly like `NSString` / `NSTextView` before it — so UTF-16
  is *not eliminated* by going custom, only relocated.
- **User "character" — grapheme clusters.** What `h` / `l` / `w` should move by; a
  non-BMP character (emoji, the math-alphanumeric block U+1D400+) is one grapheme
  but a UTF-16 surrogate *pair*.

**End-state rule:** the model, marks, selection, motion, operators, and paste are
**byte-native** (matching Cambium); **UTF-16 is confined to a thin per-line Core
Text layout adapter** (byte↔UTF-16 computed as a byproduct of laying out each line
and cached with its fragment, rather than per-crossing rope queries); and motion is
**grapheme-aware**, converting to bytes (model) and UTF-16 (Core Text) only at the
edges.

This is a deliberate departure from the TK1 world, where UTF-16 leaked past the
view boundary into `CursorMotionEngine` / `OperatorRange` / `PasteEngine`
*because NSTextView's API surface (selection, edited ranges, hit-testing) is
UTF-16*. It also retires the boundary-correctness hazards behind past bugs
(mid-multibyte / surrogate-mid conversion — Phase 2 landmines #9/#10 — and
rope-vs-`NSString` line-terminator divergence #5). The byte-native +
grapheme-aware cleanup is scheduled as a **refinement bundle** (below), *not*
Phase 1.

---

## Phase overview

| Phase | Scope | Status | Seam built in P1 |
|---|---|---|---|
| **1** | **TK1 → custom Core Text engine, strict parity** | **focus** | — |
| 2 | Display ≠ source projection (conceal, table align/pad, virtual text) | next | projection reads as identity |
| 3 | Accessibility (CST → AX tree, rotors, actions) | deferred | view is an `NSAccessibilityElement` structured for a tree |
| 4 | Chinese / CJK input (full `NSTextInputClient`) | deferred | protocol adopted, English-correct |
| 5 | Math input (digraphs / Agda mnemonics) | deferred, independent | `CompositionSession` abstraction |
| 6 | Rendering backend upgrade (GPU/Metal or CALayer-per-line) — **TBD** | independent followup | renderer behind geometry seam |
| R | Coordinate cleanup — byte-native core + grapheme-aware motion | refinement · before P5 | model/marks/edits already byte-native in P1 |

Phases 3–5 are deferred but their **seams are built in Phase 1** (see
*Boxing-in safeguards*). Phase 6 is an independent performance followup with no
model/behavior change. Block widgets, folding, and multi-cursor are *unlocked* by
the custom engine and noted under Phase 2+ but not scheduled here. The **R** row
is a cross-cutting coordinate-system cleanup scheduled by dependency (before
Phase 5), not a sequential phase.

---

## Phase 1 — TK1 → custom Core Text engine (strict parity)  ← main focus

### Goal
Replace the NSTextView/TextKit-1 substrate with a custom Core Text `NSView` that
reproduces **today's main editing experience with zero regression**, rendering
**byte-faithfully (display == source)**. No new features.

### Acceptable losses (restored in later phases — *not* regressions per the agreed bar)
- **OS IME / marked-text composition** — Phase 1 supports English direct insert
  only. *Restored in Phase 4*; the `NSTextInputClient` seam is adopted now.
- **Accessibility** (VoiceOver / Voice Control / Switch Control) — *Phase 3*; a
  minimal `NSAccessibilityElement` stub is structured for it now.
- **Incidental native extras** — Services, Look Up / data detectors, system text
  drag-and-drop, dictation, press-and-hold accent menu. Restore opportunistically;
  not core to the modal editing experience.

### Must-keep (the no-regression checklist)
1. **Text rendering + syntax highlighting**, viewport/scoped repaint and
   scroll-driven repaint (parity with `applyHighlights` scoping,
   `LiminalTextView.swift:3006-3085`, and `visiblePaintScope`).
2. **Edit pipeline**: keystroke → `TextEdit` (byte range) → `document.applyTextEdits`
   → reparse → scoped re-highlight (replaces the `NSTextStorageDelegate` path at
   `LiminalTextView.swift:525-561`; reentrancy is simpler since we own the loop).
3. **All vim modes** (normal/insert/visual/visual-line/visual-block/visualCST/
   commandLine) and their selection rendering; **block vs bar cursor** styles
   (replaces the length-1-selection trick in `refreshCursorStyle`,
   `LiminalTextView.swift:471-494` — now a real custom-drawn caret).
4. **All cursor motions**: char/word/line + structural (`structuralMotion`),
   viewport `H/M/L` (`viewportMotion`), wrapped display-line `gj/gk/g0/g^/g$`
   (`displayLineMotion`), file `gg/G`, heading/reference, in-line `f/t`.
   The motion *math* is reused unchanged; only the layout queries it consumes are
   re-sourced from the geometry seam.
5. **Overlays**: CST selection, head accent, forest mark outlines, mark dots
   (port the `VimTextView.draw()` passes, `VimTextView.swift:104-281`, from
   `NSLayoutManager.enumerateEnclosingRects` to the geometry seam).
6. **Marks** (set/jump, indicators, forest marks).
7. **Hover preview** (position via offset→rect; the hover *content* view is a
   separate read-only NSTextView that **stays on TextKit initially**).
8. **Links** (cmd-click, cmd-shift-click, hover) via point→offset.
9. **Find** — reimplement minimal incremental find over source (replaces the
   native find bar; this is a must-keep capability, so it is in-scope for P1).
10. **Undo/redo** (`CSTUndoHistory`, already substrate-independent).
11. **SwiftUI chrome** (command-line popup, narrow chain, vim hints, inspector) —
    survives untouched.
12. **Scrolling / scroll-to-cursor**.

### The geometry seam (the one core new abstraction)
A renderer-agnostic protocol the engine implements via Core Text and the
Coordinator/overlays consume instead of `NSLayoutManager`:

| Query | Used by |
|---|---|
| offset(UTF-16) → caret/glyph rect | caret, mark dots, hover positioning |
| range(UTF-16) → enclosing line-fragment rects | selection + CST overlays |
| point → offset | clicks, cmd-click (`CmdClickHandler`) |
| visible offset range | viewport motions `H/M/L` |
| display-line range at offset; vertical neighbor by preferred-x | wrapped `gj/gk` |
| scroll(to offset/range); content size; ensureLayout(viewport) | scrolling, layout |

UTF-16 indices are retained at the Core Text boundary (Core Text is UTF-16
native), so `CursorMotionEngine`'s UTF-16 contract is preserved with no rewrite.

### Build-out (work items)
- **Layout engine** — Core Text typesetting (`CTTypesetter`/`CTLine`), soft-wrap
  to container width, line-fragment model, viewport-lazy layout + cache. Monospace
  assumption simplifies metrics and hit-testing.
- **Renderer** — draw visible line fragments via CG (glyphs + theme attributes:
  color/font/underline/strikethrough/background from `LiminalHighlightTheme`).
- **Custom `NSView`** (replaces `VimTextView` + the NSTextView stack) — first
  responder; `keyDown` → `VimController` (unchanged routing); `draw` (glyphs +
  overlays + custom caret/selection); mouse (click→offset, drag-select, cmd-click);
  scroll.
- **Input seam** — adopt `NSTextInputClient`; English path
  (`keyDown` → `inputContext?.handleEvent` → `insertText` → edit pipeline);
  `CompositionSession` abstraction stubbed (only direct typing produces text in P1).
- **Caret & selection rendering** — per-mode cursor; visual-mode highlight; port
  the four overlay passes to the geometry seam.
- **Motion integration** — rewire `moveCursor`/`structuralMotion`/`viewportMotion`/
  `displayLineMotion` to the seam; engines unchanged.
- **Highlighting** — keep `LiminalHighlighter` spans; apply within viewport-scoped
  render; preserve scoped + scroll-driven repaint.
- **Minimal find** over source.
- **A11y stub** — `NSAccessibilityElement` role `.textArea` with value/selection
  basics, structured so the Phase 3 CST→AX tree layers on without rework.
- **Host wiring** — point the `NSViewRepresentable` `makeNSView` (`LiminalEditorView`)
  at the custom view; overlays/chrome unchanged.

### Critical files
- **New:** the layout engine, renderer, geometry-seam protocol, and custom
  `NSView` (new files under `liminal/Liminal/App/` or a new `App/TextEngine/`
  group).
- **Modified:** `LiminalEditorView.swift` (construction site — single cutover
  point), the motion handlers and overlay/render integration currently in
  `LiminalTextView.swift`'s Coordinator, `CmdClickHandler.swift` (point→offset),
  `HoverPreviewController.swift` (offset→rect).
- **Deleted at cutover:** `VimTextView.swift` and the manual
  `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` stack.
- **Untouched:** everything in `Editor/` (except where it reads the seam),
  `Syntax/`, `Semantics/`, `Workspace/`, `LiminalHighlighter.swift`,
  `MarkDotLayout.swift` (pure math — reusable), and the SwiftUI overlays.

### Strategy & risks
- **Clean branch cutover.** Build the engine on a dedicated branch; keep the old
  NSTextView path *buildable on the branch* purely as a parity reference until the
  cutover commit, then delete it. No runtime feature flag, no dual code paths in
  `main`.
- **Layout parity** (wrapping, line metrics, caret rects) — mitigate with the
  monospace assumption and side-by-side rect/caret comparison against the
  still-present old path before cutover.
- **Large-doc perf** (the 1.2 MB stress fixtures) — viewport-lazy CT layout +
  line-fragment cache; lay out/render visible + buffer only (mirror current
  `visiblePaintScope`).
- **Edit/cursor stability across reparse** — reuse byte-offset/`CSTAnchor`
  discipline; marks and cursor are already byte-based.

### Verification (no regression)
- **Model tests** (the existing ~1009, incl. `CursorMotionEngine`/`StructureCursor`)
  must stay green — they are substrate-independent and exercise the reused logic.
- **Geometry-seam conformance tests** — offset→rect→offset round-trips,
  point→offset, display-line ranges, against fixed monospace fixtures.
- **Parity comparison** — before deleting the old path, render representative docs
  (incl. `Docs/Fixtures/stress.md`) through both engines and diff line-fragment
  rects and caret positions.
- **Manual regression walk** — drive the running app via the Xcode MCP
  (`BuildProject`, run) through the *Must-keep checklist* above.
- Build/test exclusively through the Xcode MCP per `AGENTS.md`.

---

## Later phases (concise — so nothing is forgotten)

### Phase 2 — Display ≠ source projection (the original motivation)
- **Decoration computation:** pure `CST → [Decoration]` (`.conceal`, `.pad/.align`,
  `.virtualText`, `.blockWidget`); driven by typed nodes (`PipeTableSyntax` already
  exposes header/delimiter/rows/cells/alignments, `LiminalTypedSyntax.swift:1304`);
  cached in Cambium's `SyntaxMetadataStore`, invalidated via parse witnesses.
- **ProjectionMap:** source↔display offset mapping wired into the geometry seam,
  motion, and a selection *snapper* (the "non-navigable" property — caret skips
  concealed/virtual runs).
- **Realizations:** markup conceal; **canonical monospace table alignment**
  (conceal source padding + insert virtual padding to a uniform column width —
  integer-clean under monospace); **reveal-on-cursor** policy (active line/cell
  shows raw source for editing).
- Copy yields source; find runs over source.
- This is where the table-alignment feature that began this exploration lands —
  now principled and CST-driven rather than the prototype's kern hack.

### Phase 3 — Accessibility (CST-shaped, can beat native)
- **AX adaptation:** project CST → `NSAccessibilityElement` tree (role per
  `LiminalKind`); **custom rotors** (headings / links / diagnostics — reuse the
  structural engine, same queries as `]]`/`]w`/`]d`); **custom actions**
  (navigation-spec §8: promote/demote, toggle task, wrap emphasis); **text-protocol
  leaves** (value/selection/line/`accessibilityFrame(for:)`/caret — reuse the
  geometry seam).
- **Source-vs-display policy:** VoiceOver reads the projected display + structural
  traits.
- **MVP tier** (role/value/settable-selection/line-range/frame/caret/notifications),
  then **great tier** (semantic tree + hierarchy).
- **Test matrix:** VoiceOver, Voice Control, Switch Control, Accessibility Inspector.

### Phase 4 — Chinese / CJK input
- Full `NSTextInputClient` correctness: marked-text rendering, `firstRect`
  candidate-window placement (over the *revealed* active line — the easy case,
  courtesy of reveal-on-cursor), reconversion, `attributedSubstring`.
- Plugs into the `CompositionSession` abstraction. Fill-in, not a retrofit — the
  protocol is already adopted from Phase 1.

### Phase 5 — Math input (our idioms)
- Vim digraphs / Agda `\`-mnemonics as a `CompositionSession` producer with a live
  candidate popup (built like the existing command-line completion / hint overlay).
  Engine- and IME-agnostic; unified with CJK via the shared composition model.
- **Depends on the coordinate-system cleanup refinement bundle** — the
  math-alphanumeric block (U+1D400+) is non-BMP surrogate pairs, so byte-native +
  grapheme-aware motion must land first.

### Phase 6 — Rendering backend upgrade — independent, **TBD**
- GPU/Metal or CALayer-per-line, behind the geometry seam (the renderer is
  swappable by design). Pure performance/scroll optimization; no model or behavior
  change. Approach to be decided when this is prioritized.

### Refinement bundle — coordinate-system cleanup (cross-cutting; prerequisite of Phase 5)
Not a sequential phase — a focused cleanup scheduled by dependency: before Phase 5
(math input) and benefiting Phase 4 (CJK). Background in *End-goal architecture →
Coordinate systems*.

- **Make the editor core byte-native.** Migrate `CursorMotionEngine`,
  `OperatorRange`, and `PasteEngine` off UTF-16 onto Cambium byte offsets — the one
  remaining island where UTF-16 leaked past the view boundary because NSTextView's
  API forced it.
- **Keep UTF-16 confined to the per-line Core Text layout adapter** (it lives there
  permanently — Core Text's index API is UTF-16); compute byte↔UTF-16 per line as a
  layout byproduct cached with the fragment, replacing per-crossing rope queries.
- **Grapheme-aware motion.** `h` / `l` / `w` move by grapheme cluster, not UTF-16
  unit — correct for emoji/CJK and **required** for the math-alphanumeric block
  (U+1D400+, non-BMP surrogate pairs) inserted by Phase 5.
- Retires the conversion boundary-bug class (Phase 2 landmines #9/#10) and the
  rope-vs-`NSString` line-terminator divergence (#5) by owning line breaking.
- **Why deferred, not Phase 1:** none of it changes ASCII/English behavior, so
  Phase 1 keeps the working UTF-16 motion engine for the lowest-risk strict-parity
  migration.

### Unlocked, not scheduled
Block widgets / inline-rendered blocks, code folding, and multi-cursor
(visual-block insert) — natural on the custom engine, infeasible cleanly on
NSTextView. Recorded so we remember the engine enables them.

---

## Boxing-in safeguards (honor these in Phase 1)
1. **Model/projection/mapping stay substrate-independent** — byte offsets / CST,
   never layout glyphs.
2. **Narrow geometry seam** — renderer is swappable (GPU later, Phase 6).
3. **`NSTextInputClient` adopted day one** (English) + **`CompositionSession`**
   abstraction → CJK (P4) and math (P5) are fill-ins.
4. **View is an `NSAccessibilityElement` structured for a CST→AX tree** → structural
   a11y (P3) is not blocked.
5. **Render pipeline reads through a projection** (identity in P1) → display≠source
   (P2) slots in without re-plumbing.
6. **Confine UTF-16 to the Core Text layout adapter; model/marks/edits stay
   byte-native.** `CursorMotionEngine` / `OperatorRange` / `PasteEngine` remain the
   one UTF-16 legacy island in Phase 1 (left unchanged, for strict parity) —
   scheduled for a byte-native + grapheme-aware rewrite in the coordinate-system
   cleanup refinement bundle (prerequisite of Phase 5).
