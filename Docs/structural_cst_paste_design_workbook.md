# Structural CST Paste Design Workbook

This is the working document for structural copy/paste design. It ties together
the source-side extraction inventory and the target-side paste matrix, then
groups future design work into thematic chunks.

Use this file to record decisions as we make them. The two matrix documents
remain the detailed inventories:

- `Docs/structural_cst_extraction_pairs.md`
  - Source-side inventory.
  - Tracks copied `(wrapperKind, childKinds)` fragment shapes.
  - Answers: "Do we understand the logical meaning of this copied fragment?"
- `Docs/structural_cst_paste_matrix.md`
  - Target-side operation inventory.
  - Tracks source/target/intent triples.
  - Answers: "Can this logical payload be pasted through a block, nest, or
    splice intent at this target?"

## Guiding Model

Structural paste has two independent halves.

1. Extraction gives copied content independent meaning.
   - A copied fragment is a green snapshot plus source projection metadata.
   - Projection removes source-context syntax that should not be part of the
     logical payload, such as list base indent or one block quote layer.
   - Extraction should not know the future paste target.

2. Paste lands on a target and adapts the logical payload into that target
   context.
   - Block paste lands a document-item slot.
   - Splice paste lands a sibling slot in the target parent's child sequence.
   - Nest paste starts from a container node, then derives an interior slot.
   - Primitive operations should reject invalid source/target pairs rather
     than guessing intent.

Higher-level UI can later sit above these primitives and choose between valid
operations, such as "paste as block," "paste into quote," or "splice list
items."

## First-Class Slots

Structural paste uses the same Lift / Traverse / Land / Apply grammar as other
structured commands, but it needs one additional first-class structural target:
the CST slot.

- Cursor position is text-space input to Lift, not a structural edit target.
- CST node is one structural object. It can be inspected, mutated, or used to
  derive an interior slot.
- CST forest is contiguous sibling children plus their parent role. It is the
  right target for yank, delete, change, and future replace.
- CST slot is a typed boundary in a parent/container child sequence. It is the
  right target for insert, splice, and paste.

This gives the paste algebra:

- `Forest -> Payload` for yank/copy.
- `Slot x Payload -> Edit` for insertion, including block paste and splice
  paste.
- `Node x Payload -> interior Slot x Payload -> Edit` for nest paste.
- `Forest x Payload -> Edit` for future replacement.

Slots mirror forests. A forest is selected children plus a parent role; a slot
is a child boundary plus a parent/sequence role. Slot roles include
`root.documentItems`, `list.items`, `listItem.interior`,
`blockQuote.documentItems`, `pipeTable.rows`, `pipeTableRow.cells`,
`inlineContent.children`, `fields.children`, and `listValue.values`.

Stable slot anchors should identify the parent/container, the sequence role,
and a boundary anchor such as `atStart`, `atEnd`, `before(reference child)`,
`after(reference child)`, or a `between(left, right, affinity)` gap. Resolved
slots are current-tree execution targets with parent handles, insertion child
index, byte offset, and neighbor metadata.

Block, splice, append-inside, and prepend-inside are different ways to acquire
a slot. They are not separate target-rendering families. Once Land has produced
a typed slot, Apply chooses rendering from the logical payload family, the slot
role, and local boundary context.

## Current Baseline

Implemented extraction families:

- `root` -> document item children, identity projection.
- `list` -> `listItem` children, `listItems` projection.
- `listItem` -> direct content children, `listItemContent` projection.
- `blockQuote` -> document item children plus direct quote prefix tokens,
  `blockQuoteContent` projection.

Implemented paste intent coverage:

- Block paste for root document item payloads, list payloads, list item content,
  and block quote content.
- Nest paste into list items for list payloads and paragraph/blank-line text.
- Splice paste into list child sequences for list item sequences and projected
  list child content.

Canonical Ex command surface:

- `:CSTPasteBlock`
- `:CSTPasteNest`
- `:CSTPasteSplice`

## Thematic Design Chunks

### 1. Lists

Status: mostly implemented; needs cleanup/design pass.

Scope:

