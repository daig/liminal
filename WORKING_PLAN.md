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
  ├─> LiminalLowerer       -> LiminalDocument   -> rendering / editing
  └─> DocumentIndexBuilder -> DocumentIndex     -> vault navigation
```

Lowering and indexing are sibling consumers of the typed overlay. Indexing
does not depend on the lowerer; it reads provenance from CST tokens
directly so vault navigation stays schema-independent and gets sub-token
ranges. Each layer talks only to its neighbors. The CST never knows about
schemas. The renderer and workspace index never rescan raw strings.

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
3. **Slice 3 - block IDs.** Trailing `^block-id` suffix on paragraphs,
   headings, and (where they exist) list items. Parser emits
   `blockIdSuffix`, typed overlay exposes `blockIdToken:
   LiminalTokenSyntax?`, lowerer sets `LiminalNode.id`, and
   `DocumentIndexBuilder` adds a `BlockAnchor` from the suffix's anchor-
   text token range. Heading-anchor and reference extraction shipped
   pre-slice-3 with the CST-indexer migration.
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

### Phase 3 - Semantic Model and Schema Validation

Most of the originally-planned Phase 3 scope shipped incrementally during
Phase 2. The lowerer (`Liminal/Semantics/Pipeline.swift`) covers every
typed-overlay construct through slice 7; `LiminalDocument.items:
[LiminalDocumentItem]` exists with `.block` / `.value` / `.schema` /
`.template` / `.directive` cases; document-item lowering is wired for
all five. What remains is prelude validation, structured schema-body
parsing, and template execution semantics — three sub-arcs ordered by
dependency.

**Phase 3a - Prelude reshape and base schema validator.** Self-contained;
no dependencies on later sub-arcs.

- Reshape `LiminalPrelude.declarations` (`Liminal/Semantics/Schema.swift`)
  to v0.2 §11. `Document` switches from `blocks: [blocks]` to `items:
  [DocumentItem]` plus a `DocumentItem` variant type. Split the current
  single inline `Math` and `Html` into `MathBlock` / `MathInline` and
  `HtmlBlock` / `HtmlInline`. Add an optional `info` field to `CodeBlock`.
  Add the missing v0.2 prelude types: `Frontmatter`, `ThematicBreak`,
  `BlockQuote`, `List`, `ListItem`, `CommentBlock`, `EmbedBlock`,
  `EmbedInline`, `EmbedValue`, `WikiLink`, `WikiEmbedBlock`,
  `WikiEmbedInline`, `SoftBreak`, `HardBreak`, `Emphasis`, `Strong`,
  `Strikethrough`, `Highlight`, `FootnoteInline`, `CommentInline`,
  `Interpolation`.
- Rewrite `LiminalTests/PreludeSchemaTests.swift` (currently hard-pins
  the stale list).
- Replace `SchemaValidator.validate(_:against:)` no-op stub
  (`Liminal/Semantics/Schema.swift`) with a prelude-shape validation
  pass over the lowered tree. Diagnostics are separate from parser
  diagnostics; the validator never rewrites the CST or the lowered
  document.

**Phase 3b - User schemas and reference resolution.** Depends on Phase 3a.

- Parse `:::schema` block bodies into structured `TypeDecl` / `TypeExpr`
  per spec §9, replacing today's `largeToken(.schemaText)` raw text.
  Add typed-overlay accessors for the parsed declarations.
- Parse `::use` directive bodies into `UseKind? StringOrBare
  ImportFilter? ImportAlias?` per spec §5, replacing today's raw
  `directiveText`. Pairs naturally with reference resolution since
  resolution is the consumer.
- Resolve user-defined types: `@CustomLink{...}` resolves against the
  union of prelude + `:::schema`-declared types + `::use`-imported
  types. Unresolved typed constructors stay valid CST and produce
  validation diagnostics, never parse errors.

**Phase 3c - Template syntax (parsing only).** Depends on Phase 3a;
can run in parallel with 3b. **Scope clarified: v1 parses, validates,
and round-trips template syntax. Template *execution* and related
deep-semantics work are deferred post-v1 (see "Deferred from v1"
below).**

In-scope and shipped:

- Parse template signatures (`Card(person: Person) -> blocks`)
  structurally per §10, replacing the raw `templateText` payload.
- Parse interpolation expressions (`${person.name ?? fallback}`) per
  spec §7.14 (NullCoalesce / Projection / Primary / Literal),
  replacing the raw `interpolationText` payload.
- Resolve `:::if` and `:::for` as reserved prelude types so the
  validator handles their field shapes and reserved-name
  redeclaration is an error. The lowered representation is a
  generic typed-block node with the reserved type name; a
  specialized `LiminalTemplateControl` variant is **not** part of v1
  (see deferral note).

Followed by:

- **Phase 3.5 — correctness sweep.** Field separator enforcement
  for both record parsers; unmatched `<` and chained `??`
  diagnostics; reserved-name protection elevated to error;
  `SchemaTypeExpression.unknown` → `.deferred` rename.

### Phase 4 - Workspace Migration onto the CST

Shipped via the CST-indexer migration (`a128aa2`) and slice 3
(`5ab3b73`). `DocumentIndexBuilder` walks `RootSyntax` directly;
`DocumentIndex.build(from:)` does not go through the lowerer; references
carry both `sourceRange` (whole construct, cursor containment) and
`targetRange` (sub-token, hover / Cmd-click / rename); `VaultLinkIndex`
propagates `targetRange` into `ResolvedReference`;
`reference(containing:)` returns the innermost match; heading anchors
are top-level only; block anchors come from
`paragraph.blockIdToken` / `atxHeading.blockIdToken`.

Markdown link/image destination indexing and structured embed target
indexing are intentionally not in Phase 4. They unblock with Phase 4.5
below.

### Phase 4.5 - External-URI Policy

Markdown link/image destinations and structured embed targets are not
indexed today because `WikiTarget.parse` / `LinkActivationPolicy.decision`
cannot distinguish external URIs (`https://example.org`) from
vault-relative paths. Indexing them now would let an external URL flow
into `LinkActivationPolicy.decision` as `.createNote(relativePath:
"https://...")` — Cmd-clicking would attempt to create a literally-named
note.

