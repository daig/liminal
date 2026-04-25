# Current Markdown Parser Spec

This document records the syntax actually recognized by the current Swift parser in
`liiminal/liiminal/Document/BlockParser.swift` and
`liiminal/liiminal/Document/InlineParser.swift`.

It is intended as the behavioral source of truth for the Rust/cstree rewrite.
It describes the language the parser accepts today, including quirks and
mismatches with the intended feature set.

## Scope

- This is a parser spec, not a renderer spec.
- The block parser runs first over the entire document.
- The inline parser only runs inside:
  - heading content
  - paragraph content
  - list item content
  - table cell content
- Trailing block IDs are stripped before inline parsing for headings,
  paragraphs, and list items.
- Some AST node kinds exist but are never produced by the parser; those are
  called out explicitly below.

## Notation

- `BOL` = beginning of line
- `EOL` = end of line, before the terminating `\n`
- `NL` = `\n`
- `SP` = literal space
- `WS` = any Swift `Character.isWhitespace`
- `trimmed` = the line with a trailing `\n` removed

## Overall Parsing Model

The block parser is line-oriented and stateful. Source is split into lines while
preserving their terminating `\n`.

At top level, each incoming line is classified in this order:

1. blank line
2. blockquote line
3. list item line
4. ATX heading
5. fenced code opener
6. display LaTeX block opener
7. frontmatter opener
8. thematic break
9. HTML block opener
10. paragraph continuation

That ordering is part of the grammar. A line is parsed by the first rule that
matches.

## Block Grammar

### Blank lines

A line is a blank line if `trimmed` is empty or every character in `trimmed` is
whitespace.

Accepted form:

```text
blank_line := { WS } NL?
```

Behavior:

- Any pending paragraph, list, or blockquote is flushed before the blank line.
- The blank line becomes its own `blankLine` block.

### Blockquotes

A top-level line starts or continues a blockquote if `trimmed.hasPrefix(">")`.

Accepted form:

```text
blockquote_line := ">" [ SP ] { any_char_except_NL } NL?
```

Behavior:

- Consecutive blockquote lines are grouped into one blockquote block.
- Each grouped line is rewritten before recursive parsing:
  - if it begins with `"> "`, drop the first two characters
  - else if it begins with `">"`, drop the first character
  - then append `\n`
- The stripped inner text is recursively reparsed by the full block parser.
- There is no lazy continuation. A non-`>` line always ends the blockquote.
- Nesting happens by recursion, not by counting `>` markers in one pass.

### Lists

A line is a list item if it matches one of these forms after zero or more
leading literal spaces:

```text
unordered_marker := "-" | "*" | "+"
ordered_marker   := digit { digit } "."
task_marker      := "[" (" " | "x" | "X") "]" [ SP ]

list_item_line :=
  { SP } unordered_marker SP [ task_marker ] { any_char_except_NL } NL?
  |
  { SP } ordered_marker SP [ task_marker ] { any_char_except_NL } NL?
```

Behavior:

- Only literal spaces count toward indentation. Tabs are not treated specially.
- Indentation is stored as `leading_space_count / 2` using integer division.
  Odd numbers of spaces are accepted and truncated.
- Ordered lists only recognize `1.` style markers, never `1)`.
- Consecutive list-item lines are grouped into one `list` block even if marker
  kind changes midway.
- The list block's `ordered` flag is taken from the first item only.
- The list block's `startNumber` is the first item's parsed number, or `0` for
  unordered lists.
- Each source line is exactly one list item. There is no multiline item body and
  no recursive child-list structure.
- A task checkbox is recognized only immediately after the marker:
  - `[ ]` => unchecked
  - `[x]` or `[X]` => checked
- Trailing block IDs are stripped from the item text before inline parsing.

Important quirks:

- `- - -` parses as a list item, not a thematic break.
- `* *` parses as a list item.
- Mixed marker runs like:

```text
- one
1. two
+ three
```

become a single list block with three items.

### ATX headings

A line is a heading only if it starts at column 0 with `#`.

Accepted form:

```text
heading :=
  "#" | "##" | "###" | "####" | "#####" | "######"
  SP
  heading_text
  NL?
```

Behavior:

- Heading level is the number of leading `#`, from 1 through 6.
- A space after the marker is required.
- Indented headings are not recognized.
- Trailing `#` markers are stripped only if there is at least one space before
  the trailing run.

Examples:

- `## title ##` => content is `title`
- `## title##` => content is `title##`

- A trailing block ID suffix is then removed from the heading content before
  inline parsing.

### Fenced code blocks

Fence openers are recognized only at column 0.

Accepted opener:

```text
fence_char   := "`" | "~"
fence_open   := fence_char fence_char fence_char { fence_char } [ { WS } info ]
info         := { any_char_except_NL }
```

Behavior:

- The opener must begin the line directly; leading spaces are not allowed.
- The opening fence length is the full run length, minimum 3.
- The remainder of the line, trimmed for surrounding whitespace, becomes the
  optional language/info string.

Accepted closer while inside a fenced code block:

```text
fence_close := { WS } fence_char{N_or_more} { WS } NL?
```

where `N` is the opening fence length.

Closer behavior:

- Leading and trailing whitespace on the closer are ignored.
- After trimming whitespace, the line must consist only of the fence character.
- A closer may be longer than the opener.
- A closer with any extra text does not close the block.

Examples:

- opener ````` closes with ``````, ````````, etc.
- ```` ``` nope ```` does not close

If EOF is reached before a closer, the block is still emitted as fenced code.

### Display LaTeX blocks

Accepted form:

```text
display_latex_open  := "$$" NL?
display_latex_close := "$$" NL?
```

Behavior:

- The opener line must be exactly `$$` with no surrounding spaces.
- Once opened, every following line is literal content until a line whose
  `trimmed` value is exactly `$$`.
- If EOF is reached before a closer, the block is still emitted.

### Frontmatter

Accepted form:

```text
frontmatter :=
  "---" NL
  { any_line_except_exact_closing_delimiter }
  "---" NL?
```

Behavior:

- Frontmatter is recognized only if the first line of the document is exactly
  `---`.
- Any preceding blank line or block prevents frontmatter recognition.
- The closing delimiter must also be exactly `---`.
- The content between open and close is stored verbatim, including internal
  newlines.

Important quirk:

- If EOF is reached before the closing `---`, the parser does not emit a
  `frontmatter` block. It falls back to a normal paragraph containing the
  opening delimiter and all accumulated text.

### Thematic breaks

Accepted form:

```text
thematic_break := line whose non-whitespace characters are
                  at least 3 copies of the same char,
                  where that char is "-" or "*" or "_"
```

Behavior:

- Whitespace is ignored for the check.
- Because list-item detection runs earlier, some CommonMark-style spaced forms
  are captured as list items instead.

Examples:

- `---` => thematic break
- `***` => thematic break
- `_ _ _` => thematic break
- `- - -` => list item, not thematic break
- `* *` => list item, not thematic break

### HTML blocks

HTML blocks are recognized only if a top-level line starts with `<` at column 0.

The parser supports these opener classes:

```text
type_2_comment         := "<!--"
type_3_processing_inst := "<?"
type_5_cdata           := "<![CDATA["   (case-insensitive)
type_4_declaration     := "<!" letter
tag_name               := letter { letter | digit | "-" }
tag_opener             := "<" tag_name ...
closing_tag            := "</" tag_name ...
```

Tag-name parsing rules:

- After the tag name, the next character must be whitespace, `>`, `/`, or EOL.
- Tag matching is case-insensitive.

Recognized end conditions:

- `<!-- ... -->` ends on the first line containing `-->`
- `<? ... ?>` ends on the first line containing `?>`
- `<!DECL ... >` ends on the first line containing `>`
- `<![CDATA[ ... ]]>` ends on the first line containing `]]>`
- `<script>`, `<pre>`, `<style>`, `<textarea>` blocks end on the first line
  containing the matching closing tag
- all other non-closing tags start a blank-line-terminated HTML block

Important quirks:

- The parser accepts any non-closing tag name for blank-line-terminated HTML,
  not just block-level tags.
- It does not require a complete tag. A line like `<span` starts an HTML block.
- A same-line end is only recognized for comment/PI/declaration/CDATA/type-1
  tag blocks, not for blank-line-terminated blocks.
- Blank-line-terminated HTML blocks consume every following nonblank line as raw
  HTML until a blank line or EOF.
- The terminating blank line is not included in `rawHTML`, but it is consumed by
  the block and does not become a separate `blankLine` node.

Example:

```text
<span>
next

end
```

parses as one HTML block containing `<span>\nnext\n`, followed by a paragraph
`end`.

### Tables

Tables are detected only when a would-be paragraph is flushed. They are never
recognized directly from the live top-level line classifier.

Accepted shape:

```text
table :=
  header_line
  separator_line
  { body_line }

header_line    := line containing at least one "|"
separator_line := line that:
                  - contains at least one "-"
                  - contains at least one "|"
                  - contains only "|", "-", ":", and spaces after trimming
