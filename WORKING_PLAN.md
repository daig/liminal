# Liminal Rebuild Working Plan

This document is the roadmap for the Cambium-backed Liminal rebuild. It is
aligned to `liminal/Docs/Language/liminal_markup_syntax_spec_v0_2.md`.

The language direction is now explicit:

- Liminal Markup is not a CommonMark, GFM, or Obsidian compatibility target.
- Markdown-like syntax is only surface syntax.
- The semantic core is a typed tree.
- The parser owns a schema-free, lossless CST.
- The lowerer maps CST surface forms into typed semantic document items.

Implementation details belong in code and focused tests. This plan records the
implementation sequence and the non-negotiable boundaries.

---

## The Load-Bearing Principle

> Markdown-like constructs are surface forms for typed semantic nodes.
>
> - `liminal/Docs/Language/liminal_markup_syntax_spec_v0_2.md`

Read this concretely:

- **CST kinds reflect source forms.** Use names like `atxHeading`, `mdLink`,
  `wikilink`, `wikiEmbed`, `pipeTable`, `typedBlock`, and `typedInline`.
- **CST kinds do not name user-facing schema types.** No `headingNode`,
  `personNode`, or `citationNode`. Type names live in tokens such as `qname`
  and are interpreted by the lowerer/schema pass.
- **The CST is schema-free.** `@DoesNotExist{foo: 1}` parses into a typed
  constructor with a `qname` token. Schema resolution reports unresolved types;
  it never rewrites the parse tree.
- **The semantic document is not just blocks.** v0.2 documents contain ordered
  document items: renderable blocks, top-level value declarations, schema
  declarations, template declarations, and directives.

Worked example. `# Title` parses into a surface CST:

```text
atxHeading
├── hashRun "#"
├── whitespace " "
├── inlineText "Title"
└── optional blockId
```

and lowers to the semantic node:

```liminal
@Heading{level: 1}[Title]
```

Both representations coexist. The CST is the parse; the semantic node is the
meaning.

---

## Architectural Layers

```text
source text
  -> LiminalParser / GreenTreeBuilder
Cambium CST             exact bytes, delimiters, trivia, ranges, errors
  -> typed CST overlay
Typed CST overlay       ergonomic Swift views over source forms
  -> LiminalLowerer
LiminalDocument         ordered document items, schema-validated
  -> rendering / editing / indexing / vault
```

Each layer talks only to its neighbors. The CST never knows about schemas. The
renderer and workspace index never rescan raw strings once equivalent CST
extraction exists.

The semantic model must evolve from a blocks-only document to an item-oriented
document. It should still expose a renderable block subset for UI rendering.

---

## Roadmap

### Phase 0 - Lock the CST Contract

Replace the four-case stub `LiminalKind` with the first real surface
vocabulary, derived via `@CambiumSyntaxKind`.

Before using Cambium macros or typed overlay support, update the Xcode target
dependencies so the app can import the required Cambium products. Either add
`CambiumSyntaxMacros` and `CambiumASTSupport` directly, or switch the app target
to the aggregate `Cambium` product if that keeps dependency management simpler.
Confirm the app target and test target still build before changing syntax code.

Use stable raw-value ranges with gaps:

- `1-9`: trivia, currently whitespace and newline.
- `10-99`: tokens, including static punctuation and dynamic text tokens.
- `100-199`: block/document-item nodes.
- `200-299`: inline nodes.
- `300-399`: value/schema/template structural nodes.
- `900-999`: sentinels, including `missing` and `error`.

The current scaffold places `.missing = 198` and `.error = 199` inside the new
block/document-item band. Move them into the 900-999 sentinel band as part of
this phase; together with the new kinds, this is what drives the
`serializationVersion` bump.

Token classification rules:

- Static-text punctuation uses `@StaticText`.
- Dynamic text uses token cases such as identifiers, qnames, scalar literals,
  inline text, code text, math text, HTML text, frontmatter text, and raw
  payload text.
- Comments are not trivia. They are first-class CST nodes.
- `LiminalLanguage` must override `isTrivia(_:)` to return true for the new
  trivia kinds; it currently inherits the `false` default.
- Use `largeToken` for long raw payloads: code bodies, frontmatter YAML, block
  math, raw HTML, comments, and similar text.
- Use interned short tokens for identifiers, qnames, anchors, and scalar
  literals.

The initial kind set should cover the first two parser slices plus category
slots for document items, schema/template/directive nodes, reserved raw
`MathBlock` / `HtmlBlock` fences, and embed variants. Later slices may extend
the vocabulary without renumbering existing cases.

Exit criteria:

- `LiminalKind` has stable bands and correct node/token/trivia classification.
- `LiminalLanguage.serializationVersion` bumps.
- The existing scaffold tests in `LiminalTests/SyntaxTests.swift` that pin
  `.sourceText` and the old kind taxonomy are rewritten against the new bands.
