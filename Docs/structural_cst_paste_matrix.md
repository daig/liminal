# Structural CST Paste Matrix

This document tracks structural paste support as source/target/intent triples.
It is intentionally about editor operations, not keybindings. A keybinding or
future target-picker UI should choose one of these operation intents and pass a
precise target intent into the planner.

## Status Legend

| Status | Meaning |
| --- | --- |
| Done | Implemented and covered by focused tests. |
| Partial | Some cases work, but the operation is narrower than the conceptual mode. |
| Planned | Valid operation, not implemented yet. |
| Needs design | Probably valid, but source projection, target selection, or formatting policy is unresolved. |
| Reject | Intentionally invalid for now. |
| N/A | The mode does not make semantic sense for this source/target pair. |

## Current Paste Intents

These are command intents and slot-acquisition strategies. They are not final
target-rendering families. Once an intent lands a typed CST slot, Apply chooses
rendering from the logical payload family, the slot role, and local boundary
context.

| Intent | Slot acquisition | Current user path | Current target shape |
| --- | --- | --- | --- |
| Block | Land a document-item slot, currently at the root. | `:CSTPasteBlock`; normal structural paste (`p`) | `root.documentItems` |
| Nest | Land a container node, then derive an interior slot. | `:CSTPasteNest`; shortcut `Space+n` | Currently `listItem` -> child `list.items` |
| Splice | Land a sibling slot in the target parent's child sequence. | `:CSTPasteSplice`; shortcut `Space+p` | Currently `list.items`, with cursor on a list item marker |

Current and planned slot roles include `root.documentItems`, `list.items`,
`listItem.interior`, `blockQuote.documentItems`, `pipeTable.rows`,
`pipeTableRow.cells`, `inlineContent.children`, `fields.children`, and
`listValue.values`.

## Current Clipboard Source Shapes

These are the source shapes produced by CST visual copy and consumed by the
paste planner today.

| Source family | Fragment wrapper | Child shape | Projection | Logical payload | Current adapter support |
| --- | --- | --- | --- | --- | --- |
| Root document items | `root` | one or more document items | `identity` | original root-level block(s) | Block: Done |
| List item sequence | `list` | one or more `listItem` children | `listItems` | list items with base indent removed | Block: Done; Splice: Done; Nest: Done |
| List child selected through list item content | `listItem` | exactly one `list` child | `listItemContent` | child list lifted one level | Block: Done; Splice: Done via projected list fragment; Nest: Done |
| Paragraph/content selected inside list item | `listItem` | paragraph/blank-line content | `listItemContent` | document-item text with list continuation prefix removed | Block: Done; Nest into list item: Done for paragraph/blank-line payloads |
| Block quote content | `blockQuote` | document items plus direct quote prefix tokens | `blockQuoteContent` | document-item text with one quote layer removed | Block: Done; other modes: Planned/Needs design |
| Unsupported structural fragments | any other wrapper | any other child shape | `identity` unless a projection exists | raw source text | Rejected by structural paste planner |

Current source projection kinds are `identity`, `listItems`,
`listItemContent`, and `blockQuoteContent`.

## Current Implemented Triples

| Source | Target | Mode | Status | Notes |
| --- | --- | --- | --- | --- |
| Root document items | Root document item position | Block | Done | Handles root separators and reparses when a missing terminator is needed. |
| List item sequence | Root document item position | Block | Done | Rebases list base indent to column 0. |
| List child selected from a list item | Root document item position | Block | Done | Projection lifts nested child list to a root list. |
| Paragraph/content selected from a list item | Root document item position | Block | Done | Projection strips list continuation prefix and parses as root payload. |
| Block quote content | Root document item position | Block | Done | Projection strips one quote layer and parses as root payload. |
| List item sequence | Existing list | Splice | Done | Requires precise marker target; normalizes top-level marker only when compatible. |
| List child selected from a list item | Existing list | Splice | Done | Converts projected list content into a list fragment before splicing. |
| Root list block | Existing list item | Nest | Done | Inserts the root list as a child list of the target item. |
| List item sequence | Existing list item | Nest | Done | Creates or appends to target item's child list. |
| List child selected from a list item | Existing list item | Nest | Done | Same logical result as list item sequence. |
| Paragraph/blank-line root payload | Existing list item | Nest | Done | Wraps text as a new child list item. |
| Paragraph/content selected from a list item | Existing list item | Nest | Done | Projection strips continuation prefix, then wraps as a new child list item. |

## Remaining Matrix By Target Family

### Target: Root Document