body_line      := subsequent line containing at least one "|"
```

Behavior:

- The paragraph must start with the table header line.
- Table parsing stops at the first following line without `|`.
- Remaining lines after the table are reparsed as normal blocks.
- There is no validation that header, separator, and body rows have matching
  column counts.
- A row is split into cells only at literal `|` characters.
- Escaped pipes are not supported.
- A row needs at least two `|` characters to produce any cells.
- Leading/trailing outer pipes are not required for detection, but rows without
  at least two `|` end up with zero parsed cells.

Alignment parsing:

- Split the separator row on `|`, keeping empty leading/trailing fields.
- Trim spaces in each field.
- Alignment is:
  - `:...:` => centered
  - `:...`  => left
  - `...:`  => right
  - otherwise none
- The parser does not validate dash counts inside a separator cell.

Confirmed quirk:

```text
a | b
| - | : |
body | row
```

is accepted as a table even though the header row yields zero parsed cells.

### Paragraphs

A paragraph is the fallback for any consecutive top-level lines that did not
match an earlier block rule.

Behavior:

- Paragraph lines are accumulated verbatim, including internal newlines.
- On flush, trailing newlines are counted and removed from the content before
  inline parsing.
- A trailing block ID suffix is stripped before inline parsing.
- Internal newlines remain part of text content. They are not converted into
  line-break inline nodes.

If the accumulated lines begin with a table shape, the table is emitted first
and any remaining lines are recursively reparsed.

## Trailing Block IDs

Trailing block IDs are recognized only on headings, paragraphs, and list items.

Accepted form:

```text
block_id_suffix := { WS } "^" block_id { WS }
block_id        := block_id_char { block_id_char }
block_id_char   := letter | digit | "-" | "_"
```

Additional rules:

- There must be at least one whitespace character before `^`.
- The block ID must be at the very end, aside from trailing whitespace.
- The `^` is not preserved in the stored ID.

Examples:

- `text ^abc_1` => block ID `abc_1`
- `text^abc` => no block ID
- `text ^abc!` => no block ID

## Inline Grammar

The inline parser is a single left-to-right scanner over a string. At each
position it tries constructs in this exact order:

1. backslash-escaped punctuation
2. code span
3. comment
4. display LaTeX
5. inline LaTeX
6. embed
7. image
8. wikilink
9. standard link
10. emphasis / strong
11. strikethrough
12. highlight
13. inline footnote
14. plain text

Adjacent text nodes are merged after scanning.

### Escaped punctuation

Accepted form:

```text
escaped_punctuation := "\" ascii_punctuation
```

Behavior:

- If `\` is followed by ASCII punctuation, the scanner skips over both
  characters as plain text.
- The backslash is preserved in the resulting text.
- This suppresses special parsing at the next character position.

Confirmed example:

- `\*a*` remains a single text node `\*a*`

### Code spans

Accepted form:

```text
code_span := backtick_run code_content matching_backtick_run
backtick_run := "`" { "`" }
```

Behavior:

- The opening backtick run length is `N >= 1`.
- The closer must be a later backtick run of exactly the same length.
- Content is taken verbatim.
- Newlines are allowed inside the code span.
- There is no whitespace normalization or trimming around the content.

Example:

- ```` ``code ` inner`` ```` => content `code \` inner`

### Comments

Accepted form:

```text
comment := "%%" { any_char } "%%"
```

Behavior:

- The closing delimiter is the next `%%`.
- Newlines are allowed inside the comment.
- If no closing delimiter is found, parsing falls back to plain text.

### Display LaTeX inline

Accepted form:

```text
display_latex_inline := "$$" { any_char } "$$"
```

Behavior:

- The closing delimiter is the next `$$`.
- Newlines are allowed inside the content.
- This is distinct from block-level display LaTeX. Which one is used depends on
  block parsing first.

### Inline LaTeX

Accepted form:

```text
inline_latex := "$" inline_latex_content "$"
```

Opening and closing restrictions:

- The opening `$` must not be followed by whitespace.
- The closing `$` must be preceded by a non-whitespace character.
- Parsing stops at a newline. Inline LaTeX cannot span lines.

Examples:

- `$a$` => inline LaTeX
- `$ a$` => plain text
- `$a $` => plain text

### Wikilinks

Accepted form:

```text
wikilink := "[[" inner "]]"
inner    := target [ "|" alias ]
```

Behavior:

- Newlines are not allowed inside the construct.
- The first `|` splits target from alias.
- Alias is stored verbatim and may be empty.
- The target string is trimmed before target parsing.

Target parsing:

```text
target :=
  [ note_path ] [ "#" heading_or_block_anchor ]

heading_or_block_anchor :=
  "^" block_id
  |
  heading_text
```

Rules:

- Split on the first `#`.
- If the part after `#` starts with `^`, it becomes a block anchor.
- Otherwise it becomes a heading anchor.
- An empty note path is allowed, so local-only links like `[[#Heading]]` and
  `[[#^block]]` are accepted.

### Embeds

Accepted form:

```text
embed := "![[" inner "]]"
inner := target [ "|" params ]
```

