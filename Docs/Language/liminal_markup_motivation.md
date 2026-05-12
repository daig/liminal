# Liminal Markup Motivation

Status: non-normative companion to the live syntax spec.

The current source syntax and parse/lowering contract is
[Liminal Markup Syntax Spec v0.2 Draft](./liminal_markup_syntax_spec_v0_2.md).
This document captures the design motivation behind that spec. The historical
[v0.1 syntax proposal](./liminal_markup_syntax_spec_v0_1.md) remains as design
history, but it is not the conformance target.

## Core Thesis

Markdown-like source is not the semantic core of Liminal Markup.

The semantic core is a typed tree. Markdown-like forms, tables, math, HTML,
embeds, custom records, templates, and schema declarations are surface syntax
for typed structures.

For example, this source:

```markdown
# Introduction
```

is not semantically "a Markdown heading." It is a surface form for a typed
`Heading` node. Likewise, a link, table, image, callout, citation, or custom
record should lower to a declared semantic type instead of remaining a bag of
Markdown tokens.

This gives the language one semantic model:

```text
source text
  -> lossless CST
  -> typed semantic tree
  -> schema validation, rendering, editing, indexing
```

The CST is for source fidelity and editor structure. The semantic tree is for
meaning. The schema pass is for resolving names and validating shape.

## Why Not A Markdown Dialect

Liminal uses familiar markup where that helps authors, but it does not try to
be CommonMark, GFM, Obsidian Markdown, or a compatibility superset.

The goal is a language that is predictable under editing:

- block boundaries should be local and explicit;
- schema validation must not change tokenization;
- unknown types should still parse as structured nodes;
- incomplete input should keep useful tree shape;
- every nontrivial surface form should have a typed fallback.

This means deliberately avoiding some Markdown features that make editor parsers
harder to reason about, including lazy continuation, indented code blocks,
setext headings, arbitrary raw HTML recognition, and global attribute syntax.

## Schema-Free Parsing

The base parser must not need the user schema.

Unknown constructors such as `@DoesNotExist{foo: 1}` are syntactically valid.
They produce typed-constructor CST and semantic nodes, then the schema pass can
report unresolved names or invalid fields.

This separation is central:

- parsing answers "what source structure did the user write?";
- lowering answers "what typed semantic shape does that source imply?";
- schema validation answers "is this shape allowed in this document context?";
- rendering/indexing/editing consume the validated or partially validated tree.

Because schema validation never changes CST shape, editor features can remain
stable while imports are missing, schemas are mid-edit, or names are unresolved.

## Generic Typed Fallback

Every semantic node must be representable in generic typed syntax.

Surface forms are authoring conveniences, not semantic requirements. A table can
be written as a pipe table when safe, but its semantic target is still `Table`.
A custom callout can have a fenced form, but the generic typed constructor must
remain available. If a surface printer cannot safely preserve the desired
semantic shape, it can fall back to generic typed syntax.

The central generic forms are:

```liminal
@Type#id{fields}[inline content]

:::Type#id{fields}
block content
:::

@[
inline content value
]

@{
block content value
}

!{ExpectedType}[fallback](target)

&reference
```

This keeps extension design regular: define the type first, then optionally add
a reader/printer surface for that type.

## Surface Readers And Printers

A surface reader maps source syntax to a typed node. A surface printer maps a
typed node back to source.

Good surface syntax follows these constraints:

- it declares the semantic type it produces;
- it does not require schema knowledge to tokenize or build the CST;
- it does not change global block-boundary rules;
- it preserves source spans for bidirectional editing;
- it is either lossless or records its normalization;
- it has a generic typed fallback.

This is the reason built-in Markdown-like forms lower to typed nodes instead of
becoming a second semantic system. Headings, links, images, tables, math, embeds,
and comments are all surface readers over the same typed-tree foundation.

## Structure Over Annotations

Identity belongs to typed nodes. It should not be modeled as arbitrary Markdown
attributes sprinkled across syntax.

The language should avoid general `{#id .class key=value}` annotations. Such
annotations blur parser, schema, styling, and semantic concerns. Liminal's
identity model is narrower: typed nodes may carry node identity, and shorthand
block IDs exist only where the live spec defines them.

This keeps the source language expressive without making every syntax form an
open-ended annotation host.

## Editor-Oriented Recovery

The parser is an editor parser. It must preserve structure under incomplete
input.

If a user is typing a constructor, block, record, list, link, embed, comment, or
template expression, the CST should usually keep the smallest incomplete node
that preserves surrounding structure. Semantic lowering can then choose whether
that incomplete node becomes a recoverable semantic value, literal text, or a
diagnostic-bearing partial construct.

The important invariant is source fidelity: every consumed byte stays in the
CST, and recovery must not synthesize normalized source text.

## Context Matters

The typed tree has distinct document, block, inline, value, and template
contexts. Syntax that looks similar may need different semantic targets in those
contexts.

This is why the live spec splits some forms that the early proposal treated more
generically:

- block math and inline math are different semantic targets;
- block HTML and inline HTML are different semantic targets;
- structured embeds have inline, block, and value forms;
- list items are explicit value nodes inside list blocks;
- top-level values, schemas, templates, and directives are document items, not
  renderable blocks.

The result is more verbose than a single universal node type for each topic, but
it gives rendering, indexing, validation, and editing clearer contracts.

## Templates Are Typed And Pure

Templates are transformations over typed data, not an escape hatch into an
arbitrary host language.

Template expressions should remain deliberately small: projections, indexing,
literals, references, grouping, and limited coalescing. Template control
structures should be structural typed blocks, not free-form string directives.

This keeps templates inspectable, indexable, portable, and safe to evaluate in
editor-facing workflows.

## Compatibility Posture

The intended migration path is semantic, not source-compatible.

Existing Markdown-like source may need normalization into Liminal source or
generic typed syntax. That is acceptable. Liminal should prioritize stable CST
shape, typed semantics, schema-aware validation, and bidirectional editing over
compatibility with every Markdown edge case.

## Design Constraints

The core design constraints are:

1. Generic typed syntax must represent every semantic node.
2. Surface syntax must lower into declared typed semantics.
3. The base parser must not require schema knowledge.
4. Schema validation must not change tokenization or CST shape.
5. Multiline custom content must be explicitly delimited.
6. Inline constructs should use balanced delimiters or remain literal/recoverable.
7. Unknown types are syntactically valid.
8. Node identity is part of typed structure, not arbitrary annotation syntax.
9. Printers may fall back to generic typed syntax.
10. Templates must be typed, pure, and inspectable.
11. Extension authors add types first and surfaces second.