- New tests pin the classifications that parser slice 1 depends on.

### Phase 1 - Typed CST Overlay Scaffold

Add typed wrappers as parser slices land, using `@CambiumSyntaxNode` the same
way `cambium/Examples/Calculator/Sources/CalculatorCore/CalculatorTypedAST.swift`
does.

Rules:

- Each wrapper stores only a `SyntaxNodeHandle`.
- Accessors compute by walking the underlying tree.
- Use tagged-union dispatch points such as `DocumentItemSyntax`,
  `BlockSyntax`, `InlineSyntax`, and `ValueSyntax`.
- Do not pre-build wrappers for constructs the parser does not emit yet.

Exit criteria:

- Typed-overlay infrastructure compiles: `LiminalSyntaxNode`,
  `LiminalTokenSyntax`, the `DocumentItemSyntax` / `BlockSyntax` /
  `InlineSyntax` / `ValueSyntax` union dispatch points, shared traversal
  helpers, and `RootSyntax`.
- Scaffold tests pin the current root shape and the empty-union dispatch.
- Per-construct typed wrappers (`ParagraphSyntax`, `AtxHeadingSyntax`,
  `MdLinkSyntax`, etc.) add cases to the union dispatch points incrementally
  as their parser slices land; they are not pre-built in this phase.

### Phase 2 - Parser Slices

Build parser, kinds, overlays, lowerer, and tests in lockstep.

1. **Slice 1 - minimum note spine.** Root, blank lines, paragraphs, ATX
   headings, inline text runs, code spans, markdown links/images, wikilinks,
   and wiki embeds. This proves source -> CST -> overlay -> document items ->
   document index.
2. **Slice 2 - generic typed and value syntax.** `@Type#id{fields}[inline]`,
   `:::Type#id{fields}\n...\n:::`, scalars, records, lists, references,
   structured embeds `!{Type}[label](target)`, inline literals `@[...]`, and
   block literals `@{...}`. This slice includes reserved-name hooks for raw
   `MathBlock` and `HtmlBlock` fences even if their full payload behavior lands
   later.
3. **Slice 3 - block IDs and index extraction.** Trailing block IDs on
   paragraphs, headings, and list items. Walk the CST to populate heading
   anchors, block anchors, wikilinks, wiki embeds, markdown links, and
   structured embeds in `DocumentIndex`.
4. **Slice 4 - recursive containers.** Ordered/unordered/task lists,
   blockquotes, nesting, continuation indentation, and no lazy continuation.
5. **Slice 5 - content blocks and rich inline.** Fenced code, `MathBlock`,
   frontmatter, comment blocks, inline comments, strikethrough, highlights,
   inline footnotes, and `\(...\)` inline math. Bare `$...$` remains text.
6. **Slice 6 - high-complexity surfaces.** Pipe tables and explicit
   `HtmlBlock` raw fences. Do not parse raw `<tag>` lines as HTML blocks.
7. **Slice 7 - language-level items.** `::use` directives, `&` references,
   `:::schema` blocks, `:::template` blocks, and template control structures.

Per-slice discipline:

- `tree.makeString() == source`.
- Source ranges are correct on emitted nodes and tokens.
- Parser recovery uses `missing` / `error` sentinels and does not throw away
  source.
- Recognized incomplete syntax recovers into the CST; parser control flow must
  not throw merely because source is malformed.
- Each slice records its incremental reuse candidates.
- Tests assert narrow contracts instead of broad golden CST dumps.

### Phase 3 - Lowerer and Semantic Model

`LiminalLowerer.lower()` walks the typed overlay and produces a
`LiminalDocument` with ordered document items. Renderable blocks remain a
derived view of those items.

Construct lowering:

- Paragraph -> `Paragraph`.
- ATX heading -> `Heading`.
- Markdown link -> `Link`.
- Markdown image -> `Image`.
- Code span -> `CodeSpan`.
- Soft/hard break -> `SoftBreak` / `HardBreak`.
- Wikilink -> `WikiLink`.
- Wiki embed -> `WikiEmbedInline` or `WikiEmbedBlock`.
- Structured embed -> `EmbedInline`, `EmbedBlock`, or `EmbedValue`.
- Frontmatter -> `Frontmatter`.
- Generic typed constructors -> unresolved/resolved `LiminalNode` carrying the
  source qname.

Document-item lowering:

- Renderable blocks (paragraph, heading, list, code block, etc.) -> block
  document item.
- Top-level value declaration -> value document item carrying the resolved
  `LiminalNode`.
- `:::schema` block -> schema document item.
- `:::template` block -> template document item.
- `::use` directive -> directive document item.

