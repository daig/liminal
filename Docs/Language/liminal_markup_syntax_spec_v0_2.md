# Liminal Markup Syntax Spec v0.2 Draft

Status: draft for review

Companion documents:

- [Liminal Markup Motivation](./liminal_markup_motivation.md) captures the
  non-normative design rationale.
- [Liminal Markup Syntax Spec v0.1](./liminal_markup_syntax_spec_v0_1.md) is
  retained as historical design context.

This document defines the source syntax and parse/lowering contract for
Liminal Markup v0.2.

The language is Markdown-like in places, but it is not a Markdown dialect and
does not target CommonMark, GFM, or Obsidian compatibility. Markdown-like
constructs are surface forms for typed semantic nodes.

Normative words are used as follows:

- "must" means required for v0.2 conformance.
- "should" means recommended unless there is a documented implementation reason.
- "may" means optional.

## 1. Core Model

Liminal Markup has these layers:

```text
source text
  -> lossless CST
  -> typed semantic tree
  -> schema validation, rendering, editing, indexing
```

The CST is schema-free. It records surface syntax, delimiters, trivia, source
ranges, and errors. CST node kinds name syntax forms such as `atxHeading`,
`typedBlock`, `wikilink`, and `pipeTable`; they do not name user schema types.

The semantic tree is typed. Every nontrivial construct lowers to this shape:

```text
Node {
  kind: document | block | inline | value | template
  type: QName
  id?: Anchor
  fields: ordered Field*
  content?: InlineContent | BlockContent
  source?: SurfaceInfo
}

Field {
  name: FieldName
  value: Value
}
```

Document source lowers to an ordered sequence of document items:

```text
DocumentItem =
  block node
  | value node
  | schema declaration
  | template declaration
  | directive
```

Renderable content is a subset of document items. Top-level value declarations
are valid document items and do not render by default.

Schema validation must never change CST shape or tokenization. Unknown typed
constructors are syntactically valid and become unresolved semantic nodes until
the schema pass resolves them.

## 2. Source and Lexical Rules

Source is Unicode text. The CST must preserve the exact source bytes. Source
ranges are byte ranges in the original encoding used by the implementation.

The grammar treats these as newline sequences:

```text
LF
CRLF
CR
```

The CST preserves the exact newline spelling.

Horizontal whitespace is space or tab. Structural indentation is measured in
columns; a tab advances to the next multiple of four columns. Implementations
must preserve the original whitespace tokens.

Backslash escapes are recognized in inline content and structured quoted
strings. Outside those contexts, backslash is ordinary text unless a construct
explicitly says otherwise.

### 2.1 Names

```ebnf
Ident       ::= IdentStart IdentContinue*
IdentStart  ::= ASCII letter | "_"
IdentContinue ::= ASCII letter | ASCII digit | "_" | "-"
QName       ::= Ident ("." Ident)*
FieldName   ::= Ident
Anchor      ::= "#" AnchorIdent
AnchorIdent ::= ASCII letter | ASCII digit
                (ASCII letter | ASCII digit | "_" | "-")*
```

Names are case-sensitive.

Reserved top-level block names are:

```text
schema
template
MathBlock
HtmlBlock
```

Reserved template-control block names are:

```text
if
for
```

Other names are not reserved. A schema may still reject or shadow a name during
semantic validation.

### 2.2 Scalar Values

Structured value syntax recognizes these scalar token classes:

```text
"quoted string"
123
-123
12.5
-12.5
true
false
null
bare-symbol
https://example.org/path?q=1
1815-12-10
```

Numbers and keywords are recognized only when the whole scalar token matches
the corresponding pattern. For example, `1815-12-10` is a bare scalar token,
not an integer expression.

Quoted strings use double quotes and do not contain raw newlines.

Recognized string escapes:

```text
\"   double quote
\\   backslash
\n   newline
\r   carriage return
\t   tab
\u{H+} Unicode scalar by hexadecimal code point
```

A bare scalar is a nonempty run of characters in value position. It ends before
whitespace or one of these structural delimiters:

```text
, ] } )
```

Bare scalars may contain `:`, `/`, `?`, `#`, `&`, `.`, and `-`. Final scalar
meaning is assigned by schema validation.

## 3. Document Structure

