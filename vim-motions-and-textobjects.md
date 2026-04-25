# Vim Motions, Text Objects, and Operators

Derived from `vim-default-keybinding-spec.md` (Vim 9.1).

## Table 1: Motion Argument Constructs

Motions define a range from the cursor's current position to a destination. All can follow an operator.

| Category | Motions | Linewise? | Notes |
|---|---|---|---|
| **Left/right char** | `h` `l` `<Space>` `<BS>` | no | |
| **Find on line** | `f{char}` `F{char}` `t{char}` `T{char}` | no | inclusive (`f`/`F`) or exclusive (`t`/`T`) |
| **Repeat find** | `;` `,` | no | repeat/reverse last `f`/`t`/`F`/`T` |
| **Line position** | `0` `^` `$` `g_` `\|` | no | `\|` = go to column N |
| **Screen line pos** | `g0` `g^` `g$` `gm` `gM` | no | wrap-aware variants |
| **Word** | `w` `W` `b` `B` `e` `E` | no | `w`/`b`/`e` = word; `W`/`B`/`E` = WORD |
| **Word end back** | `ge` `gE` | no | backward to end of prev word/WORD |
| **Up/down line** | `j` `k` `+` `-` `<CR>` `_` | yes | `+`/`<CR>`/`_` go to first non-blank |
| **Screen line** | `gj` `gk` | yes | wrap-aware up/down |
| **Jump to line** | `G` `gg` `H` `M` `L` | yes | `H`/`M`/`L` = screen-relative |
| **Sentence** | `(` `)` | no | N sentences back/forward |
| **Paragraph** | `{` `}` | no | N paragraphs back/forward |
| **Section** | `[[` `]]` `[]` `][` | often | exclusive motions; after operators they often become exclusive-linewise |
| **Search** | `/{pat}` `?{pat}` `n` `N` | no | offset can make linewise |
| **Word search** | `*` `#` `g*` `g#` | no | `g` variants: no `\<\>` word bounds |
| **Search & select** | `gn` `gN` | no | visually select next/prev match |
| **Match bracket** | `%` | no | without count: find matching pair; with count: go to N% of file |
| **Marks (backtick)** | `` `{a-zA-Z0-9} `` `` `` `` `` `[ `` `` `] `` `` `< `` `` `> `` `` `( `` `` `) `` `` `{ `` `` `} `` | no | exact position |
| **Marks (quote)** | `'{mark}` `''` `'[` `']` `'<` `'>` `'(` `')` `'{` `'}` | yes | first non-blank on mark's line |
| **Byte offset** | `go` | no | go to byte N |
| **Changelist** | `g;` `g,` | no | older/newer change position |
| **Bracket cmds** | `[(` `[{` `])` `]}` `[#` `]#` `[/` `]/` `[m` `]m` `[c` `]c` `[s` `]s` `[z` `]z` | no | unmatched-bracket, comment, method, diff, spell, fold navigation |
| **Fold** | `zj` `zk` | yes | next/prev fold |

Arrow keys, `<Home>`, `<End>`, `<C-Left>`, `<C-Right>`, etc. are aliases for the above (e.g., `<Left>`=`h`, `<End>`=`$`). Omitted for brevity.

**Operator-pending modifiers** (not motions, but modify how a motion is interpreted):

| Modifier | Effect |
|---|---|
| `v` | Force characterwise |
| `V` | Force linewise |
| `CTRL-V` | Force blockwise |

## Table 2: Text Object Constructs

Text objects select a region *around* the cursor. Only valid after an operator or in Visual mode. Counts work (`2aw`, `3ip`). `a`/`i` are **not** a universal include/exclude toggle:

- For non-block objects (`w` `W` `s` `p` `t` quotes), `a` selects the object plus adjacent whitespace. Vim prefers trailing whitespace, but if none exists, or the cursor starts in leading whitespace, it uses leading whitespace instead.
- For those same non-block objects, `i` selects the object itself; if the cursor is on whitespace, the whitespace is selected instead.
- For block objects (`()` `{}` `[]` `<>`), `a` includes delimiters and `i` excludes them.

| Object | `a` form | `i` form | What it selects |
|---|---|---|---|
| **word** | `aw` | `iw` | [count] word(s); `a` includes adjacent whitespace, `i` treats inter-word whitespace as part of the count |
| **WORD** | `aW` | `iW` | [count] WORD(s); same as word objects, but WORD = any run of non-blank chars |
| **sentence** | `as` | `is` | [count] sentence(s); characterwise in Visual mode |
| **paragraph** | `ap` | `ip` | [count] paragraph(s); blank/whitespace-only lines are boundaries; linewise in Visual mode |
| **`()` block** | `ab` `a(` `a)` | `ib` `i(` `i)` | [count] parenthesized block; `a` includes parens but not outer whitespace, `i` excludes parens and errors on empty `()` |
| **`{}` block** | `aB` `a{` `a}` | `iB` `i{` `i}` | [count] brace block; `a` includes braces, `i` excludes braces and errors on empty `{}` |
| **`[]` block** | `a[` `a]` | `i[` `i]` | [count] bracket block; `a` includes brackets, `i` excludes brackets and errors on empty `[]` |
| **`<>` block** | `a<` `a>` | `i<` `i>` | [count] angle-bracket block; `a` includes angles, `i` excludes them and errors on empty `<>` |
| **tag block** | `at` | `it` | [count] matching `<tag>...</tag>` block; `a` includes tags, `i` excludes them |
| **double quote** | `a"` | `i"` | one-line double-quoted string; `a` includes quotes plus adjacent whitespace, `i` excludes quotes |
| **single quote** | `a'` | `i'` | one-line single-quoted string; `a` includes quotes plus adjacent whitespace, `i` excludes quotes |
| **backtick** | `` a` `` | `` i` `` | one-line backtick string; `a` includes backticks plus adjacent whitespace, `i` excludes backticks |

**Text object notes**

- Quote objects (`a"`/`i"`, `a'`/`i'`, `` a` ``/`` i` ``) only work within one line. Repeating the `a` forms in Visual mode extends to another quoted string; repeating the `i` forms does not.
- `2i"`/`2i'`/`` 2i` `` are special: they include the quotes but not the extra whitespace that the `a` forms would include. Other counts on quote objects are effectively unused.
- Tag objects (`at`/`it`) are only available when Vim is compiled with `+eval`. Matching is HTML/XML-ish: case is ignored, self-closing tags are skipped, and stray end tags are tolerated.
- Repeating `it` can include the tags on the next expansion; `it` on an empty tag block selects the start tag.
- Most text objects become characterwise in Visual mode. `ap`/`ip` become linewise, and `aw`/`iw`/`aW`/`iW` switch Visual-line mode back to characterwise.

## Table 3: Operators (Commands That Take Motion or Text Object Arguments)

All operators below accept **both** motions and text objects unless noted.

| Operator | Doubled form | Action | Quirks / Notes |
|---|---|---|---|
| `d` | `dd` | delete | Linewise motions (`j`, `G`, etc.) delete whole lines. |
| `c` | `cc` | change (delete + insert) | **`cw`/`cW` act like `ce`/`cE`** -- they don't include trailing whitespace. This is Vim's most famous motion-operator quirk, inherited from Vi. Does not apply to text objects (`ciw` is normal). |
| `y` | `yy` | yank | Cursor stays at start of yanked area (unlike `d`/`c`). |
| `>` | `>>` | shift right | Always operates linewise regardless of motion type. Text objects work but are coerced to full lines. |
| `<` | `<<` | shift left | Same as `>`: always linewise. |
| `=` | `==` | auto-indent | Always linewise. Uses `equalprg` or internal indenter. |
| `!` | `!!` | filter through external cmd | Always linewise. After the motion, prompts for a shell command. |
| `gq` | `gqq` (via `gqgq`) | format text | Always linewise. Moves cursor to end of formatted text. |
| `gw` | `gww` (via `gwgw`) | format text | Always linewise. **Keeps cursor position** (unlike `gq`). |
| `gu` | `guu` (via `gugu`) | lowercase | Works char/linewise per motion. |
| `gU` | `gUU` (via `gUgU`) | uppercase | Works char/linewise per motion. |
| `g~` | `g~~` (via `g~g~`) | swap case | Works char/linewise per motion. |
| `g?` | `g??` (via `g?g?`) | ROT13 encode | Works char/linewise per motion. |
| `g@` | -- | call `operatorfunc` | User-defined; behavior depends on the function. |
| `zf` | `zF` (N lines) | create fold | `zf` takes a motion/text-obj; `zF` takes a count of lines instead. |
| `~` | -- | swap case | **Only an operator when `tildeop` is set.** Without it, `~` is a standalone command that swaps N chars and advances. |

### Key interaction patterns

- **Doubled form** (`dd`, `cc`, `>>`, etc.): operates on N whole lines, bypassing the need for a motion/text-object argument entirely.
- **Linewise coercion**: `>`, `<`, `=`, `!`, `gq`, `gw` always operate on whole lines even with characterwise motions or text objects. So `>iw` and `>ap` both shift entire lines.
- **`c` + word motion quirk**: `cw` stops at end of word (like `ce`), not at the start of the next word. This **only** affects `w`/`W` after `c`. All other operators treat `w` normally. With text objects (`ciw`, `caw`) there's no anomaly.
- **Visual mode**: operators act on the visual selection directly -- they don't take a motion/text-object argument. The selection itself already defines the range. Text objects in Visual mode *extend* the selection.
- **`v`/`V`/`CTRL-V` in operator-pending**: force the type of any subsequent motion. E.g., `dVf.` deletes the full lines covered by `f.` instead of just the characters.
