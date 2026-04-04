# Keybindings

This editor currently supports a focused subset of Vim-style modal navigation.
The list below describes the behaviors that are available today.

## Modes

- `Normal mode`: navigation mode. Keys move the cursor instead of inserting text.
- `Insert mode`: typing inserts text normally.

## Mode Switching

| Key | Behavior |
| --- | --- |
| `i` | Enter Insert mode at the current cursor position. |
| `a` | Enter Insert mode after the current character. On an empty or blank line, this behaves like inserting at the current line position. |
| `I` | Enter Insert mode at the first non-blank character of the current line. |
| `A` | Enter Insert mode at the end of the current line. |
| `o` | Open a new line below the current line and enter Insert mode there. |
| `O` | Open a new line above the current line and enter Insert mode there. |
| `Esc` | Return to Normal mode. If the cursor is sitting on a newline, it moves back one character first, matching Vim's usual normal-mode cursor behavior. |

## Counts

- Most Normal-mode motions accept a numeric count prefix.
- Counts start with `1`-`9`.
- `0` by itself is a motion, not a count prefix.
- After a count has started, `0` can be used inside the number.

Examples:

- `3j`: move down 3 lines.
- `2w`: move forward 2 words.
- `10G`: go to line 10.

## Normal Mode Navigation

### Basic Cursor Movement

| Key | Behavior |
| --- | --- |
| `h` | Move left. |
| `j` | Move down one logical line. |
| `k` | Move up one logical line. |
| `l` | Move right. |
| `Left Arrow` | Move left. |
| `Down Arrow` | Move down one logical line. |
| `Up Arrow` | Move up one logical line. |
| `Right Arrow` | Move right. |

### Line Anchors

| Key | Behavior |
| --- | --- |
| `0` | Move to the start of the current logical line. |
| `^` | Move to the first non-blank character on the current logical line. |
| `$` | Move to the end of the current logical line. |

`$` accepts a count. For example, `3$` moves to the end of the line 2 lines below the current one.

### Word and File Movement

| Key | Behavior |
| --- | --- |
| `w` | Move to the start of the next word. |
| `b` | Move to the start of the previous word. |
| `e` | Move to the end of the current word, or the end of the next word if already at a word end. |
| `gg` | Move to the first non-blank character of the first line. |
| `G` | Move to the first non-blank character of the last line. |
| `[count]gg` | Move to the first non-blank character of line `[count]`. |
| `[count]G` | Move to the first non-blank character of line `[count]`. |

### In-Line Character Search

These motions search only within the current logical line.

| Key | Behavior |
| --- | --- |
| `f<char>` | Move forward to the next occurrence of `<char>`. |
| `F<char>` | Move backward to the previous occurrence of `<char>`. |
| `t<char>` | Move forward until just before the next occurrence of `<char>`. |
| `T<char>` | Move backward until just after the previous occurrence of `<char>`. |
| `;` | Repeat the last `f`, `F`, `t`, or `T` search in the same direction. |
| `,` | Repeat the last `f`, `F`, `t`, or `T` search in the opposite direction. |

Examples:

- `fa`: jump forward to `a` on the current line.
- `tb`: jump forward to just before `b`.
- `2fx`: jump to the second next `x` on the current line.

### View-Relative Movement

These motions are based on the current viewport rather than only on document lines.

| Key | Behavior |
| --- | --- |
| `H` | Move to the first non-blank character of the top visible line. |
| `M` | Move to the first non-blank character of the middle visible line. Counts are ignored. |
| `L` | Move to the first non-blank character of the bottom visible line. |
| `Ctrl-U` | Move up by half a page. With a count, move up by that many screen lines. |
| `Ctrl-D` | Move down by half a page. With a count, move down by that many screen lines. |
| `Ctrl-B` | Move up by one full page. With a count, move up by that many full pages. |
| `Ctrl-F` | Move down by one full page. With a count, move down by that many full pages. |

`H` and `L` accept counts. For example, `3H` moves to the third visible line from the top, and `2L` moves to the second visible line from the bottom.

### Wrapped-Line Movement

These motions operate on screen lines created by soft wrapping, not on logical document lines.

| Key | Behavior |
| --- | --- |
| `gj` | Move down one screen line. |
| `gk` | Move up one screen line. |
| `g0` | Move to the start of the current screen line. |
| `g^` | Move to the first non-blank character of the current screen line. |
| `g$` | Move to the end of the current screen line. |

`g0`, `g^`, and `g$` accept counts. For example, `3g$` moves to the end of the screen line 2 screen lines below the current one.

### Paragraph Movement

| Key | Behavior |
| --- | --- |
| `{` | Move backward to the start of the previous paragraph. |
| `}` | Move forward to the start of the next paragraph. |

## Normal Mode Deletion

Delete now uses Vim's `d` operator model over the currently supported motion subset. Counts can be used before the command, such as `2dd` or `3dw`.
Successful deletes also write the removed text to the system clipboard. Linewise deletes preserve linewise paste behavior when pasted back inside this editor.

Standalone delete aliases:

| Key | Behavior |
| --- | --- |
| `D` | Delete to the end of the line. Equivalent to `d$`. |

### Linewise Delete

| Key | Behavior |
| --- | --- |
| `dd` | Delete the current line. |
| `d` + `j` | Delete the current line and the line below it. |
| `d` + `k` | Delete the current line and the line above it. |
| `d` + `gg` | Delete from the current line to the start of the document. |
| `d` + `G` | Delete from the current line to the end of the document. |
| `d` + `{` | Delete backward by paragraph. |
| `d` + `}` | Delete forward by paragraph. |

### Characterwise Delete

| Key | Behavior |
| --- | --- |
| `d` + `h` | Delete characters to the left. |
| `d` + `l` | Delete characters at and to the right of the cursor. |
| `d` + `0` | Delete back to the start of the line. |
| `d` + `^` | Delete back to the first non-blank character of the line. |
| `d` + `$` | Delete to the end of the line. |
| `d` + `w` | Delete forward by word. |
| `d` + `b` | Delete backward by word. |
| `d` + `e` | Delete to the end of the current or next word. |
| `d` + `f<char>` | Delete forward through the next occurrence of `<char>` on the current line. |
| `d` + `F<char>` | Delete backward through the previous occurrence of `<char>` on the current line. |
| `d` + `t<char>` | Delete forward until just before the next occurrence of `<char>` on the current line. |
| `d` + `T<char>` | Delete backward until just after the previous occurrence of `<char>` on the current line. |
| `d` + `;` | Repeat the last `df`, `dF`, `dt`, or `dT` search in the same direction. |
| `d` + `,` | Repeat the last `df`, `dF`, `dt`, or `dT` search in the opposite direction. |

## Normal Mode Paste

Paste uses the current system clipboard contents.

| Key | Behavior |
| --- | --- |
| `p` | Paste after the cursor. If the clipboard content came from a linewise delete in this editor, paste it below the current line. |
| `P` | Paste before the cursor. If the clipboard content came from a linewise delete in this editor, paste it above the current line. |

Counts repeat the paste. For example, `3p` pastes the current clipboard contents three times.

## Not Yet Supported

This is not full Vim yet. Some important Vim features are intentionally still out of scope for now:

- `/`, `?`, `n`, `N`, `*`, `#`
- marks and register-based jumps
- change and yank operators
- named registers and advanced put variants like `gp`, `gP`, `[p`, and `]p`
- Visual mode
- command-line mode and Ex commands