- Root list block vs list item sequence.
- Child list selected through list item content.
- Paragraph/content selected from list item.
- Block-to-list nesting.
- Root-list splice semantics.
- Marker/blank-line target intent.

Current decisions:

- List item sequence extraction is a logical list item sequence, not a whole
  document block.
- List item content extraction removes the selected item's structural prefix
  and continuation indentation.
- Splice is precise and should not retarget from arbitrary cursor positions.

Open decisions:

- Should root `list` block payload be accepted by list-item splice by extracting
  its items operation-locally, or should users explicitly copy a list item
  sequence?
- Should any root document item be nestable as a new list item, or only
  paragraph-like payloads?
- What UI should expose "paste as child list" vs "splice as siblings" when both
  are valid?

### 2. Block Quotes

Status: source projection exists; target slot/rendering support is deferred.

Scope:

- Block quote content extraction.
- Paste into quote vs paste beside quote.
- Nested quote depth.
- Quote + list interactions.
- Quote prefix insertion/removal.

Current decisions:

- Copying content from a block quote strips exactly one quote layer from the
  logical payload.
- Cursor position alone is not enough to distinguish "inside quote" from
  "beside quote" in all cases.
- Nesting into a block quote targets the `blockQuote` container.
- Splicing inside a block quote targets a precise child slot in the quote's
  document-item sequence.
- Copying a whole block quote block and pasting it into another quote preserves
  the copied block quote as a document item, so it becomes a nested quote.

Open decisions:

- What UI gesture or target picker should choose block quote nest vs block
  quote splice?
- How should quoted list content combine quote prefixing with list indentation?
- Should inline text copied structurally into a quote auto-wrap as a quoted
  paragraph, or should inline paste stay separate?

#### Target Semantics

For block quote targets, "nest" and "splice" should use the same source
projection rules and eventually lower to the same `blockQuote.documentItems`
slot renderer. They differ in how that slot is acquired.

- Nest into block quote:
  - target intent names a `blockQuote` container;
  - derive an interior `blockQuote.documentItems` slot inside that quote;
  - this is the operation users mean by "paste into this quote."
- Splice into block quote:
  - target intent names a precise `blockQuote.documentItems` child slot;
  - this is the structural sibling operation and should not retarget from an
    arbitrary cursor position.

Both operations produce a `blockQuote.documentItems` slot. Apply then renders
compatible logical document-item payloads with one additional block quote prefix
layer. Whole block quote document items remain block quote document items, so
they become nested quotes. Block quote content projections have already removed
one quote layer, so pasting them into a quote restores exactly one layer.

Cell notation below:

- `Quote docs`: parse/copy the logical payload as document items, then inject
  one quote layer.
- `Quote list`: treat the logical payload as list items/list block, normalize
  list indentation, then inject one quote layer.
- `Nested quote`: preserve a copied block quote document item, then inject one
  outer quote layer.
- `Wrap paragraph`: convert inline/plain logical text into a paragraph, then
  inject one quote layer.
- `Reject`: invalid for this operation.
- `Later`: valid direction, but requires a source adapter we do not have yet.

#### Nest Into Block Quote Source Table

Rows are selected child payload shapes. Columns are copied fragment wrappers.

| Selected children | `root` wrapper | `list` wrapper | `listItem` wrapper | `blockQuote` wrapper | `pipeTable`/row/cell wrappers | inline wrappers | value/schema wrappers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Paragraph/heading/thematic break | Quote docs | N/A | Quote docs via `listItemContent` | Quote docs via `blockQuoteContent` | N/A | Later: wrap paragraph | Reject |
| Atomic block: code/math/html/comment/frontmatter/directive/embed | Quote docs | N/A | Quote docs if it parses from item content | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Whole list block | Quote docs | N/A | Quote list via `listItemContent` when child is a list | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| List item sequence | N/A | Quote list | Quote list when selected child is a list | N/A | N/A | N/A | Reject |
| List item content that parses as paragraphs/blank lines | N/A | N/A | Quote docs | N/A | N/A | N/A | Reject |
| Block quote document item | Nested quote | N/A | Nested quote if item content contains a quote block | Nested quote when selected child is `blockQuote` | N/A | N/A | Reject |
| Block quote content | N/A | N/A | N/A | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Whole pipe table block | Quote docs | N/A | Quote docs if it parses from item content | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Pipe table row/header/cell | N/A | N/A | N/A | N/A | Later: table-specific conversion or reject | N/A | Reject |
| Inline sequence/text | N/A | N/A | N/A | N/A | N/A | Later: wrap paragraph | Reject |
| Field/value/schema internals | N/A | N/A | N/A | N/A | N/A | N/A | Reject |