```ebnf
Document      ::= DocumentItem*
DocumentItem  ::= Frontmatter
                | Directive
                | SchemaBlock
                | TemplateBlock
                | ValueDeclaration
                | Block
                | BlankLine

Block         ::= Paragraph
                | Heading
                | List
                | BlockQuote
                | ThematicBreak
                | CodeBlock
                | MathBlock
                | HtmlBlock
                | CommentBlock
                | TypedBlock
                | PipeTable
                | EmbedBlock
```

Blank lines are preserved in the CST. They do not produce semantic nodes unless
an implementation provides an explicit whitespace-aware view.

`InlineContent` means a sequence of inline nodes and text up to the current
inline delimiter or block boundary. `BlockContent` means a sequence of blocks
and blank lines up to the current block delimiter or container boundary.

A block opener is recognized only at a logical line start. In ordinary block
sequences, up to three extra leading spaces may precede a block opener. Inside
list items and block literals, the current container indentation is considered
the logical line start.

There are no indented code blocks and no lazy continuation lines.

## 4. Document-Start Frontmatter

YAML frontmatter is recognized only at the start of the file.

```text
---
raw yaml
---
```

Rules:

- The opening delimiter must be the first line of the file, except for an
  optional byte-order mark.
- The opening and closing delimiter lines must be exactly `---`, aside from the
  line ending.
- Content between the delimiters is raw text.
- If EOF is reached before a closing delimiter, the CST contains an incomplete
  frontmatter node.
- A `---` line anywhere else is parsed by normal block rules.

Semantic form:

```liminal
@Frontmatter{format: yaml, raw: "..."}
```

## 5. Line Directives

Line directives begin with `::` and are recognized at logical line start.

```liminal
::use type "./schema.lim" as schema
::use data "./people.lim" as people
::use "./bibliography.lim" only { Entry, Citation }
```

Directive grammar:

```ebnf
Directive      ::= "::" "use" UseDirectiveBody Newline
UseDirectiveBody ::= UseKind? StringOrBare ImportFilter? ImportAlias?
UseKind        ::= "type" | "data"
ImportFilter   ::= "only" "{" QNameList? "}"
ImportAlias    ::= "as" Ident
QNameList      ::= QName ("," QName)* ","?
StringOrBare   ::= QuotedString | BareScalar
```

Directives affect schema and reference resolution only. They do not affect base
parsing.

## 6. Block Syntax

### 6.1 Paragraphs

A paragraph is one or more nonblank lines that do not begin with another block
or document-item opener.

Paragraph content is parsed as inline content. Newline boundaries inside a
paragraph become soft break inline nodes. A backslash immediately before the
newline creates a hard break and removes the backslash from rendered text.

Trailing block IDs may attach to paragraphs:

```text
Paragraph text ^block-id
```

The suffix is recognized only if:

- it appears at the end of the paragraph after optional trailing whitespace,
- it is preceded by at least one whitespace character,
- the ID matches `AnchorIdent`.

The suffix lowers to `Node.id`; it is not an inline node.

### 6.2 Headings

Only ATX headings are core syntax.

```text
# Heading 1
## Heading 2
###### Heading 6
```

Rules:

- The marker is a run of one to six `#` characters.
- The marker must be followed by at least one space or tab.
- Heading body is parsed as inline content.
- Optional closing `#` markers are recognized only when preceded by whitespace.
- A trailing block ID suffix may attach to the heading, using the paragraph
  block-ID rules.

Semantic form:

```liminal
@Heading{level: 1}[Heading 1]
```

Setext headings are not part of v0.2.

### 6.3 Thematic Breaks

A thematic break is a line containing at least three copies of the same marker
character, optionally separated by spaces or tabs.

Allowed marker characters:

```text
-
*
_
```

Examples:

```text
---
* * *
_ _ _
```

At document start, `---` is frontmatter only when it satisfies the frontmatter
rules. Otherwise it is a thematic break.

### 6.4 Lists

Unordered list markers:

```text
-
*
+
```

Ordered list marker:

```text
ASCII digits followed by "."
```

Examples:

```markdown
- First
- Second

1. First
2. Second
```

Rules:

- A list is a sequence of adjacent list items with the same ordered/unordered
  kind and compatible marker family.
- Marker-family changes start a new list.
- Ordered list start number is the number on the first item.
- List items contain block content.
- Continuation content must be indented to the item content column.
- Nested lists are parsed recursively from continuation content.
- Lazy continuation is not allowed.

Task markers may appear immediately after the list marker and following
whitespace:

```text
[ ] unchecked
[x] checked
[X] checked
```

A trailing block ID suffix on the opening paragraph of a list item attaches to
the `ListItem` semantic node.

Semantic shape:

