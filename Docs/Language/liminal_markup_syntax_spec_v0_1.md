# Liminal Markup Syntax Spec v0.1

Below is a proposed **v0.1 syntax architecture** for a language I’ll call **Liminal Markup** for now. The key idea is:

> Markdown-like syntax is not the language’s semantic core.  
> The semantic core is a typed tree. Markdown-like forms, tables, math, HTML, and custom records are all surface syntaxes for typed nodes.

This follows Djot’s motivation of making Markdown-like syntax less ambiguous and easier to parse, but it diverges from Djot’s extension model: instead of attaching arbitrary attributes to existing markup nodes, extensions introduce **typed structures** with explicit schemas. Djot itself emphasizes fixing CommonMark parsing complexity and supports generic containers and attributes; here, the container/type system becomes the primary abstraction rather than an annotation layer. ([djot.net](https://djot.net/)) JTD is a useful inspiration because it deliberately limits schema expressiveness to shapes that map well to mainstream programming-language types, code generation, and portable validation; this proposal adopts that “small structural type system” spirit rather than full JSON Schema-style expressiveness. ([rfc-editor.org](https://www.rfc-editor.org/rfc/rfc8927.html)) The parser target is also realistic for Tree-sitter-style tooling: Tree-sitter is explicitly designed to build concrete syntax trees, update them incrementally as text changes, and remain useful under syntax errors. ([tree-sitter.github.io](https://tree-sitter.github.io/tree-sitter/))

---

# 1. Core design thesis

Liminal Markup has three layers:

```text
source text
  ↓
lossless CST
  ↓
typed AST
  ↓
rendered / edited / queried document model
```

The **base parser** must be able to parse a document without knowing any user schema. Unknown types still produce well-formed typed-constructor nodes. The **schema pass** resolves names, validates fields, checks templates, and interprets references.

The language has one semantic representation:

```text
Node<T> {
  kind: block | inline | value | document | template
  type: QName
  id?: Anchor
  fields: ordered map<FieldName, Value>
  content?: Inline[] | Block[]
  source?: SurfaceForm
}
```

Every special form lowers to this. For example:

```markdown
# Introduction
```

is not semantically “a Markdown heading.” It is sugar for something like:

```liminal
@Heading{level: 1}[Introduction]
```

Similarly:

```markdown
[the paper](https://example.org)
```

lowers to:

```liminal
@Link{href: https://example.org}[the paper]
```

And a table lowers to a `Table` record. Math lowers to `Math`. HTML lowers to `Html`. A custom `Callout` lowers to `Callout`.

The generic typed syntax must always be available. Custom syntaxes are only reader/printer views.

---

# 2. Source-level principles

The language should avoid Markdown’s hardest parsing cases.

Recommended rules:

```text
1. No indented code blocks.
2. No lazy continuation lines.
3. Block openers are recognized only at line start after optional indentation.
4. Multiline custom structures use explicit fences.
5. Inline constructs use balanced delimiters or remain literal.
6. Schema validation never changes the parse tree shape.
7. Unknown types are syntactically valid but semantically unresolved.
8. Every custom surface form must have a generic typed fallback.
```

This gives us a fast base grammar and lets editors maintain a useful tree even when schemas are missing, imports fail, or a user is midway through editing.

---

# 3. Block syntax

## 3.1 Paragraphs

A paragraph is one or more nonblank lines that do not begin with a recognized block opener.

```markdown
This is a paragraph with *inline markup*.
It continues here.
```

No lazy continuation is allowed inside lists or block quotes. If a paragraph belongs to a list item or quote, its continuation lines must be structurally inside that container.

---

## 3.2 Headings

```markdown
# Heading 1
## Heading 2
### Heading 3
```

Equivalent typed form:

```liminal
@Heading{level: 1}[Heading 1]
```

Optional explicit IDs should not use a general attribute syntax. Use the long typed form when identity matters:

```liminal
@Heading#intro{level: 1}[Introduction]
```

This avoids adding Markdown-style `{#id .class key=value}` annotations.

---

## 3.3 Lists

Unordered list:

```markdown
- First item
- Second item
```

Ordered list:

```markdown
1. First item
2. Second item
```

Continuation content must be indented.

```markdown
- First item

  Continued paragraph.

  - Nested item
```

Semantic form:

```liminal
@List{
  ordered: false,
  items: [
    @{ First item },
    @{ Second item }
  ]
}
```

Here `@{ ... }` is a block-content literal, described below.

---

## 3.4 Block quotes

Every quoted line must have a `>` prefix.

```markdown
> This is quoted.
> 
> - Lists inside quotes are parsed recursively.
```

No lazy quote continuation.

---

## 3.5 Code blocks

Only fenced code blocks exist.

````markdown
```python
print("hello")
```
````

Semantic form:

```liminal
@CodeBlock{
  language: python,
  text: "print(\"hello\")\n"
}
```

Indented code blocks are intentionally omitted.

---

## 3.6 Math blocks

Canonical typed form:

```liminal
:::Math{display: true}
E = mc^2
:::
```

Optional LaTeX/MathJax-inspired sugar:

```markdown
$$
E = mc^2
$$
```

or:

```markdown
\[
E = mc^2
\]
```

Both lower to:

```liminal
@Math{display: true, tex: "E = mc^2"}
```

Inline math should prefer an unambiguous canonical form:

```liminal
@Math{display: false}[x^2 + y^2]
```

The shorthand `\(x^2 + y^2\)` may be supported. Bare `$...$` should probably be avoided in the core grammar because it collides too easily with ordinary prose and currency.

---

## 3.7 HTML blocks

Raw HTML should not participate in document structure unless explicitly marked.

```liminal
:::Html
<div class="warning">
  Raw HTML here.
</div>
:::
```

Inline:

```liminal
@Html[<span class="x">raw</span>]
```

The base parser treats this as raw content. A later HTML-aware pass may parse it into an HTML tree, but that is not required for the core markup parser.

---

## 3.8 Typed block constructors

Custom block nodes use colon fences.

```liminal
:::Callout{kind: warning, title: @[Careful]}
This is the body of the callout.

It is parsed as normal block markup.
:::
```

Semantic form:

```text
Callout {
  kind: warning,
  title: Inline("Careful"),
  body: [
    Paragraph("This is the body of the callout."),
    Paragraph("It is parsed as normal block markup.")
  ]
}
```

The opening fence is:

```text
:::+ TypeName Anchor? Fields?
```

where `:::` may be any run of three or more colons. The closing fence must use the same number of colons alone on a line.

This permits nesting:

```liminal
::::Callout{kind: note}
Outer body.

:::Callout{kind: warning}
Inner body.
:::

Back to outer body.
::::
```

---

# 4. Inline syntax

## 4.1 Emphasis

```markdown
*emphasis*
**strong**
~~strikethrough~~
==highlight==
```

Suggested delimiter rule:

```text
* opens emphasis only when followed by nonspace.
* closes emphasis only when preceded by nonspace.
** has priority over *.
Underscore is not emphasis by default.
```

This avoids a large class of CommonMark ambiguity around intraword underscores.

Delimiter recovery is part of the editor-facing syntax contract:

| Surface | Closed form | Unclosed opener |
|---|---|---|
| `*text*` | `Emphasis` | Remains literal text; no diagnostic. |
| `**text**` | `Strong` | Remains literal text; no diagnostic. |
| `~~text~~` | `Strikethrough` | Parser may keep an incomplete CST node with a missing-closer diagnostic; semantic lowering treats it as literal text. |
| `==text==` | `Highlight` | Parser may keep an incomplete CST node with a missing-closer diagnostic; semantic lowering treats it as literal text. |

The distinction is intentional. `*` and `**` are common prose characters, so
they should not create noisy partial markup while typing. `~~` and `==` are
rarer and visually distinctive, so incomplete CST nodes are useful for live
highlighting and syntax discovery.

---

## 4.2 Code spans

```markdown
`code`
```

Backtick spans use the usual “matching run length” rule:

```markdown
``code containing ` backtick``
```

Semantic form:

```liminal
@Code[text: "code"]
```

or, using constructor syntax:

```liminal
@Code{ text: "code" }
```

---

## 4.3 Links

```markdown
[label](https://example.org)
```

Semantic form:

```liminal
@Link{href: https://example.org}[label]
```

Images are just typed embeds:

```markdown
![alt text](image.png)
```

Equivalent to:

```liminal
!{Image}[alt text](image.png)
```

---

## 4.4 Typed inline constructors

Inline typed content uses `@Type`.

```liminal
@Badge{status: success}[passing]
```

Semantic form:

```text
Badge {
  status: success,
  content: Inline("passing")
}
```

Typed atom with no inline content:

```liminal
@Icon{name: warning}
```

Typed inline with ID:

```liminal
@Term#crdt{key: crdt}[conflict-free replicated datatype]
```

---

## 4.5 Inline content literals

Inside structured values, use `@[ ... ]` for inline markup.

```liminal
title: @[A *rich* inline title]
```

This parses the content between brackets as inline markup, not as a plain string.

Escaping:

```liminal
@[A literal \] bracket]
```

---

## 4.6 Template interpolation

Template holes use `${...}`.

```liminal
Hello, ${person.name}.
```

Expression syntax should be deliberately small:

```text
expr       ::= name
             | expr "." field
             | expr "[" integer "]"
             | literal
             | expr "??" expr
```

No arbitrary host-language code. Function calls should be opt-in and schema-declared.

---

# 5. Structured value syntax

The structured data syntax is the heart of the language.

## 5.1 Generic typed values

```liminal
@Person#ada{
  name: "Ada Lovelace"
  born: 1815-12-10
  url: https://example.org/ada
}
```

Equivalent JSON-ish shape:

```json
{
  "type": "Person",
  "id": "ada",
  "fields": {
    "name": "Ada Lovelace",
    "born": "1815-12-10",
    "url": "https://example.org/ada"
  }
}
```

Fields are line-separated or comma-separated.

```liminal
@Person{name: "Ada Lovelace", born: 1815-12-10}
```

and:

```liminal
@Person{
  name: "Ada Lovelace"
  born: 1815-12-10
}
```

are both valid.

---

## 5.2 Scalars

Supported scalar tokens:

```text
"quoted string"
123
12.5
true
false
null
bare-symbol
https://example.org/path
1815-12-10
```

Bare scalars are parsed as lexical scalar tokens. Their final type is assigned by schema validation.

For example:

```liminal
born: 1815-12-10
```

is a bare scalar token. If the schema says `born: date`, it becomes a date. If the schema says `born: str`, it becomes a string.

This keeps the parser schema-independent.

---

## 5.3 Lists

```liminal
links: [
  @LinkRef{label: "Wikipedia", href: https://wikipedia.org}
  @LinkRef{label: "Archive", href: https://archive.org}
]
```

Comma form is also valid:

```liminal
links: [1, 2, 3]
```

---

## 5.4 Anonymous records

```liminal
address: {
  city: "London"
  country: "UK"
}
```

Anonymous records are allowed in value position, but named typed constructors are preferred when the value has semantic importance.

---

## 5.5 Block content literals

Use `@{ ... }` for block markup as a value.

```liminal
bio: @{
  Ada Lovelace worked on Babbage's Analytical Engine.

  This is a second paragraph.
}
```

The content inside is parsed as normal block markup. The closing `}` must appear alone at the matching indentation level.

---

## 5.6 Structured grammar sketch

```ebnf
Document       ::= Block*

Block          ::= Paragraph
                 | Heading
                 | List
                 | Quote
                 | CodeFence
                 | MathFence
                 | TypedBlock
                 | Directive
                 | Table
                 | HtmlBlock

TypedBlock     ::= FenceOpen QName Anchor? Fields? Newline
                   Block*
                   FenceClose

FenceOpen      ::= ColonRun QName
FenceClose     ::= SameColonRun
ColonRun       ::= ":::" ":"*

TypedInline    ::= "@" QName Anchor? Fields? InlineContent?
TypedValue     ::= "@" QName Anchor? Fields?

Anchor         ::= "#" Ident

Fields         ::= "{" FieldList? "}"
FieldList      ::= Field (FieldSep Field)* FieldSep?
Field          ::= FieldName ":" Value
FieldSep       ::= "," | Newline

Value          ::= Scalar
                 | Symbol
                 | Ref
                 | Embed
                 | List
                 | Record
                 | TypedValue
                 | InlineLiteral
                 | BlockLiteral

InlineLiteral  ::= "@[" Inline* "]"
BlockLiteral   ::= "@{" Block* "}"

List           ::= "[" ValueList? "]"
Record         ::= "{" FieldList? "}"

Ref            ::= "&" RefTarget
Embed          ::= "!" TypeExpectation? Label? "(" Target ")"

TypeExpectation ::= "{" QName "}"
Label           ::= "[" Inline* "]"
```

---

# 6. Schema syntax

Schemas live in explicit schema blocks.

```liminal
:::schema
type Person : value = {
  name: str
  born?: date
  url?: uri
  bio?: blocks
}

type Callout : block = {
  kind: enum { note, warning, error }
  title?: inline
  body: blocks @content
}

type Badge : inline = {
  status: enum { success, warning, error }
  body: inline @content
}
:::
```

The important distinction is `: value`, `: inline`, and `: block`.

```text
value  = structured data, not directly rendered as inline/block content
inline = may appear inside inline content
block  = may appear where blocks are allowed
```

A field marked `@content` receives the constructor’s bracket or fenced body.

```liminal
@Badge{status: success}[passing]
```

maps to:

```liminal
@Badge{
  status: success
  body: @[passing]
}
```

And:

```liminal
:::Callout{kind: warning}
Body here.
:::
```

maps to:

```liminal
@Callout{
  kind: warning
  body: @{
    Body here.
  }
}
```

---

## 6.1 Type expressions

Recommended schema type expressions:

```text
str
bool
int
num
decimal
date
time
datetime
uri
id
inline
blocks
T?
[T]
map<T>
ref<T>
embed<T>
enum { a, b, c }
{ field: T, optional?: T }
variant by field { caseA: {...}, caseB: {...} }
```

Examples:

```liminal
type BibliographyEntry : value =
  variant by kind {
    book: {
      title: str
      author: [str]
      isbn?: str
    }

    article: {
      title: str
      author: [str]
      doi?: str
    }
  }
```

Unions should be **discriminated only**. Avoid arbitrary unions like:

```liminal
str | int | { name: str }
```

because they make validation and bidirectional printing less predictable.

---

## 6.2 Schema modifiers

Schema modifiers are allowed because they live in the schema, not scattered through content.

```liminal
@content
@default(value)
@surface(name)
@readonly
@deprecated("message")
```

Example:

```liminal
type Table : block = {
  columns: [Column]
  rows: [Row]
  caption?: inline
} @surface(pipe-table)
```

The modifier says that `Table` may have a custom pipe-table surface form, but its real semantic shape remains the declared record.

---

# 7. Imports, references, and embeds

## 7.1 Imports

Line directives use `::`.

```liminal
::use type "./schema.lim" as schema
::use data "./people.lim" as people
::use "./bibliography.lim" only { Entry, Citation }
```

Imports do not change the base parse. They only affect schema resolution and reference resolution.

Qualified types:

```liminal
@schema.Person{name: "Ada"}
```

---

## 7.2 IDs

Any typed constructor may have an ID.

```liminal
@Person#ada{
  name: "Ada Lovelace"
}
```

Block form:

```liminal
:::Figure#engine-diagram{caption: @[Analytical Engine]}
!{Image}[diagram](engine.png)
:::
```

IDs are not arbitrary annotations. They are part of the typed node identity system.

---

## 7.3 References

Local reference:

```liminal
&ada
```

Imported reference:

```liminal
&people.ada
```

External reference:

```liminal
&<./people.lim#ada>
```

A reference is a value. It does not render by itself unless used in a rendering context.

---

## 7.4 Embeds

Embeds are typed links to structured content.

```liminal
!{Person}[Ada Lovelace](#ada)
```

Shape:

```text
Embed {
  expected: Person
  fallback: Inline("Ada Lovelace")
  target: "#ada"
}
```

External structured embed:

```liminal
!{BibliographyEntry}[Knuth 1984](./refs.lim#knuth84)
```

Image syntax is a shorthand:

```markdown
![alt](image.png)
```

for:

```liminal
!{Image}[alt](image.png)
```

This generalizes Markdown image embedding without making images special in the semantic model.

---

# 8. Templates

Templates are typed functions from structured values to inline or block content.

```liminal
:::template PersonCard(person: Person) -> blocks
:::Card{title: @[${person.name}]}
Born: ${person.born}

${person.bio}
:::
:::
```

A template declaration has:

```text
name
typed parameters
result kind: value | inline | blocks
body
```

Template calls use normal typed constructor syntax when possible.

```liminal
@PersonCard{person: &ada}
```

If the result is block-level, it can also be embedded:

```liminal
!{PersonCard}[Ada](#ada)
```

---

## 8.1 Template control structures

Keep them structural, not free-form string directives.

```liminal
:::if{test: person.bio}
${person.bio}
:::
```

```liminal
:::for{item: link, in: person.links}
- [${link.label}](${link.href})
:::
```

These lower to typed template nodes:

```text
TemplateIf {
  test: Expr
  body: Blocks
}

TemplateFor {
  item: Ident
  in: Expr
  body: Blocks
}
```

No arbitrary code execution. Expressions are pure projections over typed data.

---

# 9. Tables as typed structures

Pipe-table syntax may exist as a surface reader:

```markdown
| Name | Born |
| ---- | ---: |
| Ada Lovelace | 1815 |
| Alan Turing | 1912 |
```

But the semantic form is:

```liminal
@Table{
  columns: [
    { label: @[Name], align: left }
    { label: @[Born], align: right }
  ]

  rows: [
    [@[Ada Lovelace], @[1815]]
    [@[Alan Turing], @[1912]]
  ]
}
```

The table reader/printer must satisfy:

```text
read_pipe_table(write_pipe_table(table)) == table
```

If a table cannot be represented cleanly in pipe-table form, the printer falls back to generic typed syntax.

This is the general rule for all custom syntaxes.

---

# 10. Surface readers and printers

A surface syntax is a pair:

```text
Reader:  SourceText -> Node<T>
Printer: Node<T> -> SourceText
```

The schema may declare that a type supports a surface:

```liminal
type Table : block = {
  columns: [Column]
  rows: [Row]
  caption?: inline
} @surface(pipe-table)
```

But the actual parser support is supplied by the implementation.

Surface readers must obey these rules:

```text
1. They declare the exact type they produce.
2. They cannot change global block-boundary rules.
3. They cannot make schema-dependent tokenization decisions.
4. They must have a generic typed fallback.
5. They must preserve source spans for bidirectional editing.
6. They must either be lossless or explicitly mark what normalization they perform.
```

Examples of core surface readers:

```text
heading-line     -> Heading
markdown-link    -> Link
markdown-image   -> Image embed
pipe-table       -> Table
math-fence       -> Math
code-fence       -> CodeBlock
```

Examples of optional extension surfaces:

```text
mermaid-fence    -> Diagram{language: mermaid}
csv-table        -> Table
bibtex-entry     -> BibliographyEntry
```

But none of these are semantically privileged.

---

# 11. Bidirectional parsing and printing

The language should support two printing modes.

## 11.1 Lossless print

If a node has not been structurally edited, preserve its original source exactly:

```text
parse(source).print_lossless() == source
```

This requires the CST to retain:

```text
comments
whitespace
field ordering
quote style
delimiter choice
surface form
source spans
unresolved text
```

## 11.2 Canonical print

If a node has been structurally edited, print it using the preferred available surface. If no safe custom printer exists, print generic typed syntax.

```liminal
@Person#ada{
  name: "Ada Lovelace"
  born: 1815-12-10
}
```

Canonical field ordering should be schema-defined:

```liminal
type Person : value = {
  name: str
  born?: date
  url?: uri
  bio?: blocks
}
```

So canonical print orders fields as:

```text
name
born
url
bio
```

not alphabetically unless the schema requests that.

---

## 11.3 Round-trip laws

For a valid document:

```text
parse(print(ast)) == ast
```

For arbitrary source:

```text
print_lossless(parse(source)) == source
```

For normalized source:

```text
print_canonical(parse(source)) == normalize(source)
```

For custom surfaces:

```text
read_surface(write_surface(node)) == node
```

If the printer cannot satisfy that law, it must use generic syntax instead.

---

# 12. Error recovery

The base parser should produce useful nodes even for incomplete input.

Unclosed typed block:

```liminal
:::Callout{kind: warning}
Still typing...
```

Parse as:

```text
ErrorBlock {
  opener: Callout
  body: parsed blocks until EOF
  diagnostic: missing closing fence
}
```

Unknown type:

```liminal
@DoesNotExist{foo: 1}
```

Parse as:

```text
TypedValue {
  type: DoesNotExist
  fields: { foo: 1 }
  diagnostic: unresolved type, emitted by schema pass
}
```

Malformed field:

```liminal
@Person{
  name "Ada"
}
```

Parse as an error field, but keep surrounding structure.

This matters for structure-aware editing: the editor should still understand that the user is inside a `Person` value.

---

# 13. A complete example

```liminal
::use type "./bibliography.lim" as bib
::use data "./people.lim" as people

:::schema
type Person : value = {
  name: str
  born?: date
  url?: uri
  bio?: blocks
}

type Callout : block = {
  kind: enum { note, warning, error }
  title?: inline
  body: blocks @content
}

type Citation : inline = {
  target: ref<bib.Entry>
  label: inline @content
}

type PersonCard : block = template(person: Person) -> blocks
:::

@Person#ada{
  name: "Ada Lovelace"
  born: 1815-12-10
  url: https://example.org/ada
  bio: @{
    Ada Lovelace wrote notes on the Analytical Engine.

    Those notes are often discussed in histories of computing.
  }
}

# Typed documents

:::Callout{kind: warning, title: @[Draft feature]}
The `@surface` mechanism is intentionally separate from the schema's
structural type definition.
:::

See @Citation{target: &bib.knuth84}[Knuth 1984].

!{Person}[Ada Lovelace](#ada)

| Name | Born |
| ---- | ---: |
| Ada Lovelace | 1815 |
| Alan Turing | 1912 |
```

The document contains ordinary markup, custom records, a custom block type, a typed inline citation, a structured embed, and a table. Semantically, all of them are typed nodes.

---

# 14. Recommended prelude types

The core language should ship with a prelude schema roughly like this:

```liminal
:::schema prelude
type Document : value = {
  blocks: blocks
}

type Paragraph : block = {
  body: inline @content
}

type Heading : block = {
  level: int
  body: inline @content
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

type CodeSpan : inline = {
  text: str
}

type CodeBlock : block = {
  language?: str
  text: str
}

type Math : inline = {
  display: bool
  tex: str
}

type Html : inline = {
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
:::
```

This prelude makes the important conceptual move explicit: even “basic Markdown” is just typed structure with convenient surface syntax.

---

# 15. The most important design constraints

The spec should probably treat these as nonnegotiable:

```text
1. Generic typed syntax must be complete enough to represent every semantic node.
2. Custom syntaxes must lower into declared types.
3. The base parser must not require schema knowledge.
4. Schema validation must not change tokenization.
5. All multiline custom content must be explicitly delimited.
6. There must be no global arbitrary attribute syntax.
7. Every typed node may carry identity, but identity is part of the constructor, not an annotation.
8. The printer must be allowed to fall back to generic typed syntax.
9. Templates must be typed and pure.
10. Extension authors may add types first, surfaces second.
```

---

# 16. Open design choices

The biggest unresolved choices are:

| Choice | Recommendation |
|---|---|
| Should `$...$` inline math be allowed? | Probably no in the core grammar. Use `@Math[...]` and optional `\(...\)`. |
| Should unquoted scalars be broad or narrow? | Broad lexically, schema-resolved semantically. |
| Should custom schemas define new syntax directly? | No. Schemas define types. Implementations may register surface readers/printers for those types. |
| Should field order matter? | Source order is preserved; canonical order follows schema order. |
| Should IDs be allowed on shorthand headings? | Prefer long typed form for explicit IDs to avoid general annotations. |
| Should HTML be parsed deeply? | Not in the base parser. Treat it as raw typed content unless an HTML surface parser is explicitly enabled. |

The central syntax shape I would keep is:

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

That gives the language a small, regular, human-readable foundation while still leaving room for Markdown-like convenience syntax, math, tables, HTML, structured data, imports, templates, and bidirectional typed editing.