Scope:

- Extend `WikiTarget` (or successor) to model external URI versus
  vault-relative path as distinct cases.
- Update `LinkActivationPolicy.decision` for external targets (open in
  default handler, no auto-create).
- Once the policy lands, extend `DocumentIndexBuilder` to emit
  `DocumentReference`s from `MdLinkSyntax` / `MdImageSyntax`
  destinations and `StructuredEmbed*Syntax` targets. Token accessors
  already exist (`destinationTextToken`, `targetTextToken`).
- Decide whether image destinations should be `kind: .link` or
  `kind: .embed` (asset embedding is a separate navigation concern).

Vault navigation stays correct without this work; closing the gap is
about reach, not correctness. May reshuffle ahead of Phase 3 if editor
work in Phase 7 needs it sooner.

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
- `wikiEmbedBlock`
- `mdLink`
- `mdImage`
- `codeSpan`

Excluded initially:

- emphasis/strong/highlight delimiter chains, because adjacent delimiter
  context can change associativity and recovery.
- `inlineContent`, because the same kind is emitted under headings,
  paragraphs, link labels, and wikilink aliases with diverging stop rules;
  reusing across contexts would silently apply the wrong ones.

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
  provenance through `SurfaceForm`, and `LiminalDocument` may retain the
  syntax tree. The workspace indexer reads provenance from CST tokens
  directly (not from `SurfaceForm`); any future consumer needing
  sub-token range fidelity should follow the same pattern. No semantic
  consumer should own raw source text or reparse strings.
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

- **Phase 0** [satisfied: `9498111`]. `LiminalKind` has stable v0.2
  category coverage and correct Cambium classification.