```liminal
@List{ordered: false, marker: dash, items: [
  @ListItem{body: @{First}}
]}
```

### 6.5 Block Quotes

Every quoted content line must begin with `>` after the current container
indentation.

```markdown
> This is quoted.
>
> - Lists inside quotes are parsed recursively.
```

Rules:

- The `>` marker may be followed by one space or tab, which is not part of the
  quoted content.
- A nonblank line without a `>` marker ends the block quote.
- Blank quoted lines must still contain the `>` marker.
- Lazy quote continuation is not allowed.

Semantic form:

```liminal
@BlockQuote{
  body: @{ ... }
}
```

### 6.6 Fenced Code Blocks

Only fenced code blocks are core syntax.

````markdown
```python
print("hello")
```
````

Rules:

- Opening fence is a run of at least three backticks or at least three tildes.
- The full opening run length is recorded.
- The rest of the opening line is the raw info string, trimmed only for the
  normalized semantic `language` field.
- Closing fence must use the same character and at least the opening run
  length.
- Closing fence line may contain only indentation, the fence run, optional
  trailing whitespace, and newline.
- If EOF is reached before a closing fence, the CST contains an incomplete code
  block.

Semantic form:

```liminal
@CodeBlock{language: python, text: "print(\"hello\")\n"}
```

Indented code blocks are not part of v0.2.

### 6.7 Math Blocks

Math blocks are raw TeX block content.

Core shorthand:

```markdown
$$
E = mc^2
$$
```

Optional shorthand:

```markdown
\[
E = mc^2
\]
```

Generic field fallback:

```liminal
@MathBlock{tex: "E = mc^2\n"}
```

Core raw fence surface:

```liminal
:::MathBlock
E = mc^2
:::
```

Rules:

- `$$` opening and closing delimiter lines must be exactly `$$`, aside from the
  line ending.
- `\[` closes only at a line whose content is exactly `\]`, aside from the line
  ending.
- `:::MathBlock` is a reserved raw block surface. Its body is not parsed as
  normal typed-block content.
- Content is raw text and is not parsed as block or inline markup.
- If EOF is reached before closing, the CST contains an incomplete math block.

Semantic form:

```liminal
@MathBlock{tex: "E = mc^2\n"}
```

Bare `$...$` inline math is not part of v0.2.

### 6.8 HTML Blocks

Raw HTML does not participate in document structure unless explicitly marked.

Core raw fence surface:

```liminal
:::HtmlBlock
<div class="warning">
  Raw HTML here.
</div>
:::
```

Rules:

- `:::HtmlBlock` is a reserved raw block surface. Its body is not parsed as
  normal typed-block content.
- HTML block content is raw text.
- The base parser does not parse HTML tags.
- A line beginning with `<tag` is ordinary paragraph text unless it appears
  inside an explicit `HtmlBlock` surface.

Generic field fallback:

```liminal
@HtmlBlock{raw: "<div>Raw HTML here.</div>"}
```

Semantic form:

```liminal
@HtmlBlock{raw: "..."}
```

### 6.9 Comment Blocks

A comment block begins with a line that contains only optional indentation,
`%%`, optional trailing whitespace, and a newline. It ends at the next line
with the same shape.

```text
%%
hidden content
%%
```

Rules:

- Comment content is raw text.
- Comments do not nest.
- `%%` inside a paragraph is an inline comment, not a comment block.
- If EOF is reached before a closing delimiter, the CST contains an incomplete
  comment block.
- Comment blocks do not render by default.

Semantic form:

```liminal
@CommentBlock{raw: "hidden content\n"}
```

### 6.10 Typed Blocks

Typed block constructors use colon fences.

```liminal
:::Callout#warning-1{kind: warning, title: @[Careful]}
This is the body.
:::
```

Grammar:

```ebnf
TypedBlock ::= ColonRun QName Anchor? Fields? Newline
               Block*
               MatchingColonRun

ColonRun   ::= ":::" ":"*
```

Rules:

- The opening colon run must contain at least three colons.
- `QName` follows the colon run immediately.
- The closing fence must contain exactly the same number of colons as the
  opening fence.
- The closing fence line may contain only indentation, the colon run, optional
  trailing whitespace, and newline.
- The body is parsed as normal block content unless the name is a reserved
  block name with its own body grammar.
- If EOF is reached before closing, the CST contains an incomplete typed block.

Body content is assigned to the schema field marked `@content`.

### 6.11 Pipe Tables

Pipe tables are a core surface for the `Table` block type.

