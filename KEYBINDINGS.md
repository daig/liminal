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
| `v` | Enter characterwise Visual mode starting at the current cursor position. |
| `V` | Enter linewise Visual mode starting at the current line. |
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

## Command Hints

- After a short delay, Normal mode shows a bottom-of-editor hint panel for pending prefixes such as `d`, `c`, `y`, `g`, `f`, and `t`.
- The hint panel is generated directly from the currently registered command bindings, so it always matches the actual supported commands.
- `Space` in idle Normal mode opens the top-level command catalog immediately.
- `Esc` closes the hint panel when it is open and there is no active pending command.

## Mouse

- In Normal mode, clicking a character moves the cursor to that position.
- In Visual mode, clicking a character extends or shrinks the current selection to that position. In linewise Visual mode, the selection still expands and contracts in whole-line units.
- If an operator is pending, such as after `d`, `c`, or `y`, clicking a character uses that clicked position as the motion target for the operator.
- Operator-pending mouse motions are characterwise and span from the starting cursor position through the clicked position.

## Visual Mode

This editor currently supports characterwise Visual mode and linewise Visual mode. Blockwise Visual mode, text objects, and most of Vim's visual-only command variants are not implemented yet.

### Selection Movement

- In Visual mode, the supported motion keys reuse the same movement subset as Normal mode and extend or shrink the active selection.
- This includes basic movement, line anchors, word motions, `gg` / `G`, in-line character search, view-relative movement, wrapped-line movement, paragraph movement, and character clicks with the mouse.
- In linewise Visual mode, the selected range always expands or contracts by whole lines, regardless of the motion used to move the cursor within the selection.

### Visual Actions

| Key | Behavior |
| --- | --- |
| `v` | Leave characterwise Visual mode and return to Normal mode. In linewise Visual mode, switch to characterwise Visual mode. |
| `V` | Leave linewise Visual mode and return to Normal mode. In characterwise Visual mode, switch to linewise Visual mode. |
| `Esc` | Leave Visual mode and return to Normal mode. |
| `d` | Delete the current selection, copy it to the system clipboard, and return to Normal mode. |
| `x` | Delete the current selection and return to Normal mode. |
| `c` | Change the current selection, copy the removed text to the system clipboard, and enter Insert mode. |
| `s` | Equivalent to `c` for the current selection. |
| `y` | Yank the current selection to the system clipboard and return to Normal mode. |
| `p` | Replace the current selection with the current system clipboard contents and return to Normal mode. |
| `P` | Same as `p` in the current Visual-mode implementation. |

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
| `x` | Delete the character under the cursor. With a count, delete that many characters to the right. |
| `X` | Delete the character before the cursor. With a count, delete that many characters to the left. |
| `Forward Delete` | Equivalent to `x` when your keyboard provides it. |

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
| `p` | Paste after the cursor. If the clipboard content came from a linewise delete, yank, or change in this editor, paste it below the current line. |
| `P` | Paste before the cursor. If the clipboard content came from a linewise delete, yank, or change in this editor, paste it above the current line. |

Counts repeat the paste. For example, `3p` pastes the current clipboard contents three times.

## Undo Tree

Undo history is stored per note for the current app session. Normal-mode edit commands like delete, change, and paste each create one undo step. An uninterrupted Insert-mode session also undoes as one step.

| Key | Behavior |
| --- | --- |
| `u` | Undo the most recent change. With a count, undo that many changes. |
| `Ctrl-R` | Redo along the currently active undo branch. With a count, redo that many changes. |

## Normal Mode Yank

Yank uses Vim's `y` operator model over the same currently supported motion subset as delete. Successful yanks write the selected text to the system clipboard but do not modify the document or move the cursor.

Standalone yank aliases:

| Key | Behavior |
| --- | --- |
| `Y` | Yank the current line. Equivalent to `yy`. With a count, yank that many lines starting at the current line. |

### Linewise Yank

| Key | Behavior |
| --- | --- |
| `yy` | Yank the current line. |
| `y` + `j` | Yank the current line and the line below it. |
| `y` + `k` | Yank the current line and the line above it. |
| `y` + `gg` | Yank from the current line to the start of the document. |
| `y` + `G` | Yank from the current line to the end of the document. |
| `y` + `{` | Yank backward by paragraph. |
| `y` + `}` | Yank forward by paragraph. |