Nest examples:

- Copy root paragraph `hello\n`, nest into quote -> `> hello\n`.
- Copy root block quote `> hello\n`, nest into quote -> `> > hello\n`.
- Copy block quote content from `> hello`, nest into quote -> `> hello\n`.
- Copy nested quote content from `> > hello`, nest into quote -> `> > hello\n`
  because the source projection removes only the outer copied layer.
- Copy root list `- a\n  - b\n`, nest into quote -> `> - a\n>   - b\n`.

#### Splice Inside Block Quote Source Table

Rows are selected child payload shapes. Columns are copied fragment wrappers.
Cells are intentionally almost identical to the nest table; the difference is
that splice requires a precise child slot inside the target quote.

In this table, `Quote list` inserts a quoted list document item into the block
quote. It does not splice list items into an existing list inside the quote;
that remains the list-child-sequence splice operation with a quoted-list target.

| Selected children | `root` wrapper | `list` wrapper | `listItem` wrapper | `blockQuote` wrapper | `pipeTable`/row/cell wrappers | inline wrappers | value/schema wrappers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Paragraph/heading/thematic break | Quote docs | N/A | Quote docs via `listItemContent` | Quote docs via `blockQuoteContent` | N/A | Later: wrap paragraph | Reject |
| Atomic block: code/math/html/comment/frontmatter/directive/embed | Quote docs | N/A | Quote docs if it parses from item content | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Whole list block | Quote docs | N/A | Quote list via `listItemContent` when child is a list | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| List item sequence | N/A | Quote list | Quote list when selected child is a list | N/A | N/A | N/A | Reject |
| List item content that parses as paragraphs/blank lines | N/A | N/A | Quote docs | N/A | N/A | N/A | Reject |
| Block quote document item | Nested quote | N/A | Nested quote if item content contains a quote block | Nested quote when selected child is `blockQuote` | N/A | N/A | Reject |
| Block quote content | N/A | N/A | N/A | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Whole pipe table block | Quote docs | N/A | Quote docs if it parses from item content | Quote docs via `blockQuoteContent` | N/A | N/A | Reject |
| Pipe table row/header/cell | N/A | N/A | N/A | N/A | Later: table-specific conversion or reject | N/A | Reject |
| Inline sequence/text | N/A | N/A | N/A | N/A | N/A | Later: wrap paragraph | Reject |
| Field/value/schema internals | N/A | N/A | N/A | N/A | N/A | N/A | Reject |

Splice examples:

- Given `> one\n> three\n`, splice root paragraph `two\n` after the `one`
  child -> `> one\n> two\n> three\n`.
- Given `> one\n> three\n`, splice root block quote `> two\n` after `one`
  -> `> one\n> > two\n> three\n`.
- Given `> - one\n> - three\n`, splice list item sequence `- two\n` after the
  first quoted list item only if the target is the list inside the quote, not
  the block quote itself. Splicing into the block quote child sequence would
  insert a separate quoted list block.

### 3. Pipe Tables

Status: unsupported beyond whole-table block paste.

Scope:

- Whole table.
- Header.
- Delimiter.
- Body rows.
- Cells.
- Cell content.
- Column count and alignment policy.

Current decisions:

- A whole table selected as a root document item can be block-pasted through
  the generic root path.
- Table delimiter rows are structural glue and should not become normal user
  paste payloads by accident.

Open decisions:

- What should copying a `pipeTableRow` mean independently of a target table?
- Should header rows be pasteable as rows, header replacements, or both?
- How strict should row splice be about column count?
- Should cell paste normalize escaping/alignment immediately or preserve source
  bytes until reformatting?

### 4. Generic Document-Item Containers