Root document paste is the broadest implemented mode. Most document-item
sources should be valid as block payloads if they are complete root children.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Paragraph, heading, thematic break | Done | N/A | Planned | Splice would mean sibling document-item insertion, effectively the same target family as Block but without root separator policy ambiguity. |
| Fenced code, math, HTML, comment, frontmatter | Done | N/A | Planned | Atomic block items. Need preserve opaque payload exactly. |
| Directive, value declaration, typed block | Done | N/A | Planned | Root insertion works when selected as document items. Container-internal paste is separate. |
| Schema block, template block | Done | N/A | Planned | Root insertion works when selected as document items. Body-level nesting/splicing needs target-aware support. |
| Structured/wiki embed blocks | Done | N/A | Planned | Root insertion should work as document items. |
| List block | Done | N/A | Planned | Block paste creates a top-level list with boundary separators. Root-level list-item splice is currently covered only through list target marker behavior, not a generic root splice operation. |
| Block quote block | Done | N/A | Planned | Block paste preserves quote when selecting the block itself; block-quote-content projection strips one quote layer. |
| Pipe table block | Done if selected as root document item | N/A | Planned | Whole-table block paste should work via root document item path. Row/cell fragments remain unsupported. |
| Inline-only fragments | Reject | N/A | Needs design | We do not yet have inline paste semantics. |
| Table row/cell fragments | Reject | N/A | Needs design | Need table-specific adapters. |

### Target: List Item

This target means "insert content inside the current list item." Today this is
the explicit nested list paste operation.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| List block | N/A | Done | N/A | Inserts as child list. |
| List item sequence | N/A | Done | N/A | Creates/appends child list, rebased to target content column. |
| List child selected from a list item | N/A | Done | N/A | Projection gives list source. |
| Paragraph or blank lines | N/A | Done | N/A | Wraps as child list item text. |
| Paragraph/content selected from list item | N/A | Done | N/A | Projection gives paragraph/blank-line root payload. |
| Heading, thematic break, code/math/html/comment, table, block quote | N/A | Planned | N/A | Need decide whether every root block can become a child document item under a list item, or whether nesting should wrap only paragraph-like text as a list item. |
| Block quote content | N/A | Planned | N/A | Likely wrap lifted root payload inside child list item(s), but quote semantics need tests. |
| Inline-only fragments | N/A | Needs design | N/A | Could insert into paragraph text, but not part of structural paste yet. |

### Target: List Child Sequence

This target means "insert list items as siblings in this list." Today this is
the explicit list-item splice operation.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| List item sequence | N/A | N/A | Done | Requires cursor on a target list item marker. |
| List child selected from a list item | N/A | N/A | Done | Projected to list fragment, then spliced. |
| Root list block | N/A | N/A | Reject | Current explicit splice refuses root-list-block payload to keep operation-specific semantics precise. We may intentionally accept this later if target intent says "splice list's items." |
| Paragraph/blank-line root payload | N/A | N/A | Planned | Should wrap each paragraph run as list item(s), or refuse multi-block payloads until policy is clear. |
| Paragraph/content selected from list item | N/A | N/A | Planned | Same as paragraph/blank-line root payload after projection. |
| Block quote content | N/A | N/A | Needs design | Could wrap lifted content as list items, but quote boundary rules need explicit policy. |
| Any non-list structural block | N/A | N/A | Needs design | Could wrap as a list item document item, but UI should make that intent clear. |
| Inline-only fragments | N/A | N/A | Needs design | Could create a paragraph list item, but not yet represented. |

### Target: Block Quote

This target means "insert content inside an existing block quote," preserving or
injecting quote prefixes as needed. We deliberately deferred this because cursor
position alone does not cleanly express whether the user means "beside the
quote" or "inside the quote."

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Root document items | N/A | Planned | Planned | Nest would inject one quote layer. Splice would insert quoted siblings inside the quote's document-item sequence. |
| Block quote block | N/A | Planned | Planned | Need decide whether nesting preserves full quote depth or unwraps/re-wraps one layer. |
| Block quote content | N/A | Planned | Planned | Natural case: paste lifted content into quote by adding one quote layer. |
| List item sequence/list block | N/A | Planned | Planned | Quote adapter must combine quote prefixing with list indentation. |
| Paragraph/content from list item | N/A | Planned | Planned | Needs both list prefix removal from source and quote prefix insertion at target. |
| Inline-only fragments | N/A | Needs design | Needs design | Inline insertion inside quoted paragraph is a separate mode. |

