# Markdown Parser V2 Direction

This document evaluates the quirks in
[CURRENT_MARKDOWN_PARSER_SPEC.md](/Users/dai/code/liminal/CURRENT_MARKDOWN_PARSER_SPEC.md)
and recommends which ones V2 should keep, normalize, or drop.

The goal is not source compatibility with the current parser. The goal is a
clean spec for a cstree-based parser with:

- CommonMark as the baseline block/inline model
- GFM behavior where we intentionally support it
- Obsidian-specific extensions where they are clearly part of the product
- explicit error-tolerant structure for incomplete edits

## Guiding Rules

V2 should follow these rules when current behavior and desired behavior differ:

1. Keep user-visible syntax that is clearly intentional and product-relevant.
2. Drop behavior that is obviously a parser artifact rather than a language rule.
3. Prefer established specs over local ad hoc behavior:
   - CommonMark for core markdown
   - GFM for tables, strikethrough, task lists, autolinks
   - Obsidian behavior for wikilinks, embeds, comments, block IDs, and math
4. Prefer explicit incomplete/error nodes over fallback-to-text when the source
   is syntactically recognizable but unfinished.

## Keep

These look like real intended language features and should stay in V2.

### Obsidian / product-specific syntax

- Wikilinks: `[[target]]`, `[[target|alias]]`
- Embeds: `![[target]]`, `![[target|...]]`
- Block IDs as trailing block suffixes on headings, paragraphs, and list items:
  `... ^block-id`
- Comments: `%%comment%%`
- Highlights: `==text==`
- Inline footnotes: `^[text]`
- Inline math: `$...$`
- Block math delimited by `$$` on its own lines

### Core markdown constructs

- Headings
- Paragraphs
- Blockquotes
- Lists
- Fenced code blocks
- Thematic breaks
- Frontmatter at document start
- Tables
- HTML blocks

### Reasonable current choices to keep

- Frontmatter should remain a document-start-only construct.
- Local-only wikilinks like `[[#Heading]]` and `[[#^block]]` make sense and
  should stay.
- Treating embed right-hand payload as syntax, not immediately as rendering
  semantics, is fine. V2 can parse it first and interpret it later.

## Normalize

These are real language areas, but the current behavior is too ad hoc.

### 1. Core block parsing should become real container parsing

Normalize:

- Lists should be block containers, not one-line records with an `indent` field.
- Blockquotes should be block containers with proper nested parsing.
- Lazy continuation lines should work where CommonMark allows them.
- Container structure should be determined structurally, not by "keep grouping
  consecutive lines until something else happens."

Reason:

- The current line-based list model is the biggest structural limitation in the
  existing parser.
- For CST-based incremental editing, list and blockquote structure should be
  represented explicitly in the tree.

### 2. Mixed list markers should not coalesce into one list

Normalize:

- Marker family changes should usually start a new list.
- Ordered vs unordered lists should be distinct at parse time.

Drop current behavior:

```text
- one
1. two
+ three
```

becoming one list block.

Reason:

- That behavior is a direct parser artifact, not a sensible source-language rule.

### 3. Thematic break vs list-item ambiguity should follow CommonMark

Normalize:

- Cases like `- - -` should be classified by CommonMark rules, not by "list
  detection happens first."

Reason:

- Current precedence creates visibly wrong results for common markdown input.

### 4. HTML blocks should match CommonMark, not the current imitation

Normalize:

- Use CommonMark HTML block rules directly.
- Do not treat arbitrary `<tag` lines as HTML blocks.
- Do not let blank-line-terminated HTML blocks absorb unrelated following text
  unless CommonMark says they should.
- Do not consume the terminating blank line as part of block behavior unless the
  spec requires it.

Reason:

- This is already a known temporary shortcut.
- HTML block parsing is unpleasant enough that ad hoc behavior will keep causing
  edge-case bugs if we preserve it.

### 5. Tables should become proper GFM tables

Normalize:

- Require a valid delimiter row, not merely "contains `|` and `-`".
- Parse escaped pipes correctly.
- Do not accept degenerate tables that yield zero actual header cells.
- Match GFM row/cell behavior rather than the current permissive heuristic.

Reason:

- The current parser accepts structurally nonsensical tables.
- Tables are already a GFM feature in the product description, so the spec
  should say GFM, not "whatever our old heuristic happened to accept."

### 6. Links and images should use real link parsing

Normalize:

- Standard links should balance nested `[]` in link text.
- Destination/title parsing should follow CommonMark instead of the current
  "first unescaped `)` plus ad hoc double-quote title extraction."
- Images should follow the same parsing rules as links.

Reason:

- The current implementation rejects common, reasonable markdown like
  `[a [b]](url)`.

### 7. Emphasis / strong should use CommonMark delimiter-run rules

Normalize:

- Replace the current greedy `*` / `_` parsing with real delimiter-run parsing.

Drop current behavior:

- `***triple***` parsing as `strong("*triple")` plus trailing `*`

Reason:

- This is a correctness issue, not a stylistic one.
- The current behavior is not defensible as a language rule.

### 8. Escapes should unescape

Normalize:

- Backslash escapes should suppress markup interpretation and yield the literal
  punctuation character in the semantic inline view.
- The CST should still preserve the backslash token in source.

Drop current behavior:

- preserving the backslash in plain text as if no escape happened

Reason:

