# Which-Key Hint Overlay — Behavioral Specification

Specification derived from reading the [which-key.nvim](https://github.com/folke/which-key.nvim) v3.17.0 source code directly. Intended as the foundation for implementing a similar feature in a custom mode-based (vim-like) text editor.

---

## 1. Core Concept

Which-key is a **key sequence disambiguator with a visual hint overlay**. When the user begins a multi-key command in normal mode (or any non-insert mode), which-key intercepts the input loop, takes over character-by-character, and shows a popup listing all possible continuations from the current prefix. The popup lets the user discover commands they've forgotten, while expert users who type fast enough never see it.

The system has three responsibilities:
1. **Detect** that a key prefix has been pressed that could lead to multiple commands.
2. **Show** a floating panel listing all valid continuations from that prefix.
3. **Resolve** the sequence — either the user completes it (execute the command), presses `<Esc>` (cancel), or presses `<BS>` (go back one level).

---

## 2. Data Model

### 2.1 Keybinding Tree (Trie)

All keybindings are stored in a **trie** (prefix tree). Each node represents one key in a key sequence.

```
root
├── d        → (operator: Delete)
│   ├── d    → "Delete line"
│   ├── w    → "Delete word"
│   ├── i    → (group: "inside")
│   │   ├── w → "Delete inner word"
│   │   ├── ( → "Delete inner parens"
│   │   └── ...
│   └── a    → (group: "around")
│       └── ...
├── g        → (group)
│   ├── g    → "Go to first line"
│   ├── d    → "Go to definition"
│   └── ...
├── z        → (group)
│   ├── z    → "Center this line"
│   ├── o    → "Open fold"
│   └── ...
└── <Space>  → (leader group)
    ├── s    → (group: "Search")
    │   ├── f → "Search files"
    │   └── g → "Search grep"
    └── t    → (group: "Toggle")
        └── ...
```

**Node properties:**

| Field | Type | Description |
|-------|------|-------------|
| `key` | `String` | The single key this node represents (e.g. `"d"`, `"w"`, `"<C-w>"`) |
| `keys` | `String` | Full key path from root (e.g. `"daw"`) |
| `parent` | `Node?` | Parent node (nil for root) |
| `children` | `{String: Node}` | Child nodes keyed by their key |
| `desc` | `String?` | Human-readable description (e.g. `"Delete word"`) |
| `group` | `Bool` | True if this is a named group (label-only, not a leaf action) |
| `action` | `Action?` | The command to execute if this is a leaf binding |
| `hidden` | `Bool` | If true, exclude from the popup |
| `nowait` | `Bool` | If true, execute immediately even if children exist |

A node can be **both** a leaf (has an action) **and** a group (has children). In that case, `timeoutlen` and `nowait` determine behavior (see §4).

### 2.2 Mode

Each editor mode (`normal`, `visual`, `operator-pending`, etc.) has its **own independent tree**. The hint system maintains a separate trie per `(buffer, mode)` pair. When the user switches modes, the active tree changes.

### 2.3 Items (Display Model)

When the popup is shown, each child of the current node is projected into a display item:

| Field | Type | Description |
|-------|------|-------------|
| `key` | `String` | The next key to press (formatted for display) |
| `desc` | `String` | Description. For groups, prefixed with `+` (e.g. `+Search`). For leaves without a description, shows the child count (e.g. `"3 keymaps"`). |
| `icon` | `String?` | Optional icon (Nerd Font glyph or emoji) |
| `isGroup` | `Bool` | Whether this node leads to more children |

---

## 3. Trigger System

### 3.1 What Triggers the Overlay

The overlay is activated when the user presses a key that is the **prefix of multiple bindings** and is not itself a complete, `nowait` binding.

Which-key uses **trigger keymaps**: it replaces certain prefix keys with synthetic mappings that launch the hint state machine. The trigger system determines which prefixes to intercept:

**Auto-triggers** (default behavior): The system walks the keybinding tree and automatically creates triggers for nodes that:
- Have children (are a prefix of at least one multi-key binding)
- Do not themselves have a direct keymap (would shadow a real binding)
- Are "safe" — single-character keys are only auto-triggered for `g` and `z` prefixes (to avoid intercepting basic motions like `d`, `c`, `y` which are operators, not pure prefixes)

**Manual triggers**: The user can explicitly declare additional trigger prefixes (e.g. `<leader>`, `<C-w>`).

### 3.2 Trigger Safety Rules

For **single-character keys** in normal mode, only these are safe to auto-trigger:
- `g`, `z`, `Z` — these are conventionally prefix-only keys in vim
- All other single lowercase/uppercase letters are **not** auto-triggered (they are likely operators or motions: `d`, `c`, `y`, `v`, etc.)
- Multi-character prefixes like `<leader>`, `<C-w>`, `gr` are always safe

This prevents the hint system from interfering with fast typing of commands like `dd`, `dw`, `yy`.

### 3.3 Trigger Suspension

When a trigger fires and the hint system takes over the input loop, **all triggers for that mode are temporarily removed** (suspended). This prevents recursive triggering. After the sequence completes and the input loop returns to normal, triggers are **re-attached** on the next tick.

---

## 4. State Machine (Input Loop)

Once triggered, the hint system enters a synchronous input loop:

```
┌──────────────┐
│  TRIGGERED    │ ← User presses a trigger key (e.g. "g")
│  (prefix set) │
└──────┬───────┘
       │
       ▼
┌──────────────┐     ┌──────────────┐
│  WAIT FOR    │────▶│  SHOW POPUP  │  (after delay elapses)
│  DELAY       │     │              │
└──────┬───────┘     └──────┬───────┘
       │                     │
       ▼                     ▼
┌──────────────────────────────────┐
│          READ NEXT KEY           │◀─────────┐
│   (blocking getchar)            │           │
└──────────────┬───────────────────┘          │
               │                               │
    ┌──────────┼──────────┬──────────┐        │
    ▼          ▼          ▼          ▼        │
  MATCH     MATCH       <Esc>      <BS>      │
  (leaf)    (group)     cancel     go back    │
    │          │          │          │         │
    ▼          │          ▼          ▼         │
 EXECUTE       │       STOP      navigate     │
 & EXIT        │                 to parent ───┘
               │                               
               ▼                               
         update node ─────────────────────────┘
         (descend into group,
          refresh popup)
```

### 4.1 Step-by-Step

1. **Trigger fires**: The current prefix (e.g. `"g"`) and mode are captured. A timer starts.

2. **Delay**: The popup does not appear immediately. A configurable delay (default: 200ms, or 0ms for plugins) gives fast typists time to complete the sequence without ever seeing the popup. If the sequence resolves before the delay, the popup never appears.

3. **Show popup**: If the delay elapses and the user hasn't finished typing, the popup renders showing all children of the current node.

4. **Read next key** (blocking): The system calls `getchar()` — a blocking read of the next keypress.

5. **Dispatch on the key**:
   - **Child exists and is a leaf (no children)**: Execute the action. Exit the loop.
   - **Child exists and is a group (has children)**: Descend — set the current node to this child, refresh the popup, loop back to step 4.
   - **Child exists and is BOTH leaf and group**: Honor `nowait` and `timeoutlen`. If the binding has `nowait=true`, execute immediately. Otherwise, descend and let the user continue typing (the leaf will be executed if `timeoutlen` expires without further input).
   - **`<Esc>`**: Cancel. Exit the loop. No action executed.
   - **`<BS>` (Backspace)**: Navigate to parent node. If already at root, stay at root. Refresh popup. Loop back to step 4.
   - **Scroll keys** (`<C-d>`, `<C-u>`): Scroll the popup content. Stay on the same node. Loop back to step 4.
   - **No match (unknown key)**: Feed the entire accumulated key sequence (prefix + this key) back into the editor's normal input handling. Exit the loop. This allows partial matches to fall through to default behavior.

6. **Exit**: Hide the popup. Re-attach triggers (via the suspension/re-attach cycle in §3.3).

### 4.2 Timeoutlen Interaction

The system tracks elapsed time since the trigger fired. Vim's `timeoutlen` (default 1000ms) determines how long ambiguous sequences wait before auto-resolving:

- If a node is both a keymap and a group, and `timeoutlen` has elapsed, the keymap is executed (the "timed out" path).
- If `nowait` is set on the binding, it executes immediately regardless of timeout.

### 4.3 Count and Register Preservation

When the sequence completes and an action is executed, the system prepends:
- The **numeric count** (if the user typed a count before the trigger, e.g. `3g` → the `3` is preserved)
- The **register** (if the user selected a register with `"`, e.g. `"a` → preserved)

These are fed back into the editor along with the resolved keystrokes.

---

## 5. Popup Layout

### 5.1 Structure

The popup is a **floating panel** anchored to the bottom of the editor viewport (by default). It contains a **columnar table** of items.

Each row in the popup shows:

```
  key  ➜  icon  description
```

For example:
```
  d  ➜      Delete line
  w  ➜      Delete word
  i  ➜   +  inside
  a  ➜   +  around
```

### 5.2 Column Layout

The popup uses a table layout engine with these columns:

| Column | Alignment | Content |
|--------|-----------|---------|
| `key` | right | The next key to press |
| `sep` | left | Separator glyph (default: `➜`) |
| `icon` | left | Optional icon (inherits from parent if not set) |
| `desc` | left | Description text (groups prefixed with `+`) |

### 5.3 Multi-Column Flow

Items flow into **multiple columns** when the list is long. The algorithm:

1. Compute the maximum row width from all items.
2. Determine how many "boxes" (columns of items) fit in the available editor width: `box_count = floor(editor_width / (box_width + spacing))`.
3. Items fill **column-first** (top to bottom, then next column): item `i` goes to column `floor(i / box_height)`, row `i % box_height`.
4. `box_height = ceil(item_count / box_count)`, minimum 2.

### 5.4 Sorting

Items are sorted by multiple criteria applied in order (first criterion wins ties):

1. **Local-first**: Buffer-local bindings before global ones
2. **Order**: Plugin-specified ordering
3. **Group-last**: Leaf bindings before groups
4. **Alphanumeric-first**: `[a-zA-Z0-9]` keys before special keys
5. **Modifier-last**: `<C-...>`, `<M-...>` keys sorted after plain keys
6. **Natural sort**: Alphanumeric sorting with numeric segments compared numerically
7. **Case**: Lowercase before uppercase

### 5.5 Breadcrumb Trail

The popup title (if borders are enabled) or a footer line shows the **breadcrumb trail** — the path from root to the current node:

```
 +Search » f
```

This tells the user "you are inside the Search group, about to press `f`".

### 5.6 Help Footer

A footer line shows available meta-actions:

```
  ⎋ close   ⌫ back   ^d/^u scroll
```

- `<Esc>` to close
- `<BS>` to go back one level (only shown if not at root)
- Scroll keys (only shown if content overflows)

### 5.7 Positioning and Overlap

- **Default position**: Bottom of the editor, full width (the "classic" preset).
- **Overlap avoidance**: If the popup would overlap the cursor position, it repositions below the cursor row.
- **Padding**: Configurable padding around content (default: 1 line top/bottom, 2 chars left/right).
- **Z-index**: High z-index (default 1000) to float above other UI.

### 5.8 Visual Presets

Three built-in layout presets:

| Preset | Position | Border | Width |
|--------|----------|--------|-------|
| `classic` | Bottom, full width | None | `∞` (fills screen) |
| `modern` | Bottom center | Rounded | 90% of screen |
| `helix` | Bottom right | Rounded | 30-60 chars |

---

## 6. Description Resolution

When a node has no explicit `desc`, the system falls back:

1. If the binding has a string `rhs` (e.g. `:Telescope find_files<CR>`), use that as the description.
2. If the node is a group, show `"{N} keymaps"` where N is the child count.
3. Descriptions are cleaned up by stripping common noise: `<Cmd>`, `<CR>`, `<silent>`, `lua `, `call `, leading `:`.

---

## 7. Group Expansion

Groups with very few children can be **auto-expanded** — their children are shown inline rather than requiring a separate keypress to descend. Controlled by a threshold:

- `expand = 0` (default): Never auto-expand. Always show the group as a single entry.
- `expand = N`: If a group has ≤ N children, show them all inline.
- `expand = function(node)`: Custom predicate.

When a group is expanded, its children appear at the current level with their full key path relative to the popup's root node.

---

## 8. Integration Points for a Custom Editor

### 8.1 Required Editor Capabilities

To implement this system, the editor must provide:

1. **A keybinding registry** that can be queried: "given mode M, what bindings exist?"
2. **Modal input interception**: The ability to temporarily take over the input loop (read one character at a time without the editor's normal dispatch).
3. **A floating/overlay panel API**: Render styled text in a panel that floats over the editor content.
4. **Timer/delay API**: Schedule callbacks after a delay.
5. **Mode change notifications**: Know when the user switches modes, to cancel the hint state.

### 8.2 Implementation Checklist

1. **Build the trie**: On startup (and when bindings change), parse all keybindings for each mode into a trie.
2. **Install triggers**: For each multi-key prefix in the trie, install a synthetic binding that launches the hint loop.
3. **Hint loop**: When triggered, run the state machine from §4. Show the popup after the delay.
4. **Render the popup**: Project the current node's children into display items, sort them, lay them out in columns, and render.
5. **Handle completion**: When the sequence resolves, feed the accumulated keys (with count and register) back to the editor.
6. **Handle cancellation**: On `<Esc>`, hide the popup and discard the sequence.
7. **Handle backtrack**: On `<BS>`, navigate to the parent node and refresh.
8. **Suspend/re-attach triggers**: Remove triggers while the hint loop is active to prevent recursion. Re-attach after.

### 8.3 Edge Cases to Handle

- **Macros/recording**: Disable the hint system entirely while recording or replaying macros. The popup should not appear, and triggers should not fire.
- **Focus loss**: If the editor loses focus while the popup is open, auto-cancel after a timeout (which-key uses 5 seconds).
- **Command-line mode**: Never trigger from command-line mode transitions.
- **Operator-pending mode**: In operator-pending mode (after pressing `d`, `c`, `y`), the hint overlay can optionally start hidden and only appear after the delay, since the user is likely about to type a motion quickly.
- **Recursive triggering**: Guard against infinite loops — cap recursion depth (which-key uses 50).
- **Pending input**: If characters are already buffered (e.g. from a paste), do not trigger the hint system.

---

## 9. Minimal Example

Given these bindings in normal mode:

```
g g  → "Go to first line"
g d  → "Go to definition"  
g r  → (group: "LSP Actions")
g r n → "Rename symbol"
g r r → "Find references"
```

**User presses `g`:**

1. `g` is a trigger (it's a prefix with children, it's in the safe list).
2. Delay timer starts (200ms).
3. User does nothing for 200ms.
4. Popup appears:

```
  d  ➜  Go to definition
  g  ➜  Go to first line
  r  ➜  + LSP Actions
```

5. User presses `r`.
6. Current node becomes `gr`. Popup refreshes:

```
  n  ➜  Rename symbol
  r  ➜  Find references
```

Breadcrumb: `g » +LSP Actions`

7. User presses `n`.
8. `grn` is a leaf. Execute "Rename symbol". Hide popup. Exit loop.