```markdown
| Name | Born |
| ---- | ---: |
| Ada Lovelace | 1815 |
```

Rules:

- A table consists of a header row, delimiter row, and zero or more body rows.
- Rows are split on unescaped `|` characters.
- `\|` represents a literal pipe in cell source.
- Leading and trailing outer pipes are optional.
- Header and delimiter rows must have the same column count.
- A delimiter cell must match `:?-{3,}:?`, with optional surrounding spaces.
- Body rows should have the same column count. Mismatched rows remain in the
  CST and produce diagnostics.
- Cell content is parsed as inline content.

Alignment:

```text
---   none
:---  left
---:  right
:---: center
```

Semantic form:

```liminal
@Table{
  columns: [
    @Column{label: @[Name]}
    @Column{label: @[Born], align: right}
  ]
  rows: [
    @Row{cells: [@[Ada Lovelace], @[1815]]}
  ]
}
```

If a `Table` cannot be printed safely as a pipe table, canonical printing must
fall back to generic typed syntax.

### 6.12 Embed Blocks

A structured embed may appear as a block when it occupies a whole logical line.

```liminal
!{Person}[Ada Lovelace](#ada)
```

Obsidian-style wiki embeds may also appear as whole-line block embeds:

```liminal
![[Note#Heading|payload]]
```

Semantic forms:

```liminal
@EmbedBlock{expected: Person, fallback: @[Ada Lovelace], target: "#ada"}
@WikiEmbedBlock{target: "Note#Heading", payload: "payload"}
```

The same source forms inside inline content lower to inline embed types.

## 7. Inline Syntax

Inline content is parsed inside paragraphs, headings, table cells, inline
content literals, link labels, and constructor inline bodies.

Unmatched inline openers remain literal text unless this spec requires an
incomplete CST node for editor recovery.

Inline parsing recognizes constructs in this order:

```text
1. code spans
2. escaped punctuation
3. inline comments
4. inline math shorthand
5. structured typed constructors and structured embeds
6. wiki embeds and wikilinks
7. markdown images and links
8. inline footnotes
9. template interpolation
10. strong, emphasis, strikethrough, highlight
11. autolinks
12. text
```

Code spans protect their contents from all other inline parsing.

### 7.1 Escapes

In inline content, a backslash before ASCII punctuation escapes that punctuation
and removes the backslash from the semantic text.

Examples:

```text
\* literal asterisk
\] literal bracket in bracketed content
```

If the following character is not ASCII punctuation, the backslash is literal.

### 7.2 Code Spans

```markdown
`code`
```

Rules:

- Opening delimiter is a run of one or more backticks.
- Closing delimiter is a later run of exactly the same length.
- Content is raw text.
- Newlines may appear inside code spans.
- If no closing delimiter is found before the containing inline boundary, the
  CST contains an incomplete code span.

Semantic form:

```liminal
@CodeSpan{text: "code"}
```

### 7.3 Emphasis and Strong

```markdown
*emphasis*
**strong**
```

Rules:

- Only `*` is an emphasis delimiter in v0.2.
- `_` is ordinary text.
- A single `*` opens or closes emphasis.
- A double `**` opens or closes strong.
- Runs of three or more `*` are literal text.
- An opener must be followed by a non-whitespace character.
- A closer must be preceded by a non-whitespace character.
- Contents are parsed recursively as inline content.
- Unmatched delimiters remain literal text.

Semantic forms:

```liminal
@Emphasis[emphasis]
@Strong[strong]
```

### 7.4 Strikethrough and Highlight

```markdown
~~deleted~~
==highlighted==
```

Rules:

- Delimiters are exactly `~~` and `==`.
- Contents are parsed recursively as inline content.
- Delimiters do not cross code spans or other completed inline node
  boundaries.
- Unmatched delimiters remain literal text.

Semantic forms:

```liminal
@Strikethrough[deleted]
@Highlight[highlighted]
```

### 7.5 Links and Images

Markdown-style links:

```markdown
[label](https://example.org)
[label](https://example.org "Title")
```

Markdown-style images:

```markdown
![alt](image.png)
![alt](image.png "Title")
```

Rules:

- Label or alt text uses balanced brackets and is parsed as inline content.
- Destination is the text inside the balanced parentheses after the label.
- Parentheses may be nested when escaped or balanced.
- Optional title is a final quoted string after destination whitespace.
- Supported title quotes are double quotes and single quotes.
- If the closing `]` or `)` is missing, the CST contains an incomplete node.