- **Phase 1** [satisfied: `c593936`]. Typed-overlay infrastructure
  compiles.
- **Phase 2** [satisfied: slices 1-7 plus `e9ff413`]. Constructs round-
  trip losslessly, ranges are correct, recovery emits sentinels, reuse
  candidates are recorded, same-colon-count nesting works.
- **Phase 3a.** Prelude matches v0.2 §11; `PreludeSchemaTests` rewritten;
  `SchemaValidator.validate` runs prelude-shape validation against
  lowered documents.
- **Phase 3b.** `:::schema` bodies and `::use` directive bodies parse
  structurally; reference resolution unifies prelude with user-defined
  types.
- **Phase 3c (v1 scope).** Template signatures and interpolation
  expressions parse structurally; `:::if` / `:::for` resolve through
  reserved prelude entries (lowered as generic typed-block nodes
  named `if` / `for`). Specialized `LiminalTemplateControl`
  lowering and template execution are explicitly deferred from v1.
- **Phase 3.5.** Correctness sweep: record-field separators required;
  unmatched-`<` and chained-`??` diagnostics; reserved-name
  protection for `if`/`for` elevated to error; `.unknown` → `.deferred`.
- **Phase 4** [satisfied: `a128aa2` + `5ab3b73`]. `DocumentIndex` is
  extracted from the CST and exposes sub-token `targetRange` alongside
  containment `sourceRange`; `VaultLinkIndex` builds without ad hoc
  source scanning; block anchors come from CST suffix tokens.
- **Phase 4.5.** `WikiTarget` distinguishes external URIs from vault-
  relative paths; markdown destinations and structured embed targets
  are indexed and route through correct activation policy.
- **Phase 5.** Lossless print walks real CST tokens; canonical print
  emits schema-ordered typed syntax for lowered document items.
- **Phase 6.** Reparses with edits demonstrably reuse eligible subtrees.
- **Phase 7.** The editor opens, renders, edits, navigates, and indexes
  a real `.lim` document.

---

## Deferred from v1

Template-related work beyond *parsing and validation* is intentionally
out of scope for v1. We built the parsing and lowered-model
infrastructure upfront so future template work can plug in cleanly,
but no v1 consumer runs templates. The dormant artifacts below stay
in the codebase because removing them now (only to re-introduce them
later) costs more than carrying them — they are small, tested, and
do not constrain other code.

**Dormant lowered-model surface (kept, no v1 consumer)**:

- `LiminalTemplateBlock.parsedSignature: LiminalTemplateSignature?`
  and the `LiminalTemplateSignature` / `LiminalTemplateParameter` /
  `LiminalTemplateResult` types in `Liminal/Semantics/Model.swift`.
- `LiminalUserSchemaTypeDeclaration.templateSignature`.
- `lowerTemplateSignature` in `Liminal/Semantics/Pipeline.swift`.

**Explicitly deferred work** (no commitment to ever ship):

- **Template execution engine.** Evaluating `:::template Card(p:
  Person) -> blocks` against an actual value of type `Person` and
  producing the rendered blocks.
- **Specialized `LiminalTemplateControl.if/.for` lowered variants.**
  The plan originally called for these in Phase 3c; v1 instead uses
  the generic typed-block representation with reserved prelude
  entries (Indep-4 resolution). When (if) template execution lands,
  the specialized variants land alongside it where a concrete
  consumer can inform the variant shape.
- **Template invocation validation.** Validating `@PersonCard{p:
  ada}` against the declared signature.
- **Field-value template-expression parsing.** `:::if{test:
  person.bio}` captures `person.bio` as a bare scalar today; lowering
  it as a parsed §7.14 template expression is deferred.
- **Deferred TypeExpr forms inside schemas.** `map<T>` / `ref<T>` /
  `embed<T>` / `enum {…}` / `variant by …` parse to the `.deferred`
  sentinel; structural lowering of these forms is a separate
  schema-completeness slice, not coupled to template execution.