- The current behavior loses the distinction between "literal punctuation"
  syntax and actual source text.
- This is exactly the kind of case where CST + typed AST should help.

### 9. Hard breaks and soft breaks should be real syntax

Normalize:

- Paragraph newlines should not remain buried inside plain text nodes.
- Soft breaks and hard breaks should be represented explicitly in the syntax
  tree and typed inline model.
- Hard break recognition should follow CommonMark/GFM rules.

Reason:

- The AST already anticipates this.
- Explicit break nodes matter for editing, selection, and source-preserving
  transforms.

### 10. Autolinks should be implemented

Normalize:

- `<https://example.com>` and equivalent GFM/CommonMark autolink forms should
  parse as autolinks.

Reason:

- This is clearly intended and already modeled in the AST.
- This matches your "dead syntax is probably incomplete implementation" rule.

### 11. Indentation rules should follow CommonMark for core blocks

Normalize:

- Headings, thematic breaks, fenced code blocks, and HTML blocks should not be
  arbitrarily column-0-only if CommonMark permits leading indentation.

Reason:

- The current parser is stricter than normal markdown in several places for no
  good language-design reason.

### 12. Incomplete constructs should become incomplete nodes, not plain text

Normalize:

- Unclosed constructs that have a clear opener should typically remain visible
  in the CST as incomplete syntax.
- This applies to things like:
  - frontmatter
  - fenced code
  - comments
  - wikilinks
  - embeds
  - links
  - footnotes

Reason:

- This is the right fit for incremental editing.
- Falling back to plain text is acceptable for a one-shot parser, but not ideal
  for an editor-grade syntax tree.

## Drop

These should not survive into V2 as normative language behavior.

### 1. Any-tag blank-line HTML imitation

Drop:

- "any non-closing tag starts a blank-line-terminated HTML block"

Replace with:

- exact CommonMark HTML block behavior

### 2. Flat list AST as the source-language model

Drop:

- list items as single-line records with only `indent`, `markerLength`, and
  inline content

Replace with:

- list items that contain child blocks

### 3. Mixed ordered/unordered marker coalescing

Drop:

- one list node spanning different marker families purely because the lines were
  adjacent

### 4. Degenerate table acceptance

Drop:

- table recognition where the header row can yield zero parsed cells

### 5. Escape-preserving "plain text" behavior

Drop:

- `\*` remaining semantically as backslash-plus-asterisk text

### 6. Greedy delimiter-run artifact behavior

Drop:

- malformed emphasis/strong outcomes like the current `***triple***` result

### 7. Inline display-math parsing with `$$...$$` inside paragraphs

Likely drop:

- treating `$$...$$` as an inline construct within ordinary paragraph content

Reason:

- This blurs block math and inline math.
- Unless we have evidence that Obsidian intentionally supports this as source
  syntax, it is better to reserve `$$` for block math and keep `$...$` for
  inline math.

This is the one place where I would not blindly apply the "dead syntax probably
means intended feature" heuristic. The existing `InlineNode.displayLatex` case
looks more like model leakage from the renderer than a stable language design.

### 8. Bare inline `^block-id` as its own source syntax

Likely drop as user-facing syntax:

- parsing bare `^block-id` inside inline text as a reference node

Keep instead:

- block ID definitions as trailing block suffixes
- block references via wikilinks / embeds using `#^block-id`

Reason:

- In Obsidian-style markdown, `^block-id` makes sense as a block anchor
  definition, not as a standalone inline expression.
- The existing `InlineNode.blockReference` case is probably a modeling mistake
  or an unfinished internal concept, not a user-visible syntax we should bless.

If later we want a shorthand local block-reference syntax, it should be added
deliberately rather than inferred from this dead node.

## Open Questions For V2

These are not current-parser quirks so much as decisions the new spec should
make explicitly.

### 1. Embed payload semantics

Question:

- What exactly does the right-hand side of `![[target|...]]` mean?

Likely answer:

- Parse it as syntax first.
- Interpret it semantically by target type later:
  - note/block embed alias
  - image sizing/options
  - possibly future structured-data parameters

### 2. Frontmatter recovery

Question:

- If frontmatter is opened and not closed, should the typed AST expose an
  incomplete frontmatter node or downgrade it at some layer?

Recommendation:

- Keep it as an incomplete node in the CST.
- Let higher layers decide how tolerant they want to be.

### 3. Math exactness

Question:

- How closely do we want math parsing to match Obsidian/MathJax behavior,
  especially around escaping, whitespace, and block-vs-inline disambiguation?

Recommendation:

- Decide this explicitly in V2 rather than inheriting the current mixed model.

### 4. Image alt text as syntax tree content

Question:

- Should image alt text be parsed as inline content or stored as raw text?

Recommendation:

- If we want strong markdown parity, parse it as inline content.
- If we want a simpler AST, keep it raw but document that choice explicitly.

## Recommended V2 Posture

If I compress this down to the highest-value decisions:

- Keep Obsidian-specific extensions that are clearly part of the product.
- Normalize all core markdown behavior to CommonMark/GFM.
- Drop parser-artifact behavior, especially around HTML, lists, tables, links,
  escapes, and emphasis.
- Treat incomplete syntax as incomplete syntax, not as plain text.
- Do not assume every dead AST node should become a real language feature:
  `autolink`, `hardLineBreak`, and `softLineBreak` should; bare inline
  `blockReference` probably should not.