Semantic forms:

```liminal
@Link{href: https://example.org}[label]
@Image{src: image.png, alt: @[alt], title: "Title"}
```

### 7.6 Autolinks

Angle autolinks are supported for URI and email-like targets.

```markdown
<https://example.org>
<mailto:ada@example.org>
<ada@example.org>
```

Rules:

- URI autolinks must begin with `http:`, `https:`, or `mailto:`.
- Email autolinks must contain one `@` and no whitespace.
- Other angle-bracket text is ordinary text.
- Inline HTML is not part of v0.2.

Autolinks lower to `Link` with body equal to the displayed target.

### 7.7 Wikilinks

```liminal
[[target]]
[[target|alias]]
```

Target grammar:

```ebnf
WikiTarget  ::= NotePath? ("#" WikiAnchor)?
WikiAnchor  ::= "^" AnchorIdent | HeadingText
```

Rules:

- Target source is captured and parsed syntactically, not resolved during base
  parsing.
- Empty note path is valid when an anchor is present, as in `[[#Heading]]` and
  `[[#^block-id]]`.
- The first unescaped `|` separates target from alias.
- Alias is parsed as inline content.
- If closing `]]` is missing, the CST contains an incomplete wikilink node.

Semantic form:

```liminal
@WikiLink{target: "Note#Heading"}[alias]
```

### 7.8 Wiki Embeds

```liminal
![[target]]
![[target|payload]]
```

Rules:

- Target parsing is the same as wikilinks.
- The first unescaped `|` separates target from payload.
- Payload is preserved as raw source text.
- If closing `]]` is missing, the CST contains an incomplete wiki embed node.

Inline semantic form:

```liminal
@WikiEmbedInline{target: "Note#Heading", payload: "payload"}
```

When the source occupies a whole logical line, it lowers to `WikiEmbedBlock`.

### 7.9 Structured Embeds

```liminal
!{ExpectedType}[fallback](target)
![fallback](target)
```

Rules:

- Expected type is optional.
- Fallback text is optional and parsed as inline content.
- Target is raw source inside balanced parentheses.
- If the closing `]` or `)` is missing, the CST contains an incomplete embed
  node.

Inline semantic form:

```liminal
@EmbedInline{expected: ExpectedType, fallback: @[fallback], target: "target"}
```

When the source occupies a whole logical line, it lowers to `EmbedBlock`.

Markdown image syntax is a specialized image surface and lowers to `Image`, not
to `EmbedInline`.

### 7.10 Inline Math

Inline math shorthand uses `\(` and `\)`.

```liminal
\(x^2 + y^2\)
```

Rules:

- Content is raw text.
- Inline math cannot cross a block boundary.
- If no closing `\)` is found before the containing inline boundary, the CST
  contains an incomplete math node.
- Bare `$...$` is ordinary text in v0.2.

Semantic form:

```liminal
@MathInline{tex: "x^2 + y^2"}
```

### 7.11 Inline HTML

Inline HTML is not parsed from raw `<tag>` syntax.

Generic typed fallback:

```liminal
@HtmlInline{raw: "<span class=\"x\">raw</span>"}
```

### 7.12 Inline Comments

Inline comments use `%%`.

```text
visible %% hidden %% visible
```

Rules:

- Comment content is raw text.
- Comments do not nest.
- Inline comments may span soft line breaks but may not cross a blank line or
  block boundary.
- If no closing delimiter is found before the containing inline boundary, the
  CST contains an incomplete inline comment node.
- Inline comments do not render by default.

Semantic form:

```liminal
@CommentInline{raw: " hidden "}
```

### 7.13 Inline Footnotes

```markdown
^[footnote content]
```

Rules:

- Footnote content uses balanced brackets.
- Content is parsed recursively as inline content.
- If closing `]` is missing, the CST contains an incomplete footnote node.

Semantic form:

```liminal
@FootnoteInline[footnote content]
```

### 7.14 Template Interpolation

Template interpolation is valid in inline content and block template bodies.

```liminal
Hello, ${person.name}.
```

Expression grammar:

```ebnf
Expr       ::= NullCoalesce
NullCoalesce ::= Projection ("??" Projection)?
Projection ::= Primary (("." Ident) | ("[" Integer "]"))*
Primary    ::= Ident | Literal | "&" RefTarget | "(" Expr ")"
Literal    ::= QuotedString | Integer | Number | "true" | "false" | "null"
```

Function calls are not part of v0.2 template expressions.