**What v1 *does* support for templates**:

- Byte-accurate parse and round-trip of `:::template`, `:::if`,
  `:::for`, `::use`, `${…}`, and `type … : template = …`.
- Validation through reserved prelude entries (`:::if{test: …}`
  flags missing fields, unknown fields, kind mismatches).
- Reserved-name protection: user redeclaration of `if` / `for` is
  an error.
- Structured access to template signatures via the typed overlay
  and lowered model for any future consumer.

If templates re-enter v1 scope, the path back in is "build the
executor against the existing lowered surface" rather than "redo
the parser." That's the whole point of the deferral shape.

---

## The Next Concrete Step

Already shipped:

- **Phase 0** (`9498111`): Cambium product dependencies, the v0.2 kind
  taxonomy with stable raw bands, `serializationVersion` bump, and pinned
  language classification tests.
- **Phase 1** (`c593936`): typed-overlay infrastructure
  (`LiminalSyntaxNode`, `LiminalTokenSyntax`, the four union dispatch
  points, shared traversal helpers, and `RootSyntax`).
- **Slice 1** (`d0c7fb0`): root, blank lines, paragraphs, ATX headings,
  inline text, code spans, markdown links/images, wikilinks, and wiki
  embeds, with typed overlays and lowering to ordered document items.
- **Slice 2** (`ccbe1f8`): generic typed and value syntax — typed
  constructors, typed blocks, structured embeds, scalars, records, lists,
  references, inline/block literals, and reserved raw `MathBlock` /
  `HtmlBlock` fences.
- **Indexer items-walk fix** (`52756b1`): `DocumentIndex.build` walks
  `document.items` and recurses through field values so wikilinks/embeds
  inside top-level value declarations or typed-block bodies are no
  longer dropped.
- **CST-based indexing migration** (`a128aa2`): `DocumentIndexBuilder`
  walks `RootSyntax` directly; sub-token `targetRange` on references;
  innermost-match containment; top-level-only heading anchors. Most of
  Phase 4's scope ships here.
- **Slice 3** (`5ab3b73`): trailing `^block-id` suffix on paragraphs and
  ATX headings, through parser, typed overlay, lowerer
  (`LiminalNode.id`), and `DocumentIndexBuilder` (`BlockAnchor` from
  `blockIdToken`). Completes Phase 4.
- **Slice 4** (`bde0148`): recursive containers — ordered/unordered/task
  lists, blockquotes, nesting, continuation indentation; lazy
  continuation rejected.
- **Slice 5** (`41ee006` + `79683bc`): content blocks and rich inline —
  fenced code, `MathBlock`, frontmatter, comment blocks, inline
  comments, strikethrough, highlights, inline footnotes, `\(...\)`
  inline math.
- **Slice 6** (`ea9a1f1` + `abc6fdd`): high-complexity surfaces — pipe
  tables and explicit `:::HtmlBlock` raw fences.
- **Slice 7** (`597b51f`): language-level items — `::use` directives
  (raw body), `:::schema` blocks (raw body), `:::template` blocks
  (parsed body with interpolation), `${...}` interpolation parsing
  (raw expression), and an external-reference cursor fix. Schema bodies,
  `::use` bodies, template signatures, and interpolation expressions
  are intentionally raw text; structured parsing pairs with their
  consumers in Phase 3.
- **Typed-block nesting fix** (`e9ff413`): `closingFenceLineIndex`
  tracks same-colon-count nesting via `nestedDepth`; the duplicate
  `templateClosingFenceLineIndex` is gone. Phase 2 cleanup.

Next: **Phase 3a — prelude reshape and base schema validator.** Reshape
`LiminalPrelude.declarations` (`Liminal/Semantics/Schema.swift`) to
match v0.2 §11, rewrite `LiminalTests/PreludeSchemaTests.swift`, and
replace the `SchemaValidator.validate(_:against:)` no-op stub with a
prelude-shape validation pass. Self-contained; no dependencies on later
sub-arcs.