The Swift shape evolves from `LiminalDocument.blocks: [LiminalBlock]`
(`Liminal/Semantics/Model.swift`) to `LiminalDocument.items:
[LiminalDocumentItem]`, where `LiminalDocumentItem` is a tagged union over
renderable block, value declaration, schema declaration, template declaration,
and directive. The existing `blocks` field becomes a derived view (or is
removed once consumers migrate).

Schema validation starts with the required v0.2 prelude shape. The existing
`LiminalPrelude.declarations` (`Liminal/Semantics/Schema.swift`) must be
reshaped, not just extended:

- `Document` switches from `blocks: [blocks]` to `items: [DocumentItem]`, and
  a `DocumentItem` variant type is added.
- The current single inline `Math` and `Html` types split into `MathBlock` /
  `MathInline` and `HtmlBlock` / `HtmlInline`.
- `CodeBlock` gains an optional `info` field alongside `language` and `text`.
- Add `Frontmatter`, `ThematicBreak`, `BlockQuote`, `List`, `ListItem`,
  `CommentBlock`, `EmbedBlock`, `EmbedInline`, `EmbedValue`, `WikiLink`,
  `WikiEmbedBlock`, `WikiEmbedInline`, `SoftBreak`, `HardBreak`, `Emphasis`,
  `Strong`, `Strikethrough`, `Highlight`, `FootnoteInline`, `CommentInline`,
  and `Interpolation`.

`PreludeSchemaTests.swift` hard-pins the current type list and field shapes;
it must be rewritten alongside the prelude.

The schema pass annotates resolution and validation diagnostics. It never
rewrites the CST. The current `SchemaValidator.validate(_:against:)`
(`Liminal/Semantics/Schema.swift`) is a no-op stub; replace it with the
prelude-shape validation pass described above as part of this phase.

### Phase 4 - Workspace Migration onto the CST

`Liminal/Workspace/LiminalWorkspace.swift` currently keeps vault links and
indexes independent of the parser. `VaultLinkIndex` already consumes explicit
`DocumentIndex` values; the missing piece is a CST-backed `DocumentIndex`
extractor. Once slice 3 lowers/indexes headings, wikilinks, embeds, and block
IDs, build that extractor from the CST:

- Heading anchors come from `AtxHeadingSyntax`.
- Block anchors come from a trailing `blockId` token on supported blocks/items.
- References come from `WikiLinkSyntax`, `WikiEmbedSyntax`, `MdLinkSyntax`, and
  structured embed syntax.

Keep the existing `WikiTarget`, `DocumentIndex`, and `VaultLinkIndex` concepts.
Do not redesign vault resolution in this phase, and do not introduce or retain
ad hoc string extraction once equivalent CST extraction exists.

### Phase 5 - Printer

Lossless mode:

- Walk the CST and concatenate token text.
- Preserve original trivia, delimiters, source forms, field order, and raw
  payloads.

Canonical mode:

- Walk semantic document items.
- Emit canonical generic typed syntax when no safe surface printer is
  available.
- Use registered surfaces only when `parse(print(node)) == node`.
- Order fields by schema declaration order.

Canonical printing becomes useful after enough prelude document items lower;
do not block early parser slices on it.

### Phase 6 - Incremental Reuse Wiring

Wire `IncrementalParseSession`, `ParseInput`, and `ReuseOracle` into
`LiminalParseSession`. The existing `edits: [TextEdit]` parameter becomes
load-bearing here.

Reusable kinds must be atomic, self-bounded subtrees whose meaning does not
depend on caller context.

Good reuse candidates:

- `paragraph`
- `atxHeading`
- `fencedCodeBlock`
- `mathBlock`
- `htmlBlock`
- `commentBlock`
- `typedBlock`
- `frontmatter`
- `pipeTable`
- `wikilink`
- `wikiEmbed`
- `mdLink`
- `codeSpan`

Excluded initially:

- emphasis/strong/highlight delimiter chains, because adjacent delimiter
  context can change associativity and recovery.

Reuse boundary decisions are made during parser slices. Phase 6 wires the
mechanism.

### Phase 7 - Editor and Semantic Operations

Once a useful subset lowers and indexes, replace the SwiftUI template
`ContentView` with a real editor:

- macOS-first `NSTextView`-backed editor driven by `LiminalEditorSession`.
- Edits flow through Cambium replacement APIs.
- Replacement witnesses carry selections, diagnostics, and fold/navigation
  state across edits.
- Prefer the concrete Cambium replacement path
  `SharedSyntaxTree.replacing(_:with:context:)` when wiring edits.
- Semantic operations use the typed overlay: rename heading, toggle task item,
  update wikilink target, wrap selection in emphasis, convert paragraph to
  heading.
- Rendering consumes `LiminalDocument` document items and their renderable
  block subset.

---

## Locked v0.2 Decisions