Semantic form:

```liminal
@Interpolation{expr: "person.name"}
```

## 8. Generic Typed and Value Syntax

Generic typed syntax is the required fallback for every semantic node.

### 8.1 Typed Constructors

```liminal
@Type
@Type#id
@Type{field: value}
@Type{field: value}[inline content]
```

Grammar:

```ebnf
TypedConstructor ::= "@" QName Anchor? Fields? InlineBody?
InlineBody       ::= "[" InlineContent? "]"
```

Rules:

- There is no whitespace between `@` and `QName`.
- Fields are optional.
- Inline body is optional.
- Context determines whether the constructor appears as a document value
  declaration, inline node, or value expression.
- Schema validation determines whether the resolved type is allowed in that
  context.
- If a type has exactly one `@content` field, constructor body content maps to
  that field.
- If no matching `@content` field exists, body content is retained but schema
  validation reports an error.

At logical line start, a typed constructor whose source consumes a complete
logical block is a value declaration unless schema validation resolves it as a
block type and the syntactic form is valid as a block.

### 8.2 Fields

```liminal
{
  name: "Ada Lovelace"
  born: 1815-12-10
}
```

Grammar:

```ebnf
Fields    ::= "{" FieldList? "}"
FieldList ::= Field (FieldSep Field)* FieldSep?
Field     ::= FieldName ":" Value
FieldSep  ::= "," | Newline
```

Rules:

- Newline separates fields only at the current record nesting level.
- Comma may be used instead of newline.
- Trailing separators are allowed.
- Duplicate fields are syntactically valid and preserved in source order.
- Unless a schema explicitly allows duplicates, schema validation reports a
  duplicate-field error.

### 8.3 Values

```ebnf
Value          ::= Scalar
                 | Reference
                 | StructuredEmbedValue
                 | ListValue
                 | RecordValue
                 | TypedConstructor
                 | InlineLiteral
                 | BlockLiteral

ListValue      ::= "[" ValueList? "]"
ValueList      ::= Value (ValueSep Value)* ValueSep?
ValueSep       ::= "," | Newline
RecordValue    ::= "{" FieldList? "}"
InlineLiteral  ::= "@[" InlineContent? "]"
BlockLiteral   ::= "@{" SingleLineBlockContent? "}"
                 | "@{" Newline BlockContent? BlockLiteralClose
```

Rules:

- Newline separates list values only at the current list nesting level.
- Values on the same line must be comma-separated.
- Inline literals parse their content as inline content.
- Block literals parse their content as block content.
- `@[` starts an inline literal, not a typed constructor.
- `@{` starts a block literal, not a typed constructor.
- Single-line block literals parse their inner source as one paragraph block.

Block literal close rule:

- The closing `}` must appear alone on a logical line at the indentation level
  of the `@{` opener for multiline block literals.
- If EOF is reached before closing, the CST contains an incomplete block
  literal.

### 8.4 References

References are values.

```liminal
&ada
&people.ada
&<./people.lim#ada>
```

Grammar:

```ebnf
Reference ::= "&" RefTarget
RefTarget ::= QName | "<" ExternalRefText ">"
```

Rules:

- `&ada` is a local reference.
- `&people.ada` is a qualified reference.
- `&<...>` is an external reference target captured as raw text.
- References do not render by themselves.

### 8.5 Structured Embed Values

Embed syntax may appear as a value where a schema expects an embed-like value.

```liminal
cover: !{Image}[Cover](cover.png)
```

Value semantic form:

```liminal
@EmbedValue{expected: Image, fallback: @[Cover], target: "cover.png"}
```

## 9. Schema Blocks

Schemas live in explicit schema blocks.

```liminal
:::schema prelude
type Person : value = {
  name: str
  born?: date
}
:::
```

Grammar:

```ebnf
SchemaBlock ::= ColonRun "schema" SchemaName? Newline
                SchemaDecl*
                MatchingColonRun

SchemaName  ::= Ident
SchemaDecl  ::= TypeDecl | TemplateTypeDecl

TypeDecl    ::= "type" QName ":" NodeKind "=" TypeExpr Modifiers? Newline*
NodeKind    ::= "document" | "block" | "inline" | "value"

TemplateTypeDecl ::= "type" QName ":" "template" "=" TemplateSignature
                     Modifiers? Newline*
```

Type expressions:

```ebnf
TypeExpr    ::= PrimitiveType
              | QName
              | "[" TypeExpr "]"
              | "map" "<" TypeExpr ">"
              | "ref" "<" TypeExpr ">"
              | "embed" "<" TypeExpr ">"
              | "enum" "{" EnumCases? "}"
              | RecordType
              | VariantType
              | TypeExpr "?"

PrimitiveType ::= "str" | "bool" | "int" | "num" | "decimal"
                | "date" | "time" | "datetime" | "uri" | "id"
                | "target" | "type"
                | "inline" | "block" | "blocks" | "value" | "template"

RecordType  ::= "{" SchemaField* "}"
SchemaField ::= FieldName "?"? ":" TypeExpr Modifiers? Newline*

VariantType ::= "variant" "by" FieldName "{"
                  VariantCase*
                "}"
VariantCase ::= Ident ":" RecordType Newline*

EnumCases   ::= Ident ("," Ident)* ","?
```

Modifiers:

```ebnf
Modifiers ::= Modifier*
Modifier  ::= "@content"
            | "@default" "(" Value ")"
            | "@surface" "(" Ident ")"
            | "@readonly"
            | "@deprecated" "(" QuotedString ")"
```

Rules:

- Schema blocks are parsed without using the schema being declared.
- Type declarations are resolved by the schema pass.
- `T?` and `field?: T` both denote optionality. `field?: T` is preferred for
  record fields.
- Arbitrary unions are not part of v0.2.
- Variants must be discriminated.
- At most one field in a type declaration should be marked `@content`.
- If multiple fields are marked `@content`, validation reports an error.

## 10. Template Blocks

Templates are typed, pure transformations from values to value, inline, or
block content.

```liminal
:::template PersonCard(person: Person) -> blocks
:::Card{title: @[${person.name}]}
Born: ${person.born}
:::
:::
```

Grammar:

```ebnf
TemplateBlock ::= ColonRun "template" TemplateSignature Newline
                  TemplateBody
                  MatchingColonRun

TemplateSignature ::= QName "(" ParamList? ")" "->" TemplateResult
ParamList         ::= Param ("," Param)* ","?
Param             ::= Ident ":" TypeExpr
TemplateResult    ::= "value" | "inline" | "blocks"
```

Template body is parsed as block content with interpolation enabled.

Template control structures use typed block syntax with reserved names:

```liminal
:::if{test: person.bio}
${person.bio}
:::

:::for{item: link, in: person.links}
- [${link.label}](${link.href})
:::
```

These lower to template nodes, not arbitrary directives.

No host-language code execution, mutation, IO, or arbitrary function calls are
part of v0.2 templates.

## 11. Required Prelude

A v0.2 implementation must provide a prelude schema with at least these types.
The exact schema syntax may be generated internally, but the semantic shape
must match.

```liminal
:::schema prelude
type Document : document = {
  items: [DocumentItem]
}

type DocumentItem : value =
  variant by kind {
    block: { block: block }
    value: { value: value }
    schema: { name?: str, raw: str }
    template: { template: template }
    directive: { raw: str }
  }

type Frontmatter : value = {
  format: enum { yaml }
  raw: str
}

type Paragraph : block = {
  body: inline @content
}

type Heading : block = {
  level: int
  body: inline @content
}

type ThematicBreak : block = {}

type BlockQuote : block = {
  body: blocks @content
}

type List : block = {
  ordered: bool
  marker: enum { dash, asterisk, plus, decimal_dot }
  start?: int
  items: [ListItem]
}

type ListItem : value = {
  task?: enum { unchecked, checked }
  body: blocks @content
}

type CodeBlock : block = {
  language?: str
  info?: str
  text: str
}

type MathBlock : block = {
  tex: str
}

type HtmlBlock : block = {
  raw: str
}

type CommentBlock : block = {
  raw: str
}

type Table : block = {
  columns: [Column]
  rows: [Row]
  caption?: inline
}

type Column : value = {
  label: inline
  align?: enum { left, center, right }
}

type Row : value = {
  cells: [inline]
}

type EmbedBlock : block = {
  expected?: type
  fallback?: inline
  target: target
}

type WikiEmbedBlock : block = {
  target: target
  payload?: str
}

type SoftBreak : inline = {}

type HardBreak : inline = {}

type Emphasis : inline = {
  body: inline @content
}

type Strong : inline = {
  body: inline @content
}

type Strikethrough : inline = {
  body: inline @content
}

type Highlight : inline = {
  body: inline @content
}

type CodeSpan : inline = {
  text: str
}

type Link : inline = {
  href: uri
  title?: str
  body: inline @content
}

type Image : inline = {
  src: uri
  alt: inline
  title?: str
}

type WikiLink : inline = {
  target: target
  body?: inline @content
}

type EmbedInline : inline = {
  expected?: type
  fallback?: inline
  target: target
}

type WikiEmbedInline : inline = {
  target: target
  payload?: str
}

type MathInline : inline = {
  tex: str
}

type HtmlInline : inline = {
  raw: str
}

type CommentInline : inline = {
  raw: str
}

type FootnoteInline : inline = {
  body: inline @content
}

type Interpolation : inline = {
  expr: str
}

type EmbedValue : value = {
  expected?: type
  fallback?: inline
  target: target
}
:::
```