Status: root insertion exists; non-root document-item containers are planned.

Scope:

- `typedBlock` body document items.
- `templateBody` document items.
- `blockLiteral` document items.
- Any future parent that owns document item children.

Current decisions:

- Root insertion is really a special case of inserting into a document-item
  child sequence.

Open decisions:

- Which parent kinds should declare "document item sequence" capability?
- Can the root insertion separator rules be reused unchanged inside all such
  containers?
- What target UI identifies a body child slot precisely?

### 5. Typed Fields And Values

Status: not implemented for structural paste.

Scope:

- `fields` -> `field` children.
- `field` -> `value`.
- `value` -> scalar/list/record/constructor/literal/reference payload.
- `listValue` -> value elements.
- `recordValue` -> fields.

Current decisions:

- Typed/value syntax should use value-specific slots rather than being forced
  through document-item slot renderers.

Open decisions:

- Are value operations named block/nest/splice, or do they need value-specific
  names such as replace field, insert element, insert field?
- How should duplicate record fields be handled?
- Should scalar text copy be a structural payload or just plain text?

### 6. Schema And Template Signatures

Status: not implemented for structural paste.

Scope:

- Schema declarations.
- Type expressions.
- Schema fields.
- Variant cases.
- Modifiers.
- Template signatures and parameters.

Current decisions:

- Schema syntax is role-sensitive: the same child kind can have different
  meaning under different wrappers.

Open decisions:

- What source metadata is needed beyond `wrapperKind` and `childKinds`?
- Which schema units are atomic vs spliceable?
- Should schema/template signature editing share value adapters where possible?

### 7. Inline Content

Status: not implemented for structural paste.

Scope:

- Inline text.
- Inline formatting spans.
- Links/images/wiki links.
- Code/math/comment inline nodes.
- Multi-line paragraph content when pasted inline.

Current decisions:

- Inline paste needs a separate design from block/list paste.

Open decisions:

- Does copying a formatting wrapper preserve delimiters or copy logical
  formatted content?
- How should whitespace be inserted around inline payloads?
- What happens when multi-line content is pasted into inline content?

### 8. Links And Embeds

Status: not implemented; could be part of inline work but likely deserves a
focused pass.

Scope:

- `wikiTarget`.
- `embedTarget`.
- `linkLabel`.
- `linkDestination`.
- `linkTitle`.
- Aliases and fallback content.

Current decisions:

- Link/embed target wrappers are role-sensitive.

Open decisions:

- Is the user copying the rendered label, the target, or the whole object?
- How should target-only paste interact with existing link objects?
- Should link/embed payloads expose multiple copy flavors?

### 9. Opaque Raw Blocks

Status: whole-block paste works as document item; raw payload extraction is not
implemented.

Scope:

- Fenced code.
- Math block.
- HTML block.
- Comments.
- Frontmatter.

Current decisions:

- These blocks are opaque for CST visual descent.
- Whole-block copy/paste should preserve source bytes.

Open decisions:

- Do we need raw payload extraction/replacement inside opaque blocks?
- Should raw payload operations be plain text editing rather than structural
  paste?
- How should code fence info strings be treated when copying only code text?

### 10. Recovery And Error Nodes

Status: paste rejects fragments containing sentinels.

Scope:

- `missing`.
- `error`.
- Incomplete/recovery fragments inside otherwise valid payloads.

Current decisions:

- Pasting recovery fragments is rejected for now.

Open decisions:

- Should structural copy expose incomplete syntax only for inspection?
- Do we ever want recovery-aware paste that preserves malformed structure?
- What UI warning should appear when a copied structural fragment is invalid?

## Working Backlog

Recommended order:

1. Lists cleanup.
2. Block quotes.
3. Pipe tables.
4. Generic document-item containers.
5. Typed fields and values.
6. Schema and template signatures.
7. Inline content.
8. Links and embeds.
9. Opaque raw blocks.
10. Recovery and error nodes.

Update this document after each design pass:

- Add decisions to the relevant chunk.
- Move resolved questions out of "Open decisions."
- Reflect implementation status in `structural_cst_extraction_pairs.md` and
  `structural_cst_paste_matrix.md`.