### Target: Pipe Table

Pipe tables need a table-specific adapter rather than root/list logic.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Whole pipe table | Done at root | N/A | Planned | Splice at root is document-item insertion. Table-internal splice means rows. |
| Pipe table row | N/A | N/A | Planned | Insert as sibling row. Need target row positions and header/delimiter protection. |
| Pipe table header | N/A | N/A | Needs design | Header replacement/splice is special because a table has at most one header. |
| Pipe table delimiter | N/A | N/A | Reject/Needs design | Delimiter is structural glue, not user content. Usually not pasteable directly. |
| Pipe table cell | N/A | Planned | Planned | Nest/splice could mean insert cell into row or replace cell content. Requires column-count policy. |
| Paragraph/inline content | N/A | Planned | N/A | Could insert as cell content. Need escaping/alignment rules. |
| List/block quote/code blocks | N/A | Needs design | Needs design | Tables may reject block payloads or serialize them into cell text depending on language policy. |

### Target: Typed/Schema/Template Bodies

These containers own nested document-item sequences. They should eventually use
a generic "document item sequence inside container" adapter rather than one-off
root insertion.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Root document items | N/A | Planned | Planned | Same structural shape as root insertion, but target parent is a body node rather than `root`. |
| List/list item sequence | N/A | Planned | Planned | Reuse list rebasing when inserted into body sequence. |
| Block quote content/list item content projections | N/A | Planned | Planned | Projection should happen at source; body adapter should consume logical root payload. |
| Inline-only fragments | N/A | Needs design | N/A | Depends on whether target is field/value/inline expression rather than body. |

### Target: Inline Content

Inline paste is currently out of scope for structural paste. It will need a
separate operation because source and target units are no longer document-item
children.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Inline text or inline nodes | N/A | Planned | Planned | Need inline fragment capture and escaping/spacing policy. |
| Paragraph content | N/A | Planned | Needs design | Could insert paragraph text into inline content, but multi-line payload needs hard/soft break policy. |
| Block payloads | N/A | Reject | Reject | A block cannot be inserted into inline content without explicit text serialization. |

### Target: Value/List/Record Structures

Value syntax is structurally separate from document items and needs its own
payload families.

| Source | Block | Nest | Splice | Notes |
| --- | --- | --- | --- | --- |
| Scalar value | N/A | Planned | Planned | Insert/replace scalar in value position. |
| List value element(s) | N/A | Planned | Planned | Splice into list value child sequence. |
| Record field(s) | N/A | Planned | Planned | Splice into record fields, with duplicate-field policy. |
| Document blocks or inline text | N/A | Needs design | Needs design | Requires explicit conversion into values. |

## Priority Backlog

1. Generalize "document item sequence insertion" from root-only to any parent
   whose children are document items, starting with typed/template/schema body
   targets.
2. Add block quote slot/rendering support:
   - source projection already gives lifted logical content;
   - `blockQuote.documentItems` rendering should inject one quote layer;
   - UI must distinguish paste beside quote from paste inside quote.
3. Add pipe table row splice:
   - source: `pipeTable` wrapper with `pipeTableRow` child(ren), or a projected
     row sequence;
   - target: precise row position inside `pipeTable`;
   - reject header/delimiter targets until replacement semantics are designed.
4. Add table cell operations:
   - cell-content insertion/replacement;
   - row cell splicing with column-count policy.
5. Add generic block-to-list-item nesting:
   - decide whether all root document items can become child document items of
     a new list item, or whether only paragraph-like content should auto-wrap.
6. Define inline structural paste separately from block/list paste.
7. Define value/list/record structural paste separately from document markup
   paste.

## Implementation Notes

- Source adaptation should stay independent from target rendering. A copied
  fragment has independent logical meaning via its projection; Apply decides how
  that logical payload becomes valid CST at the landed slot.
- Avoid fallback retargeting inside primitive operations. If an operation is a
  splice into a list, the cursor/target intent must identify the list item
  marker or a future explicit list child slot.
- Treat block, splice, and nest as slot acquisition intents. Do not select
  renderers from those names. Select renderers from payload family plus slot
  role, with boundary context for separators, indentation, markers, quote
  prefixes, and delimiters.
- Prefer precise rejection over guessing. Higher-level UI can later offer
  choices such as "paste as block," "paste inside quote," or "splice list
  items."
- Reuse green subtrees when the payload can be inserted unchanged. Reparse only
  when source or target adaptation changes concrete source text, such as list
  indent rebasing or quote prefix injection/removal.
