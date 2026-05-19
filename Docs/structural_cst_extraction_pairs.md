# Structural CST Extraction Pairs

This document inventories copied CST fragment shapes by `(wrapperKind,
childKinds)` and records whether the extraction layer currently has an adapter
for them.

Extraction is source-side only:

- `StructuralCSTFragment.capture(_:)` stores the selected sibling forest inside
  a synthetic wrapper whose kind is the live selection parent.
- `StructuralCSTSourceProjection` gives that fragment independent logical text,
  such as removing list indentation or one layer of block quote markers.
- Paste modes then decide whether that logical payload is valid at a target.

This document intentionally does not decide target behavior. It answers:
"If the user copies this wrapper/children shape, do we understand what logical
content it means?"

## Current Supported Extraction Families

| Wrapper | Child shape | Projection | Support |
| --- | --- | --- | --- |
| `root` | one or more document items | `identity` | Supported as root document item payload. |
| `list` | one or more `listItem` children | `listItems` | Supported as logical list item sequence with base indent removed. |
| `listItem` | any selected direct content children | `listItemContent` | Supported as logical list item content with item prefix/continuation indent removed. Paste consumption is narrower than extraction. |
| `blockQuote` | one or more document items, possibly with direct quote prefix tokens between them | `blockQuoteContent` | Supported as logical block quote content with one quote layer removed. |

The clipboard inspector currently labels all other structural payloads as
`Unsupported`.

## Unsupported Extraction Matrix

### Document Item Internals

These are structural children of root-level document items. Selecting the whole
document item at the `root` level is supported; selecting its internal children
is not.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `directive` | `useDirective` | Directive payload projection, or treat directive as atomic. |
| `useDirective` | token-only internals (`identifier`, `qname`, scalar/string tokens) | Usually atomic; fine-grained directive editing is a future value-like adapter. |
| `schemaBlock` | `schemaHeader`, `schemaBody` | Schema block part adapter; likely atomic until schema-specific editing exists. |
| `templateBlock` | `templateSignature`, `templateBody` | Template part adapter; body may become document-item sequence projection. |
| `paragraph` | `inlineContent`, `blockIdSuffix` | Inline/content adapter; block id adapter or treat suffix as metadata. |
| `atxHeading` | `inlineContent`, `blockIdSuffix` | Heading content adapter and block id adapter. |
| `valueDeclaration` | `typedConstructor` | Typed value adapter. |
| `typedBlock` | `fields`, document item children | Field adapter plus nested document-item sequence adapter. |
| `pipeTable` | `pipeTableHeader`, `pipeTableDelimiter`, `pipeTableRow` | Table adapter; delimiter probably non-user content. |
| `pipeTableHeader` | `pipeTableCell` children | Header/cell adapter. |
| `pipeTableDelimiter` | `pipeTableCell` children | Usually reject or table-format adapter only. |
| `pipeTableRow` | `pipeTableCell` children | Row/cell adapter. |
| `pipeTableCell` | `inlineContent` | Cell content adapter. |
| `structuredEmbedBlock` | `linkLabel`, `embedTarget` | Embed target/fallback-content adapter. |
| `wikiEmbedBlock` | `wikiTarget` | Wiki embed target adapter. |

Atomic raw blocks are intentionally omitted from this table:
`frontmatter`, `fencedCodeBlock`, `mathBlock`, `htmlBlock`, and `commentBlock`
have opaque child policy in CST visual mode. Their raw payload tokens are not
structural extraction targets today.

`blankLine` and `thematicBreak` have no meaningful structural children.

### Nested Document-Item Containers

These wrappers contain document item sequences, but extraction is currently
only root-aware unless the wrapper is `listItem` or `blockQuote`.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `templateBody` | document item children | Generic document-item-sequence projection for non-root parents. |
| `typedBlock` | document item children | Generic document-item-sequence projection plus typed-block boundary policy. |
| `blockLiteral` | document item children | Generic document-item-sequence projection for value literal bodies. |
| `schemaBody` | schema declarations, not document items | See schema section below. |

`listItem` and `blockQuote` are the two supported non-root document-item-like
containers today because they need source projection: list indentation removal
and quote prefix removal.

### Schema Syntax

Schema syntax has its own structural language. None of these extraction pairs
have source adapters yet.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `schemaBody` | `schemaTypeDeclaration`, `schemaTemplateTypeDeclaration` | Schema declaration sequence adapter. |
| `schemaTypeDeclaration` | `schemaTypeExpression`, `schemaModifier` | Type declaration RHS/modifier adapter. |
| `schemaTypeExpression` | nested `schemaTypeExpression`, `schemaField`, `schemaVariantCase` | Type expression adapter with record/list/variant roles. |
| `schemaVariantCase` | `schemaTypeExpression` | Variant case payload adapter. |
| `schemaField` | `schemaTypeExpression`, `schemaModifier` | Schema field adapter. |
| `schemaTemplateTypeDeclaration` | `templateSignature` | Template signature adapter in schema declaration context. |
| `templateSignature` | `templateParameter` | Template parameter sequence adapter. |
| `templateParameter` | `schemaTypeExpression` | Parameter type adapter. |
| `schemaModifier` | token-only internals | Probably atomic until modifier argument parsing exists. |
| `schemaHeader` | token-only internals | Usually atomic metadata. |

The same child kind can require different meaning depending on the wrapper. For
example, `schemaTypeExpression` under a `schemaField` is a field type, while the
same kind under another `schemaTypeExpression` can be a list element, map
element, optional wrapper, or variant payload.

### Inline Syntax

