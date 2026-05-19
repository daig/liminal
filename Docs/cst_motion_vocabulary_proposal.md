  What I found

  The foundations are already strong

  - Cambium's SyntaxForest<Policy> gives us the right primitive: an anchor+head over
  contiguous siblings under a parent, with slidForward/slidBackward (collapse-and-move),
  extendedForward/Backward (move head only), parentForest(), firstChildForest(),
  withEndsSwapped(). Forest math is policy-driven and elegant.
  - LiminalCSTPolicy already classifies every kind as navigable/non-navigable and every
  parent as opaque/structuralChildren/allChildren. cstVisualEntry(at:in:) even ascends
  past structural-glue wrappers (inlineContent, fields, value, schemaBody, templateBody,
  typedConstructor) on entry — there's already a notion of "meaningful" vs "glue" landing
  points.
  - Today's .visualCST has 4 atoms + 2 extends + swap-ends — h parent, l firstChild, j
  next sibling, k previous sibling, J/K extend, o swap. That's the entire CST motion
  vocabulary, and it's exactly the hunt-and-peck you described.
  - Normal mode already has CST-aware motions for the text cursor: {/} (sibling at
  smallest container — StructureCursor.swift), gh (enclosing heading), [[/]] (any
  heading), [r/]r (any reference), all backed by the DocumentIndex (headings:
  [HeadingAnchor], references: [DocumentReference]).
  - The v0.1 navigation spec (liminal_navigation_spec_v0_1.md) already proposes structural
   text objects (ih/ah heading, iH/aH section, ik/ak typed block, etc.), more
  bracket-prefix searches, and % for structural matching — but everything in the spec
  lives in normal/text-visual mode against a text cursor. Nothing yet for the forest
  cursor inside .visualCST.
  - Paste targets today are an ad-hoc enum: exactCursor, rootProjectedFromCursor,
  parentProjectedFromCursor(levels), nearestAncestorProjectedFromCursor(kind). All four
  are navigation specs — "from the cursor, find this site" — and that's exactly the
  abstraction CST motions ought to unify.

  The gap, stated plainly

  .visualCST needs to feel like vim for a tree. Today it's the equivalent of having only
  h/j/k/l in text mode: technically complete, painfully tedious. Vim's punch comes from
  w/b/e, }/{, ]]/[[, ]w/[r, iw/ip/it, f/t/;/,, marks, and counts — semantic leaps, not
  byte-by-byte trudging.

  So we need to extend the CST motion vocabulary along the dimensions a tree opens up
  (horizontal, vertical, diagonal, predicate-filtered) without turning it into 60 ad-hoc
  enum cases.

  ---
  Proposal — three-layer CST motion vocabulary

  Layer 1: a small kernel abstraction

  The user-facing motions stay as a named enum (like today's CSTMotion), but underneath
  they all desugar to one composable resolver:

  struct CSTSearch {
      enum Axis {
          case sibling              // same parent
          case ancestor             // up
          case descendant           // down a first-child chain
          case preorder             // document order, all the way through
      }
      enum Direction { case forward, backward }
      enum Predicate {
          case any                  // any navigable
          case nonGlue              // any navigable, skip structural-glue kinds
          case kindIn(Set<LiminalKind>)
          case differentKindThan(LiminalKind)
          case headingLevel(Match)  // .same / .deeperThan(level) / .shallowerThan(level)
          case fromDocumentIndex(IndexedTarget)  // .headings, .references, .blocks,
  .diagnostics
          case custom((LiminalForest) -> Bool)
      }
      var axis: Axis
      var direction: Direction
      var predicate: Predicate
      var countSemantics: CountSemantics  // .repeatStep / .nthAbsolute
  }

  Every CST motion is one of these. slidForward() becomes CSTSearch(.sibling, .forward,
  .any, .repeatStep). nextHeading becomes CSTSearch(.preorder, .forward,
  .fromDocumentIndex(.headings), .repeatStep). The vocabulary in Layer 2 is just named
  instances of this kernel — the implementation is one resolver.

  Layer 2: the named motion catalog (the user-facing keys)

  Organized by "what scale of leap" — analogous to how vim splits
  char/word/line/paragraph/section.

  Step motions (vim's h/l/j/k/w/b)

  Local navigation. Counts repeat the step.

  ┌───────┬─────────────────┬─────────────────────────────────────────────────────────┐
  │ Chord │     Motion      │                           Why                           │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │ Next / previous │                                                         │
  │ j / k │  sibling        │ Forest's slidForward/Backward. The "trudge" axis.       │
  │       │ (current        │                                                         │
  │       │ behavior)       │                                                         │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │                 │ Today's h is raw parentForest. Make it ascend past      │
  │ h     │ Parent, skip    │ inlineContent/fields/value/etc. so users land on        │
  │       │ glue            │ something meaningful. The current "raw" parent becomes  │
  │       │                 │ a less-used alternative.                                │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │ First navigable │                                                         │
  │ l     │  child, skip    │ Same logic in reverse.                                  │
  │       │ glue            │                                                         │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │ Next sibling of │                                                         │
  │ w     │  different kind │ The "skip a run" motion. After 5 paragraphs in a row, w │
  │       │  than current   │  jumps to the next heading or list, not paragraph 6.    │
  │       │ head            │                                                         │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │ Previous        │                                                         │
  │ b     │ sibling of      │                                                         │
  │       │ different kind  │                                                         │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │       │ Collapse to     │ "If you're on paragraph 3 of 5 paragraphs, e lands you  │
  │ e     │ last sibling in │ on paragraph 5." Useful for "extend to the end of this  │
  │       │  current        │ block of similars" → vE (extend) becomes natural.       │
  │       │ kind-run        │                                                         │
  ├───────┼─────────────────┼─────────────────────────────────────────────────────────┤
  │ gj /  │ First / last    │                                                         │
  │ gk    │ sibling under   │ Analog of 0 / $.                                        │
  │       │ current parent  │                                                         │
  └───────┴─────────────────┴─────────────────────────────────────────────────────────┘

  Block motions (vim's }/{)

  The "jump out of inline scope to the next block."

  ┌───────┬────────────────────────────────────────────────────────────────────────────┐
  │ Chord │                                   Motion                                   │
  ├───────┼────────────────────────────────────────────────────────────────────────────┤
  │ }     │ Next sibling at the smallest block-owning ancestor (ascend until parent is │
  │       │  root/blockQuote/listItem/typedBlock/etc.; then slidForward).              │
  ├───────┼────────────────────────────────────────────────────────────────────────────┤
  │ {     │ Previous sibling at the smallest block-owning ancestor.                    │
  └───────┴────────────────────────────────────────────────────────────────────────────┘

  In .visualCST this gives you "jump out of an emphasis, past the rest of this paragraph,
  to the next paragraph" with a single press.

  Section motions (vim's ]]/[[)

  ┌────────┬──────────────────────────────────────────────────────────────────────────┐
  │ Chord  │                                  Motion                                  │
  ├────────┼──────────────────────────────────────────────────────────────────────────┤
  │ ]] /   │ Next / previous heading (any level), forest = the atxHeading node        │
  │ [[     │                                                                          │
  ├────────┼──────────────────────────────────────────────────────────────────────────┤
  │ ][ /   │ Next / previous heading at the same level as the nearest enclosing       │
  │ []     │ heading                                                                  │
  ├────────┼──────────────────────────────────────────────────────────────────────────┤
  │ ]h /   │ Next / previous heading at a strictly deeper level                       │
  │ [h     │                                                                          │
  ├────────┼──────────────────────────────────────────────────────────────────────────┤
  │ gH     │ Enclosing heading — forest jumps to the AtxHeading owning my section     │
  └────────┴──────────────────────────────────────────────────────────────────────────┘

  All backed by DocumentIndex.headings.

  Search motions (vim's ]w/]r/etc.)

  The bracket-prefix family — find a typed kind anywhere in the document, in preorder.

  ┌─────────┬──────────────────────────────────────┐
  │  Chord  │                Motion                │
  ├─────────┼──────────────────────────────────────┤
  │ ]w / [w │ wikilink                             │
  ├─────────┼──────────────────────────────────────┤
  │ ]l / [l │ markdown link                        │
  ├─────────┼──────────────────────────────────────┤
  │ ]e / [e │ embed (wikiEmbed or structuredEmbed) │
  ├─────────┼──────────────────────────────────────┤
  │ ]r / [r │ any reference                        │
  ├─────────┼──────────────────────────────────────┤
  │ ]b / [b │ block-id anchor (^name)              │
  ├─────────┼──────────────────────────────────────┤
  │ ]c / [c │ code (fenced block or codeSpan)      │
  ├─────────┼──────────────────────────────────────┤
  │ ]m / [m │ math (block or inline)               │
  ├─────────┼──────────────────────────────────────┤
  │ ]k / [k │ typed block                          │
  ├─────────┼──────────────────────────────────────┤
  │ ]t / [t │ task list item                       │
  ├─────────┼──────────────────────────────────────┤
  │ ]d / [d │ diagnostic                           │
  └─────────┴──────────────────────────────────────┘

  (Mostly mirror the v0.1 spec's normal-mode bracket family. Reserve [d/]d and [z/]z per
  the spec's note about LSP/fold conventions.)

  Endpoints and marks

  ┌──────────────────┬────────────────────────────────────────────────────────────────┐
  │      Chord       │                             Motion                             │
  ├──────────────────┼────────────────────────────────────────────────────────────────┤
  │ gg / G           │ First / last navigable forest in document                      │
  ├──────────────────┼────────────────────────────────────────────────────────────────┤
  │ gh (or H if      │ Ascend to the top-level navigable under root                   │
  │ free)            │                                                                │
  ├──────────────────┼────────────────────────────────────────────────────────────────┤
  │ gl               │ Descend the full first-child chain to its deepest navigable    │
  │                  │ leaf                                                           │
  ├──────────────────┼────────────────────────────────────────────────────────────────┤
  │ `<a-z>           │ Jump to CST mark — a LiminalForestAnchor you stored earlier    │
  ├──────────────────┼────────────────────────────────────────────────────────────────┤
  │ m<a-z>           │ Set CST mark at current forest                                 │
  └──────────────────┴────────────────────────────────────────────────────────────────┘

  Smart-expand (the "Tab" feature from §12.1 of the spec)

  ┌──────────┬────────────────────────────────────────────────────────────────────────┐
  │  Chord   │                                 Motion                                 │
  ├──────────┼────────────────────────────────────────────────────────────────────────┤
  │ + or     │ Smart expand: ascend until landing on a non-glue,                      │
  │ <Tab>    │ "interesting-relative-to-here" parent. Often just h + glue-skip +      │
  │          │ "skip single-child wrappers."                                          │
  ├──────────┼────────────────────────────────────────────────────────────────────────┤
  │ - or     │ Smart narrow: descend toward the most-meaningful first child.          │
  │ <S-Tab>  │                                                                        │
  └──────────┴────────────────────────────────────────────────────────────────────────┘

  Object motions (vim's iw/ap/ih/ik)

  In CST mode these are standalone — pressing ih jumps the forest to "the heading line
  around my current position." Outside CST mode (in normal/text-visual) they compose with
  operators per the v0.1 spec.

  Reuse the spec's letter mnemonics: ih/ah, iH/aH, ie/ae, ic/ac, im/am, ik/ak, if/af,
  iv/av, il/al, iL/aL, in/an, iq/aq.

  Layer 3: slide vs. extend

  Keep the current convention:
  - Lowercase chord = slide (collapse to singleton at the new spot).
  - Uppercase chord = extend (head moves, anchor stays).

  For multi-key chords like ]] or iH, the <S-Tab>-style shift convention can't ride on
  uppercase. Two options:
  - (A) Mode-prefix toggle: pressing v in .visualCST toggles "next motion extends." Vim
  has this for o/O semantics.
  - (B) Bind both forms: lowercase prefix slides, uppercase prefix extends — ]] slides, ]]
   with explicit shift on the second ] extends. Probably not great.

  I'd lean (A): a single sticky V (or e) toggle in .visualCST that makes the next motion
  extend.

  ---
  How this plugs into the paste-target system

  The four StructuralCSTPasteTargetScope cases re-express directly as motions from the
  text-cursor's projected singleton forest:

  ┌───────────────────────────────────────────┬───────────────────────────────────────┐
  │               Today's scope               │              Motion form              │
  ├───────────────────────────────────────────┼───────────────────────────────────────┤
  │ .exactCursor                              │ identity (cursor's singleton forest)  │
  ├───────────────────────────────────────────┼───────────────────────────────────────┤
  │ .parentProjectedFromCursor(levels: N)     │ CSTSearch(.ancestor, .forward, .any,  │
  │                                           │ .repeatStep) with count: N            │
  ├───────────────────────────────────────────┼───────────────────────────────────────┤
  │                                           │ CSTSearch(.ancestor, .forward, .any,  │
  │ .rootProjectedFromCursor                  │ .repeatStep) with count: Int.max      │
  │                                           │ (saturate at root)                    │
  ├───────────────────────────────────────────┼───────────────────────────────────────┤
  │ .nearestAncestorProjectedFromCursor(kind: │ CSTSearch(.ancestor, .forward,        │
  │  K)                                       │ .kindIn([K]), .repeatStep) with       │
  │                                           │ count: 1                              │
  └───────────────────────────────────────────┴───────────────────────────────────────┘

  And it generalizes immediately to every motion in Layer 2. <Space>p]] pastes at the next
   heading. <Space>p2h pastes at the grandparent. <Space>pgg pastes at the document start.
   The future-scope comments in StructuralCSTPasteSite.swift
  (outermostAncestorProjectedFromCursor, selectedTarget, markedTarget, explicitPath) all
  collapse into "motion to forest, paste."

  Once we have Layer 1, the paste API becomes paste(payload, atForestProducedBy:
  CSTSearch, after: Bool) and the scope enum is gone.

  ---
  Where I'd like your input before I refine

  These are the points where I think the design genuinely branches:

  1. Slide vs. extend in visualCST. Today, lowercase slides and uppercase extends. With
  multi-key chords (]], ih, etc.) the convention can't ride on shift. Are you okay with a
  sticky V-toggle for "the next motion extends," or would you rather every motion extend
  in .visualCST and treat slide as "Esc, move text cursor, re-enter"?
  2. "Smart" parent (h) vs. "raw" parent. I want h to skip structural glue (inlineContent,
   fields, value, etc.) because users almost never want to land on those. But it means h
  and "the inverse of the last l" don't always commute. Acceptable, or should
  glue-skipping live behind a separate chord (e.g., +)?
  3. Kernel-as-API vs. kernel-as-implementation-detail. I sketched CSTSearch as a value
  type that motions compile into. Do you want that surface exposed (so the engine can be
  driven from outside the binding tree — paste, marks, ex-commands), or kept as a private
  implementation behind a flat enum?
  4. First implementation slice. I'd suggest landing in this order, since each step builds
   on the last:
    - (a) The CSTSearch resolver + glue-skipping h/l + gj/gk (top/bottom sibling) + gg/G —
   pure forest math, no DocumentIndex.
    - (b) }/{ (block-owning ancestor) + w/b/e (kind-runs) — still pure forest math.
    - (c) ]]/[[ family backed by DocumentIndex — needs index plumbing into VimController.
    - (d) Object motions (ih/ik/etc.) — needs the typed-syntax queries the v0.1 spec
  sketches.
    - (e) Paste refactor to take CSTSearch — once the vocabulary is stable.

  Does that ordering match how you want to attack it, or would you front-load the paste
  refactor to validate the abstraction?

  Pick the one(s) that look most contentious and let's drill in.
