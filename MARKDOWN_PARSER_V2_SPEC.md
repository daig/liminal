# Markdown Parser V2 Spec

This document defines the replacement markdown language and parsing model for
Liminal V2.

It is a clean spec, not a compatibility spec for the current Swift parser.
Where V1 behavior differs, this document wins.

## Goals

V2 must provide:

- a full-fidelity CST that preserves all source text, delimiters, trivia, and
  incomplete constructs
- typed AST views for semantic editing and rendering
- CommonMark-compatible core markdown behavior
- GFM-compatible behavior for the extensions we intentionally support
- Obsidian-style knowledge-base extensions where explicitly specified below

## Normative Baseline

Unless this document says otherwise:

- core markdown block and inline parsing follows CommonMark
- GFM extensions are supported for:
  - tables
  - strikethrough
  - task list items
  - autolinks

If CommonMark/GFM and this document conflict, this document takes precedence.

## Explicit Deviations From CommonMark

V2 intentionally differs from raw CommonMark in these ways:

- YAML frontmatter is supported as a document-start construct
- wikilinks and embeds are supported
- block IDs are supported
- `%% ... %%` comments are supported
- `== ... ==` highlights are supported
- inline footnotes `^[ ... ]` are supported
- inline math `$ ... $` and block math `$$` blocks are supported
- inline HTML is not supported

## Source Model

The grammar is block-structured.

The top-level document contains a sequence of block nodes.
Container blocks contain child blocks.
Inline parsing only occurs inside inline-bearing leaf blocks and table cells.

### Required container structure

V2 must represent these as real structural containers:

- document
- block quote
- list
- list item

List items contain child blocks, not just inline text.

## Block Syntax

### Document frontmatter

YAML frontmatter is recognized only at the start of the document.

Accepted form:

```text
---
<yaml content>
---
```

Rules:

- The opening delimiter must be the first non-empty syntax in the file.
- The opening and closing delimiter lines are exactly `---`.
- Frontmatter ends only at a matching closing delimiter line.
- If the opening delimiter is not closed before EOF, the CST contains an
  incomplete frontmatter node.
- A `---` line anywhere else in the document is not frontmatter; it is parsed
  by normal markdown rules.

The AST exposes frontmatter as a distinct block preceding the markdown body.

### Headings

Headings follow CommonMark heading rules.

Supported:

- ATX headings
- setext headings

Block IDs may attach to headings as described in the block-ID section.

### Paragraphs

Paragraphs follow CommonMark paragraph and container-interaction rules.

Paragraphs are inline-bearing leaf blocks.

### Thematic breaks

Thematic breaks follow CommonMark rules.

V2 does not use the V1 heuristic where list-item detection effectively overrides
common thematic-break cases.

### Block quotes

Block quotes follow CommonMark container rules.

Rules:

- block quote markers are parsed structurally, not by line-grouping heuristics
- nested block quotes are represented as nested container nodes
- lazy continuation behavior follows CommonMark

### Lists

Lists follow CommonMark list and list-item container rules, with GFM task-list
support.

Rules:

- ordered and unordered lists are distinct structural lists
- list boundaries follow CommonMark container parsing rules
- list items contain child blocks
- continuation paragraphs, nested lists, nested block quotes, and code blocks
  inside list items are supported
- marker-family changes are not merged merely because the source lines are
  adjacent

Supported unordered markers:

- `-`
- `*`
- `+`

Supported ordered markers:

- CommonMark ordered-list markers

Task list items:

- Task-list behavior follows GFM.
- A task marker is recognized only in the first paragraph of a list item.
- Supported markers are:
  - `[ ]`
  - `[x]`
  - `[X]`

The typed AST should expose:

- list kind: ordered or unordered
- list start number for ordered lists
- list items as structural children
- optional task state on the item when present

### Code blocks

Code blocks follow CommonMark rules.

Supported:

- fenced code blocks
- indented code blocks

Fenced code blocks:

- preserve fence delimiter character and length in the CST
- preserve the raw info string in the CST
- expose normalized info/language fields in the AST as needed
- produce incomplete fenced-code nodes when the opening fence is not closed

### HTML blocks

HTML blocks follow CommonMark block HTML rules exactly.

Rules:

- use the CommonMark HTML block types and termination rules
- do not apply the V1 approximation that treated arbitrary `<tag` lines as
  blank-line HTML blocks
- do not absorb following ordinary text except where CommonMark HTML block rules
  require it

The CST preserves the raw HTML source exactly.
The AST may expose HTML blocks as opaque raw-source nodes.

### Tables

Tables follow the GFM tables extension.

Rules:

- a table consists of a header row, delimiter row, and zero or more body rows
- delimiter-row validation follows GFM
- escaped pipes must be handled correctly
- table cells contain inline content, not block content
- degenerate V1-style tables are not valid in V2

The AST exposes:

- header row
- body rows
- per-column alignment
- inline content for each cell

### Math blocks

Block math is a distinct block construct.

Accepted form:

```text
$$
<math content>
$$
```

Rules:

- the opening and closing delimiter lines are exactly `$$`
- content between them is literal math source
- if the block is not closed before EOF, the CST contains an incomplete math
  block

V2 does not define inline `$$ ... $$` math inside paragraphs.

## Inline Syntax

### Core inline markdown

These follow CommonMark inline rules:

- text
- escapes
- entity and character references
- emphasis
- strong emphasis
- code spans
- inline links
- inline images
- autolinks
- hard line breaks
- soft line breaks

These use CommonMark delimiter and nesting behavior rather than the V1
heuristics.

### GFM inline extensions

These follow GFM rules:

- strikethrough
- autolink extension

Autolinks include both:

- CommonMark angle-bracket autolinks
- GFM autolink-extension forms

### Inline HTML