Inline extraction is not implemented. `inlineContent` is the main future source
projection boundary; inline wrappers need adapters that preserve or intentionally
strip delimiters.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `inlineContent` | `inlineText` tokens, inline nodes (`emphasis`, `strong`, `wikilink`, etc.) | Inline sequence adapter. |
| `emphasis` | `inlineContent` | Either formatted-inline adapter preserving `*...*`, or content projection stripping delimiters. |
| `strong` | `inlineContent` | Same as emphasis. |
| `strikethrough` | `inlineContent` | Same as emphasis. |
| `highlight` | `inlineContent` | Same as emphasis. |
| `footnoteInline` | `inlineContent` | Footnote content adapter. |
| `mdLink` | `linkLabel`, `linkDestination` | Link adapter: label, destination, title roles. |
| `mdImage` | `linkLabel`, `linkDestination` | Image adapter: alt text, destination, title roles. |
| `linkLabel` | `inlineContent` | Link label/alt text content adapter. |
| `linkDestination` | `linkTitle` plus destination tokens | Destination/title adapter. |
| `linkTitle` | title text token | Probably atomic string adapter. |
| `wikilink` | `wikiTarget`, alias `inlineContent` | Wiki target/alias adapter. |
| `wikiEmbed` | `wikiTarget` plus raw payload token | Wiki embed target/payload adapter. |
| `structuredEmbed` | `linkLabel`, `embedTarget` | Structured embed fallback/target adapter. |
| `typedInline` | `typedConstructor` | Typed inline adapter. |
| `typedConstructor` | `fields`, `inlineContent` | Constructor field/content adapter. |
| `interpolation` | `interpolationExpression` | Interpolation expression adapter. |
| `interpolationExpression` | nested `interpolationExpression` | Expression adapter. |

Atomic inline wrappers with no structural content are currently unsupported as
internal extraction targets but can be copied as children of `inlineContent`
once inline sequence extraction exists:

- `codeSpan`
- `escapedPunctuation`
- `autolink`
- `mathInline`
- `inlineComment`

### Typed Fields And Values

Typed/value syntax is not covered by document-item paste. It needs extraction
families for fields, values, list elements, and record entries.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `fields` | one or more `field` children | Field sequence adapter. |
| `field` | `value` | Field value adapter; field-name metadata matters. |
| `value` | one value payload (`scalarValue`, `listValue`, `recordValue`, `typedConstructor`, `inlineLiteral`, `blockLiteral`, `reference`, `structuredEmbedValue`) | Value payload adapter. |
| `listValue` | one or more `value` children | List-value element sequence adapter. |
| `recordValue` | `fields` | Record field adapter. |
| `inlineLiteral` | `inlineContent` | Inline literal content adapter. |
| `blockLiteral` | document item children | Block literal document-item sequence adapter. |
| `structuredEmbedValue` | `linkLabel`, `embedTarget` | Value embed fallback/target adapter. |

Atomic or token-heavy value wrappers that still need logical adapters:

- `scalarValue`: scalar token adapter.
- `reference`: internal/external reference adapter.

### Link/Embed Target Wrappers

These wrapper kinds are shared by multiple syntactic parents. Their extraction
meaning depends on the parent role.

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `wikiTarget` | `wikiTargetText` token | Wiki target string adapter. |
| `embedTarget` | `embedTargetText` token | Embed target string adapter. |
| `linkLabel` | `inlineContent` | Label content adapter. |
| `linkDestination` | `linkDestinationText`, `linkTitle` | Destination/title adapter. |
| `linkTitle` | `linkTitleText` token | Link title string adapter. |

Because these are role-sensitive, source metadata may need to record more than
`wrapperKind` and `childKinds`. For example, `linkLabel` under `mdImage` is alt
text, while `linkLabel` under `mdLink` is link text.

### Recovery And Error Nodes

| Wrapper | Unsupported child selections | Needed extraction adapter |
| --- | --- | --- |
| `missing` | none or recovery-specific shape | Usually reject. |
| `error` | error children/tokens | Error payload adapter or reject. |

The current paste planner rejects fragments whose snapshot root contains
sentinels. Extraction can still produce a payload for inspection, but paste
should continue refusing it until a recovery-aware edit story exists.

## Summary Of Highest-Value Unsupported Pairs

These are the unsupported extraction pairs most likely to matter next:

1. `pipeTable` -> `pipeTableRow`
   - Needed for table row splice.
2. `pipeTableRow` -> `pipeTableCell`
   - Needed for cell-level operations and row construction.
3. `pipeTableCell` -> `inlineContent`
   - Needed for pasting table cell contents.
4. `templateBody` / `typedBlock` / `blockLiteral` -> document item children
   - Needed for generic non-root document-item sequence paste.
5. `inlineContent` -> inline text/nodes
   - Needed for all inline structural paste.
6. `fields` -> `field`
   - Needed for typed constructor and record field paste.
7. `listValue` -> `value`
   - Needed for value-list splice.
8. `schemaBody` -> schema declarations
   - Needed for schema-aware structural editing.

## Implementation Notes

- Keep source extraction role-aware where the same wrapper means different
  things under different parents.
- Keep projections independent from target paste modes. For example,
  `pipeTableRow` extraction should describe a logical row sequence; separate
  target adapters decide whether it can be pasted into a table, converted to
  root text, or rejected.
- Do not make token-only internals pasteable by accident. For most wrappers,
  token-only children should either be part of an atomic parent extraction or
  have an explicit string/value adapter.
- The clipboard inspector should grow labels alongside each new extraction
  adapter so unsupported payloads remain visible while we build coverage.