### Characterwise Yank

| Key | Behavior |
| --- | --- |
| `y` + `h` | Yank characters to the left. |
| `y` + `l` | Yank characters at and to the right of the cursor. |
| `y` + `0` | Yank back to the start of the line. |
| `y` + `^` | Yank back to the first non-blank character of the line. |
| `y` + `$` | Yank to the end of the line. |
| `y` + `w` | Yank forward by word. |
| `y` + `b` | Yank backward by word. |
| `y` + `e` | Yank to the end of the current or next word. |
| `y` + `f<char>` | Yank forward through the next occurrence of `<char>` on the current line. |
| `y` + `F<char>` | Yank backward through the previous occurrence of `<char>` on the current line. |
| `y` + `t<char>` | Yank forward until just before the next occurrence of `<char>` on the current line. |
| `y` + `T<char>` | Yank backward until just after the previous occurrence of `<char>` on the current line. |
| `y` + `;` | Repeat the last `yf`, `yF`, `yt`, or `yT` search in the same direction. |
| `y` + `,` | Repeat the last `yf`, `yF`, `yt`, or `yT` search in the opposite direction. |

## Normal Mode Change

Change uses Vim's `c` operator model over the same currently supported motion subset as delete. Successful changes write the removed text to the system clipboard, replace the selected text, and enter Insert mode at the start of the changed range.
Unlike stock Vim, this editor handles `c` with the same literal motion semantics as `d` and `y`, so `cw` follows the actual `w` motion instead of using Vim's historical `cw` special case.

Standalone change aliases:

| Key | Behavior |
| --- | --- |
| `C` | Change to the end of the line. Equivalent to `c$`. |
| `s` | Change the character under the cursor. With a count, change that many characters to the right. Equivalent to `cl`. |
| `S` | Change the current line. With a count, change that many lines starting at the current line. Equivalent to `cc`. |

### Linewise Change

| Key | Behavior |
| --- | --- |
| `cc` | Change the current line and enter Insert mode. |
| `c` + `j` | Change the current line and the line below it, then enter Insert mode. |
| `c` + `k` | Change the current line and the line above it, then enter Insert mode. |
| `c` + `gg` | Change from the current line to the start of the document, then enter Insert mode. |
| `c` + `G` | Change from the current line to the end of the document, then enter Insert mode. |
| `c` + `{` | Change backward by paragraph, then enter Insert mode. |
| `c` + `}` | Change forward by paragraph, then enter Insert mode. |

### Characterwise Change

| Key | Behavior |
| --- | --- |
| `c` + `h` | Change characters to the left. |
| `c` + `l` | Change characters at and to the right of the cursor. |
| `c` + `0` | Change back to the start of the line. |
| `c` + `^` | Change back to the first non-blank character of the line. |
| `c` + `$` | Change to the end of the line. |
| `c` + `w` | Change forward by word. This follows the same `w` motion semantics used by `d` and `y`. |
| `c` + `b` | Change backward by word. |
| `c` + `e` | Change to the end of the current or next word. |
| `c` + `f<char>` | Change forward through the next occurrence of `<char>` on the current line. |
| `c` + `F<char>` | Change backward through the previous occurrence of `<char>` on the current line. |
| `c` + `t<char>` | Change forward until just before the next occurrence of `<char>` on the current line. |
| `c` + `T<char>` | Change backward until just after the previous occurrence of `<char>` on the current line. |
| `c` + `;` | Repeat the last `cf`, `cF`, `ct`, or `cT` search in the same direction. |
| `c` + `,` | Repeat the last `cf`, `cF`, `ct`, or `cT` search in the opposite direction. |

## Not Yet Supported

This is not full Vim yet. Some important Vim features are intentionally still out of scope for now:

- `/`, `?`, `n`, `N`, `*`, `#`
- marks and register-based jumps
- named registers and advanced put variants like `gp`, `gP`, `[p`, and `]p`
- advanced undo-tree navigation like `g-` and `g+`
- Visual mode
- command-line mode and Ex commands