These are no longer open design questions:

| Decision | v0.2 position |
|---|---|
| Compatibility target | Liminal is not CommonMark, GFM, or Obsidian compatible. |
| Comments | First-class CST and semantic nodes, not trivia. |
| Inline math | `\(...\)` only; bare `$...$` is text. |
| Setext headings | Not part of v0.2. |
| Raw HTML | Only explicit `HtmlBlock` / `HtmlInline`; raw `<tag>` does not start HTML. |
| Block IDs | Trailing `blockId` slot on paragraphs, headings, and list items. |
| Wikilinks and embeds | Required prelude types: `WikiLink`, `WikiEmbed*`, `Embed*`. |
| Markdown image | Lowers to `Image`, not `EmbedInline`. |
| Frontmatter | Lowers to `Frontmatter`, not a special field on `Document`. |
| Typed block fence length | Store colon runs dynamically and require exact closing length. |

---

## Cross-Cutting Concerns

- **Diagnostics.** Parser diagnostics carry source ranges and keep the CST
  well-formed. Follow the calculator pattern: the parser owns a
  `[LiminalDiagnostic]` accumulator and attaches diagnostics when finishing the
  parse. Schema diagnostics are separate.
- **Document items.** Any blocks-only document model must move to ordered items
  plus a renderable block view.
- **Source provenance.** Semantic document items may retain CST/source
  provenance through `SurfaceInfo` / `SurfaceForm`, and `LiminalDocument` may
  retain the syntax tree. Semantic consumers should not own raw source text or
  reparse strings.
- **`GreenTreeContext` namespace stability.** Keep parse-session context
  threaded consistently with `policy: .parseSession(maxEntries: 16_384)` until
  there is a measured reason to change it. Interner collisions become silent
  reuse bugs.
- **Serialization version policy.** Bump `serializationVersion` when syntax
  kind meaning changes during phases 0-2. Treat these as pre-stability bumps,
  and do not ship persisted snapshots from pre-stability versions.
- **Test contracts, not snapshots.** Prefer source round-trip, source ranges,
  typed overlay accessors, lowerer output, and workspace link semantics over
  broad golden tree dumps.

---

## Exit Criteria per Phase

- **Phase 0.** `LiminalKind` has stable v0.2 category coverage and correct
  Cambium classification.
- **Phase 1.** Slice 1 typed overlays compile.
- **Phase 2 slice N.** Constructs round-trip losslessly, ranges are correct,
  recovery emits sentinels, and reuse candidates are recorded.
- **Phase 3 per slice.** `LiminalDocument` document items populate correctly,
  renderable block views work, and prelude validation runs.
- **Phase 4.** `DocumentIndex` is extracted from the CST, and `VaultLinkIndex`
  builds from those CST-derived indexes without ad hoc source scanning.
- **Phase 5.** Lossless print walks real CST tokens; canonical print emits
  schema-ordered typed syntax for lowered document items.
- **Phase 6.** Reparses with edits demonstrably reuse eligible subtrees.
- **Phase 7.** The editor opens, renders, edits, navigates, and indexes a real
  `.lim` document.

---

## The Next Concrete Step

Already shipped:

- **Phase 0** (`9498111`): Cambium product dependencies, the v0.2 kind
  taxonomy with stable raw bands, `serializationVersion` bump to 2, and
  pinned language classification tests.
- **Phase 1** (`c593936`): typed-overlay infrastructure
  (`LiminalSyntaxNode`, `LiminalTokenSyntax`, the four union dispatch points,
  shared traversal helpers, and `RootSyntax`) plus scaffold tests that pin
  the current root shape and the empty-union dispatch.

Remaining slice 1 work, split into two PRs:

1. **Slice 1 block spine.** Implement root, blank lines, paragraphs, and ATX
   headings in `LiminalParser`. Add per-construct typed wrappers
   (`ParagraphSyntax`, `AtxHeadingSyntax`, `BlankLineSyntax`) and extend
   `DocumentItemSyntax` / `BlockSyntax` to dispatch to them. Lower to ordered
   document items and a renderable block view. Drop the Phase 0/1 root
   scaffold: the single `.rawPayloadText` token emitted under `.root` by the
   parser, the `RootSyntax.tokens` / `tokens(kind:)` / `rawPayloadToken`
   accessors, and the `typedRootOverlayExposesCurrentScaffoldTokens` test
   that pins them.
2. **Slice 1 inline and index extension.** Add inline text, code spans,
   markdown links/images, wikilinks, and wiki embeds. Add their typed
   wrappers and `InlineSyntax` dispatch cases, lower them, and build a
   CST-derived `DocumentIndex`.

Together these PRs complete the source -> CST -> overlay -> document items
-> index spine. Every subsequent slice repeats the same pattern with new
constructs.