Inline HTML is not supported.

Rules:

- HTML-like text inside inline contexts is parsed as ordinary text unless it is
  part of another supported construct
- V2 has block HTML only

### Wikilinks

Accepted forms:

```text
[[target]]
[[target|alias]]
```

Target grammar:

```text
target := [note_path] [ "#" anchor ]
anchor := heading_anchor | block_anchor
block_anchor := "^" block_id
```

Rules:

- `target` is parsed as source syntax, not resolved during parsing
- local-only targets are valid:
  - `[[#Heading]]`
  - `[[#^block-id]]`
- the first unescaped `|` separates target from alias
- the alias is parsed as inline content
- if the closing `]]` is missing, the CST contains an incomplete wikilink node

The AST exposes:

- raw target source
- parsed target components
- optional alias inline content

### Embeds

Accepted forms:

```text
![[target]]
![[target|payload]]
```

Rules:

- target parsing is the same as for wikilinks
- the first unescaped `|` separates target from payload
- payload is preserved as source syntax and exposed to higher layers
- the parser does not assign embed-payload semantics beyond syntactic capture
- if the closing `]]` is missing, the CST contains an incomplete embed node

The AST exposes:

- parsed target
- optional raw payload

### Standard links and images

Links and images follow CommonMark inline parsing rules.

Rules:

- balanced bracket parsing is required
- destination and title parsing follows CommonMark
- V1-style ad hoc title parsing is not used

Image alt text is parsed as inline content.

### Comments

Comments are delimited by `%%`.

Accepted form:

```text
%% comment content %%
```

Rules:

- comment content may span newlines
- comments do not nest
- comments are parsed wherever inline content is allowed
- comments do not contribute to rendered output or plain-text content
- if the closing `%%` is missing, the CST contains an incomplete comment node

### Highlights

Highlights are delimited by `==`.

Accepted form:

```text
==highlighted content==
```

Rules:

- content is parsed as inline content
- delimiter pairing must not use the V1 greedy heuristic model
- highlight parsing must not cross code spans or other syntax boundaries that
  CommonMark-style inline parsing would forbid
- if the closing delimiter is missing, the CST contains an incomplete highlight
  node

### Inline footnotes

Accepted form:

```text
^[footnote content]
```

Rules:

- footnote content is parsed as inline content
- bracket balancing is structural, not first-`]` scanning
- if the closing `]` is missing, the CST contains an incomplete footnote node

### Inline math

Accepted form:

```text
$math content$
```

Rules:

- inline math is distinct from ordinary text and from code spans
- block-math delimiters `$$` do not create inline-math nodes
- inline math may not cross block boundaries
- if the closing delimiter is missing, the CST contains an incomplete inline
  math node

Exact escaping and delimiter interaction rules for math are defined by this
language, not inherited blindly from V1. The initial implementation should use
the conservative rule set:

- opening `$` must not be followed by whitespace
- closing `$` must not be preceded by whitespace
- inline math does not span newlines

## Block IDs

Block IDs are supported as trailing block suffixes.

Accepted identifier grammar:

```text
block_id := one_or_more_of(letter | digit | "_" | "-")
```

Accepted attachment sites:

- headings
- paragraphs
- list items

Accepted source form:

```text
<block content> ^block-id
```

Rules:

- the block ID is a trailing suffix in source, not a standalone inline node
- there must be at least one whitespace character before `^block-id`
- the suffix must be the last non-whitespace syntax in the block
- in a list item, a trailing block ID on the item's opening content attaches to
  the list item
- block IDs participate in wikilink/embed anchor resolution via `#^block-id`

The CST preserves the suffix tokens explicitly.
The AST exposes the normalized block ID on the attached block or list item.

## Unsupported Syntax

The following are not part of V2:

- inline HTML
- bare inline `^block-id` as a standalone inline reference syntax
- inline `$$ ... $$` math inside paragraphs

If these forms appear in source, they remain ordinary text unless another
supported construct claims them.

## Recovery And Incomplete Syntax

V2 is an editor grammar, not a batch-only parser.

The CST must preserve incomplete syntax explicitly instead of silently degrading
recognized openers into plain text.

### Required incomplete-node behavior

If a construct opener is recognized but the construct is not closed before its
legal termination point or EOF, the CST must produce an incomplete node for:

- frontmatter
- fenced code blocks
- block math
- wikilinks
- embeds
- links
- images
- comments
- highlights
- inline footnotes
- inline math

### Recovery rules

Recovery must satisfy these constraints:

- recovery must preserve all consumed source
- recovery must not invent normalized source text
- recovery should stop at the earliest boundary that preserves a stable parse
  for surrounding syntax
- typed AST views may hide or simplify malformed structures, but the CST must
  retain them exactly

## Tree Requirements

The CST and typed AST must preserve the distinction between source-preserving
syntax and semantic interpretation.

### CST responsibilities

The CST preserves:

- exact delimiters
- exact marker kinds
- exact indentation/trivia
- raw HTML source
- raw frontmatter source
- raw embed payload source
- all incomplete constructs

### AST responsibilities

The AST exposes:

- real container lists and list items
- real block quotes
- explicit hard-break and soft-break nodes
- explicit autolink nodes
- explicit math nodes
- explicit comment/highlight/wikilink/embed nodes
- parsed target structure for wikilinks and embeds
- block IDs on the blocks or items they attach to

The AST is not allowed to flatten list items into ad hoc single-line inline
records.

## Initial Conformance Target

A V2 parser is conformant if:

- it matches CommonMark for the supported core constructs
- it matches GFM for the supported extensions
- it implements the explicit Liminal extensions in this document
- it produces explicit incomplete syntax nodes for unfinished constructs
- it preserves enough source detail in the CST to support lossless
  serialization and incremental bidirectional editing