Behavior:

- Same target parsing rules as wikilinks.
- The text after the first `|` is stored as `params`.
- `params` is not parsed further.

### Standard links

Accepted form:

```text
link := "[" link_text "]" "(" url_and_optional_title ")"
```

Behavior:

- The closing `]` is the first unescaped `]`.
- The closing `)` is the first unescaped `)`.
- Bracket and parenthesis nesting is not balanced.
- The link text is recursively inline-parsed.
- The raw text inside parentheses is trimmed before URL/title parsing.

Title parsing:

- If the trimmed inner string ends with `"`, the parser looks for the last `"`
  before it.
- Text after that last `"` becomes the title.
- Text before it, trimmed, becomes the URL.
- Otherwise the whole trimmed string is the URL and title is `nil`.

Confirmed quirk:

- `[a [b]](url)` does not parse as a link; it remains plain text.

### Images

Accepted form:

```text
image := "![" alt_text "]" "(" url_and_optional_title ")"
```

Behavior:

- URL/title parsing is identical to standard links.
- The alt text is stored as raw text and is not recursively inline-parsed.

### Emphasis and strong

Accepted delimiters:

```text
emphasis := "*" inner "*" | "_" inner "_"
strong   := "**" inner "**" | "__" inner "__"
```

Behavior:

- When the scanner sees `*` or `_`, it counts the full delimiter run.
- If the run length is at least 2, it tries `strong` first using only the first
  two delimiters.
- If `strong` fails, it tries `emphasis` using only the first delimiter.
- Opening requires the next character to exist and not be whitespace.
- Closing requires the previous character before the closing delimiter to not be
  whitespace.
- Closing delimiter search:
  - skips escaped characters
  - skips over code spans
  - otherwise uses the first matching delimiter sequence
- There are no CommonMark left/right-flanking rules beyond the whitespace checks
  above.
- Longer delimiter runs are decomposed greedily from the left.

Confirmed example:

- `***triple***` parses as:
  - a `strong("*")` node whose inner text is `*triple`
  - followed by a trailing text node `*`

### Strikethrough

Accepted form:

```text
strikethrough := "~~" inner "~~"
```

Behavior:

- The closer is the first later `~~`, using the same delimiter search helper as
  emphasis.
- There are no whitespace restrictions.
- The inner content is recursively inline-parsed.
- Empty content is accepted.

### Highlight

Accepted form:

```text
highlight := "==" inner "=="
```

Behavior:

- The closer is the first later `==`, using the same delimiter search helper as
  emphasis.
- There are no whitespace restrictions.
- The inner content is recursively inline-parsed.
- Empty content is accepted.

### Inline footnotes

Accepted form:

```text
inline_footnote := "^[" footnote_content "]"
```

Behavior:

- After `^[`, the parser balances nested `[` and `]` until depth returns to 0.
- The captured content is recursively inline-parsed.
- If brackets never balance, the whole construct falls back to plain text.

### Newlines inside inline content

The inline parser does not emit dedicated line-break nodes for paragraph
newlines.

Current behavior:

- `line1\nline2` becomes a single text node containing the newline.
- `\\\n` is not recognized as a hard line break.

## Syntax Present In The AST But Not Produced By The Parser

These `InlineNode` variants currently exist in the model and serializer, but the
current inline parser never emits them:

- `blockReference`
- `autolink`
- `hardLineBreak`
- `softLineBreak`

Practical consequences:

- Bare `^block-id` is plain text, not an inline node.
- `<https://example.com>` is plain text, not an autolink.
- Paragraph newlines remain embedded in text rather than becoming soft breaks.
- Backslash-newline remains embedded in text rather than becoming a hard break.

## Source-Compatible Quirks Worth Preserving Or Deliberately Changing

If the Rust rewrite wants exact compatibility, these behaviors need explicit
tests or explicit decisions:

- Frontmatter only exists when `---` is the very first line of the file.
- Unclosed frontmatter falls back to a paragraph instead of a frontmatter block.
- Blank-line-terminated HTML blocks accept any non-closing tag name and can
  absorb following ordinary text until a blank line.
- The terminating blank line of an HTML block is consumed by that block.
- Lists are line-based and flat; nesting is only represented as an integer
  indent on each item.
- Mixed ordered/unordered list markers are grouped into one list block.
- Some spaced thematic-break shapes are parsed as list items because list
  detection runs earlier.
- Table detection is permissive and can yield structurally odd tables with zero
  parsed header cells.
- Link parsing does not balance nested `[]` or `()`.
- Inline escapes preserve the backslash instead of unescaping the punctuation.
- `blockReference`, `autolink`, `hardLineBreak`, and `softLineBreak` are dead
  syntax from the parser's perspective even though they exist in the AST.