All typed nodes may carry `Node.id`. Identity is not modeled as an ordinary
field in the prelude.

## 12. Surface Readers and Printers

A surface reader maps source syntax to a typed node.

```text
Reader: SourceSpan -> Node
Printer: Node -> SourceText
```

Core surface readers include:

```text
atx heading       -> Heading
paragraph         -> Paragraph
list              -> List
blockquote        -> BlockQuote
code fence        -> CodeBlock
math fence        -> MathBlock
pipe table        -> Table
markdown link     -> Link
markdown image    -> Image
wikilink          -> WikiLink
wiki embed        -> WikiEmbedInline | WikiEmbedBlock
structured embed  -> EmbedInline | EmbedBlock | EmbedValue
typed constructor -> resolved QName node
```

Surface readers must obey these rules:

- They must not require schema knowledge to tokenize or build the CST.
- They must declare the semantic type they produce.
- They must preserve source spans.
- They must either be lossless or explicitly record normalization.
- They must have a generic typed fallback.
- They must not change global block-boundary rules.

Lossless printing:

```text
print_lossless(parse(source)) == source
```

Canonical printing:

```text
parse(print_canonical(node)) == node
```

Canonical printing should prefer registered surfaces only when they can satisfy
round-trip laws. Otherwise it must print generic typed syntax.

Canonical field order follows schema declaration order.

## 13. Error Recovery

The parser is an editor parser. It must preserve incomplete syntax explicitly.

The CST must contain incomplete nodes for:

- frontmatter
- directives
- schema blocks
- template blocks
- typed blocks
- code blocks
- math blocks
- HTML blocks
- comment blocks
- block literals
- typed constructors
- records
- lists
- inline literals
- code spans
- links
- images
- wikilinks
- embeds
- inline comments
- highlights
- strikethrough
- footnotes
- inline math
- interpolation

Recovery rules:

- Preserve every consumed source byte.
- Do not synthesize normalized source text.
- Prefer the smallest incomplete node that keeps surrounding block structure
  stable.
- Unknown typed names are not parse errors.
- Malformed fields, records, and lists produce error children but retain their
  containing typed constructor when possible.
- Schema validation diagnostics are separate from parse diagnostics.

Example:

```liminal
@Person{
  name "Ada"
}
```

This parses as a typed constructor containing a malformed field. The editor can
still know the cursor is inside a `Person` constructor.

## 14. Compatibility Notes

v0.2 intentionally differs from the prototype Markdown parser in these ways:

- It is not CommonMark-compatible.
- It does not support indented code blocks.
- It does not support lazy continuation in lists or block quotes.
- It does not support setext headings.
- It does not support inline HTML from raw `<tag>` syntax.
- It does not support bare `$...$` inline math.
- It does not treat arbitrary HTML-looking block lines as HTML blocks.
- It treats top-level typed value declarations as first-class document items.
- It requires every special surface form to have a typed semantic target and a
  generic typed fallback.

The intended migration path is semantic, not source-compatible. Existing
Markdown-like source may need normalization into v0.2 source or generic typed
syntax.

## 15. Minimal Complete Syntax Summary

````liminal
# Heading

Paragraph with *emphasis*, **strong**, `code`, [[Wiki]], and [link](url).

- [x] Task item
  Continuation paragraph.

> Quote line
> still quote

```lang
code
```

$$
math
$$

:::Callout#id{kind: warning, title: @[Careful]}
Block body.
:::

@Person#ada{
  name: "Ada Lovelace"
  born: 1815-12-10
  bio: @{
    Block content value.
  }
}

!{Person}[Ada Lovelace](#ada)

| Name | Born |
| ---- | ---: |
| Ada | 1815 |

::use type "./schema.lim" as schema
````

The generic typed forms that must always be accepted are:

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
