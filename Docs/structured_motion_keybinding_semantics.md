# Structured Motion Keybinding Semantics

Status: working successor to the former CST motion vocabulary proposal for
command semantics.

This document preserves the useful keybinding intent from the older CST motion
proposal, but reframes it around the structured motion grammar:

1. Lift: choose the relevant enclosing structural unit from the current
   cursor, selection, or active CST forest.
2. Traverse: move among comparable units.
3. Land: choose whether the command targets an object, boundary, point, or CST
   slot.
4. Apply: perform the command's visible editor action against that target.

See `Docs/structured_motion_grammar_spec.md` for the normative behavioral spec
for Lift, Traverse, Land, and Apply. This document applies that grammar to
specific commands and proposed convenience bindings.

This file is deliberately not the development backlog. A separate follow-up
document should track remaining implementation work for Lift, Land, and Apply.
The main purpose here is to keep proposed convenience bindings semantically
clear.

## Reading This Document

Normal-mode commands are strictly richer than pure CST traversal. They start
from the text cursor or text selection, so they need the full grammar: Lift,
Traverse, Land, and Apply.

Visual-CST commands start from an already-lifted `LiminalForest` selection.
For those commands, this document records mostly the Traverse stage. Their
Land target is normally "the traversed forest" or, for extend commands, "the
new head endpoint." Apply updates the active forest selection and mirrors its
projection into the text view.

Command entries below are written in natural language. Where an older entry
says that Land "places," "opens," "mutates," or "inserts," read that as a
landed target plus the Apply action defined in the grammar spec.

`ForestMotion` is the current Traverse kernel. It is good at axes such as
sibling, ancestor, descendant, preorder, and subtree preorder, plus predicates
over structural categories, concrete kinds, glue wrappers, and heading levels.
If a proposed command cannot be expressed by that vocabulary alone, this
document calls that out.

## Normal-Mode Structural Commands

These commands start at the text cursor, land on a typed target, and then Apply
that target as text movement, selection, mutation, paste, or navigation. They
may use `ForestMotion` internally, but the user-visible command is not just a
forest traversal.

### `{` and `}`: Previous / Next Block Peer

Status: implemented in normal and text-visual motion modes.

Lift: from the current text cursor, choose the smallest enclosing CST container
that owns document-item children: root, block quote, list item, typed block,
schema block, template block, or structured embed block. Blank lines are not
meaningful block peers.

Traverse: move to the previous or next non-blank document-item child in that
container. Counts repeat this sibling traversal.

Land: produce a text point at the start of the target child.

Apply: move the text cursor to that point. In text-visual modes, extend the
text selection to that point.

Relationship to visual-CST: `:CSTPreviousBlock` and `:CSTNextBlock` express
similar intent for the active CST forest, but they are composite commands:
first lift the forest to a block item if needed, then traverse to a block-item
sibling.

### `gh`: Enclosing Heading

Status: implemented in normal and text-visual motion modes.

Lift: from the cursor byte offset, find the heading whose section contains the
cursor. If the cursor is already on that heading line, lift again to its parent
heading, so repeated `gh` walks outward through the outline.

Traverse: counts repeat the enclosing-heading ascent.

Land: produce a text point on the first non-blank byte of the chosen heading
line.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Relationship to visual-CST: the old proposal called this `gH` for the CST
plane. In the structured grammar, normal `gh` is richer because it starts from
a text cursor and lands at a text point.

### `[[` and `]]`: Previous / Next Heading

Status: implemented in normal and text-visual motion modes.

Lift: use the current cursor byte offset as the heading-search pivot. For
`[[`, when the cursor is inside a section body, first pivot through that
section's heading so the command lands on the previous heading rather than the
current enclosing one.

Traverse: move backward or forward through indexed ATX headings, regardless of
heading level. Counts repeat the heading traversal.

Land: produce a text point on the first non-blank byte of the target heading
line.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Relationship to visual-CST: visual-CST can express this as preorder traversal
to a heading category, but the normal command lands in text space.

### `[]` and `][`: Previous / Next Same-Level Heading

Status: proposed normal-mode convenience. Visual-CST traverse commands exist
as `:CSTPreviousSiblingHeading` and `:CSTNextSiblingHeading`.

Lift: find the nearest heading context for the current cursor. If the cursor is
on a heading, that heading supplies the comparison level. If the cursor is in a
section body, the enclosing section heading supplies the comparison level.

Traverse: move backward or forward to the next heading whose level equals the
lifted heading level.

Land: produce a text point on the first non-blank byte of the target heading
line.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Gap: the Traverse predicate exists in `ForestMotion`, but normal-mode bindings
and text-cursor landing are not wired for these chords.

### `[h` and `]h`: Previous / Next Deeper Heading

Status: proposed normal-mode convenience. Visual-CST traverse commands exist
as `:CSTPreviousDeeperHeading` and `:CSTNextDeeperHeading`.

Lift: find the nearest heading context for the current cursor, as with `[]`
and `][`.

Traverse: move backward or forward to the next heading whose level is strictly
deeper than the lifted heading level.

Land: produce a text point on the first non-blank byte of the target heading
line.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Gap: the Traverse predicate exists in `ForestMotion`, but normal-mode bindings
and text-cursor landing are not wired.

### `[H` and `]H`: Previous / Next Shallower Heading

Status: proposed completion of the heading-level family. Visual-CST traverse
commands exist as `:CSTPreviousShallowerHeading` and
`:CSTNextShallowerHeading`.

Lift: find the nearest heading context for the current cursor.

Traverse: move backward or forward to the next heading whose level is strictly
shallower than the lifted heading level.

Land: produce a text point on the first non-blank byte of the target heading
line.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Gap: the old proposal named only same-level and deeper-heading motions. The
Traverse predicate for shallower headings now exists, but there is no agreed
normal-mode chord.

### `[r` and `]r`: Previous / Next Reference

Status: implemented in normal and text-visual motion modes.

Lift: use the current cursor byte offset as the search pivot.

Traverse: move backward or forward through indexed references in source order.
Counts repeat the reference traversal.

Land: produce a text point at the start of the reference source range.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Relationship to visual-CST: this is broader than a pure `ForestMotion`
category search because it uses the document index and lands at a text point.

### Bracket-Prefix Kind Search

Status: proposed normal-mode convenience family. Visual-CST has the underlying
category search through `:CSTGlobalFind <kind>` and
`:CSTGlobalFindLast <kind>` for most of these categories.

Lift: use the current cursor byte offset as the search pivot.

Traverse: move backward or forward in document preorder to the next matching
structural category:

- `[w` / `]w`: wikilink.
- `[l` / `]l`: markdown-style link.
- `[e` / `]e`: embed.
- `[b` / `]b`: block-id anchor.
- `[c` / `]c`: code block or inline code.
- `[m` / `]m`: math block or inline math.
- `[k` / `]k`: typed construct family.

Short aliases in the visual-CST `f` / `F` family use the same letters:

- `w`: wikilink.
- `l`: markdown-style link.
- `e`: embed.
- `b`: block-id anchor.
- `c`: code block or inline code.
- `m`: math block or inline math.
- `k`: typed construct family.

Land: produce a text point at the start of the matched structural object.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Gap: the visual-CST Traverse kernel can find these categories, but normal-mode
bindings and text-cursor landing are not wired. If this family is implemented,
it should decide whether to use the CST preorder search directly, a
DocumentIndex extension, or a shared structural-query layer.

### `[t` and `]t`: Previous / Next Task List Item

Status: proposed.

Lift: use the current cursor byte offset as the search pivot.

Traverse: move backward or forward in document preorder to the next `listItem`
that has a task marker.

Land: produce a text point at the start of that list item, or possibly at the
task marker if the command is defined as a task-toggle aid. The target policy
needs an explicit product decision.

Apply: move the text cursor to that point, or extend the active selection in
text-visual modes.

Gap: task-ness requires inspecting list-item children, not just checking a
structural category. This is not currently represented as a structured
`ForestMotion` predicate.

### `[d` and `]d`: Previous / Next Diagnostic

Status: reserved, not implemented.

Lift: use the current cursor byte offset as the search pivot.

Traverse: move backward or forward through diagnostics in source order.

Land: produce a text point at the diagnostic's primary source range, plus the
diagnostic region when it spans more than one point.

Apply: move the cursor to the point, or extend the active selection in
text-visual modes. Expose the full diagnostic region through the diagnostic UI.

Gap: diagnostics are not currently a `ForestMotion` predicate and should
probably come from a diagnostic index rather than CST traversal alone.

### `gd`: Follow Reference At Cursor

Status: implemented as an Ex command with a normal-mode shortcut.

Lift: find the innermost reference containing the current cursor.

Traverse: resolve that reference through workspace/navigation state rather than
moving through the CST.

Land: produce a navigation target. For same-document anchors, include the
resolved anchor point. For missing or ambiguous targets, include the unresolved
navigation query needed by the existing navigation UI.

Apply: open or focus the navigation target. For same-document anchors, move the
text cursor to the resolved anchor. For missing or ambiguous targets, hand off
to the existing navigation UI.

This is not a motion in the Traverse-kernel sense, but it follows the same
Lift, Land, and Apply framing.

### `<Space>t`: Toggle Task

Status: implemented as an Ex command with a normal-mode shortcut.

Lift: find the task list item containing the cursor and identify its marker.

Traverse: none.

Land: produce a mutation target for the task marker.

Apply: mutate the marker in place and keep the user's editing context stable.

This command is a useful reminder that Lift, Land, and Apply are not only for
motions.

### `:CSTPasteBlock`: Block CST Paste

Status: implemented as an Ex command. Normal `p` also routes a `cstForest`
clipboard payload through this block-paste path.

Lift: project the current cursor to the root document-item sequence, preserving
the root child nearest the cursor as the reference item.

Traverse: none today. Future target-picking commands could insert a Traverse
stage before paste.

Land: produce a child-boundary CST slot in `root` before or after the reference
root child.

Apply: insert the compatible CST clipboard payload into that slot. Separator
normalization comes from the resolved parent kind and boundary context, not from
a separate block renderer.

Gap: this still uses `StructuralCSTPasteTargetScope` rather than the general
structured motion grammar.

### `:CSTPasteSplice` / `<Space>p`: Splice CST Paste

Status: implemented as an Ex command with a normal-mode shortcut.

Lift: project the current cursor to the exact CST focus used by the structural
paste resolver.

Traverse: none today. Future target-picking commands could insert a Traverse
stage before paste.

Land: produce a precise sibling CST slot in the target parent's child sequence.
For the current implemented case, this is a child boundary in the target `list`
before or after the focused list item.

Apply: insert the compatible CST clipboard payload into that slot. Splice is
the slot-acquisition intent; rendering is selected by payload family plus slot
parent kind and boundary context.

Gap: this still uses `StructuralCSTPasteTargetScope` rather than the general
structured motion grammar.

### `:CSTPasteNest` / `<Space>n`: Nest CST Paste

Status: implemented as an Ex command with a normal-mode shortcut.

Lift: project the current cursor to the exact CST focus used by the structural
paste resolver.

Traverse: none today. Future target-picking commands could insert a Traverse
stage before paste.

Land: produce the target container node, then derive an interior CST slot from
that node. For the current implemented case, a `listItem` node derives a child
boundary in a nested `list`.

Apply: insert the compatible CST clipboard payload into the derived slot. Nest
is the container-to-slot intent; rendering is selected by payload family plus
parent kind and boundary context.

Gap: like splice paste, this still uses `StructuralCSTPasteTargetScope`.

### `gC`: Enter Visual-CST

Status: implemented in normal mode.

Lift: project the current text cursor to a CST forest using visual-CST entry
semantics. This starts with the smallest cursor target, then ascends past
token-oriented or structural-glue wrappers until the selection is a meaningful
structural unit.

Traverse: none.

Land: produce a CST forest selection target for the lifted forest.

Apply: switch to visual-CST mode with that forest as the active structural
selection and mirror its source projection into the text view.

This command is the bridge from normal-mode Lift/Land/Apply commands into the
traverse-oriented CST plane.

## Normal-Mode Structural Text Objects

Status: proposed. These come from the navigation spec and from the object
motion section of the old CST motion proposal. They are normal/operator-pending
or text-visual commands, not pure visual-CST traversals.

General rule:

- Lift: find the smallest enclosing object of the requested kind at the current
  cursor or selection.
- Traverse: counts expand the object through sibling or ancestor structure,
  depending on the object family.
- Land: produce an object range. `i` lands on the inner/content range; `a`
  lands on the around/whole-object range.
- Apply: select that range in text-visual mode, or feed it to the pending
  operator as the operator target.

Proposed object meanings:

- `ih` / `ah`: heading inline content / whole heading line.
- `iH` / `aH`: section content / section including heading.
- `ie` / `ae`: paragraph inline content / whole paragraph.
- `ic` / `ac`: code payload / code object including delimiters or fence.
- `im` / `am`: math payload / math object including delimiters.
- `ik` / `ak`: typed block body / typed block including header and close
  fence.
- `if` / `af`: fields interior / fields including braces.
- `iv` / `av`: field value / field name, colon, and value.
- `il` / `al`: wikilink target / whole wikilink.
- `iL` / `aL`: markdown link destination / whole markdown link.
- `in` / `an`: list item content / whole list item.
- `iq` / `aq`: block quote body / whole block quote.

Gap: structural object resolution is mainly a Lift and Land problem, with Apply
handling selection or operator dispatch. It should not be implemented by adding
more ad-hoc Traverse cases unless the object also needs counted sibling or
ancestor expansion.

## Visual-CST Traverse Commands

These commands operate on the active CST forest. Treat their Lift stage as
"already done by `gC` or an existing visual-CST selection."

### Core Direct Chords

Status: implemented.

- `h` / `:CSTParent`: traverse ancestor, skipping structural-glue wrappers in
  one logical step.
- `l` / `:CSTFirstChild`: traverse down the first-child chain, skipping
  structural-glue wrappers in one logical step.
- `j` / `:CSTNextSibling`: traverse to the next navigable sibling.
- `k` / `:CSTPreviousSibling`: traverse to the previous navigable sibling.
- `J` / `:CSTExtendForward`: extend the head endpoint to the next sibling.
- `K` / `:CSTExtendBackward`: extend the head endpoint to the previous
  sibling.
- `o` / `:CSTSwapEnds`: swap anchor and head. This is endpoint management, not
  traversal.
- `f<kind>` / `:CSTFind <kind>`: traverse subtree preorder to the first
  matching kind category.
- `F<kind>` / `:CSTFindLast <kind>`: traverse subtree preorder to the last
  matching kind category.

The currently recognized `f` / `F` kind letters are:

- `h`: heading.
- `c`: code.
- `m`: math.
- `r`: any reference.
- `l`: markdown-style link.
- `w`: wikilink.
- `e`: embed.
- `k`: typed construct family.
- `b`: block-id anchor.

### Sibling Endpoints

Status: implemented as Ex commands; old proposal suggested `gj` / `gk` as
direct visual-CST chords.

- `:CSTFirstSibling`: traverse previous siblings until saturation.
- `:CSTLastSibling`: traverse next siblings until saturation.

Gap: direct visual-CST chords are not wired.

### Kind Runs

Status: implemented as Ex commands; old proposal suggested `w` / `b` as direct
visual-CST chords.

- `:CSTKindRunForward`: traverse to the next sibling whose structural category
  set differs from the current head.
- `:CSTKindRunBackward`: traverse to the previous sibling whose structural
  category set differs from the current head.

Gap: the old proposal's `e` command, "collapse to the last sibling in the
current kind-run," is not implemented as a named command.

### Block Peers

Status: implemented as Ex commands; old proposal suggested `{` / `}` as
direct visual-CST chords.

- `:CSTNextBlock`: if needed, lift the active forest to a block item, then
  traverse to the next non-blank block-item sibling.
- `:CSTPreviousBlock`: same, but backward.

Note: these commands are not pure Traverse in the strict grammar because they
include an internal Lift step before the sibling traversal. A future grammar
surface should expose that composition explicitly.

### Heading Traversal

Status: implemented as Ex commands for same/deeper/shallower heading levels.
The old proposal suggested direct visual-CST chords such as `]]`, `[[`, `][`,
`[]`, `]h`, and `[h`.

- `:CSTGlobalFind heading`: traverse preorder to the next heading.
- `:CSTGlobalFindLast heading`: traverse preorder to the previous heading.
- `:CSTNextSiblingHeading`: traverse preorder to the next heading at the same
  level as the starting heading context.
- `:CSTPreviousSiblingHeading`: same, backward.
- `:CSTNextDeeperHeading`: traverse preorder to the next strictly deeper
  heading.
- `:CSTPreviousDeeperHeading`: same, backward.
- `:CSTNextShallowerHeading`: traverse preorder to the next strictly shallower
  heading.
- `:CSTPreviousShallowerHeading`: same, backward.

Gap: direct visual-CST chords are not wired. The normal-mode same-level,
deeper-heading, and shallower-heading bindings are also not wired.

### Global Kind Search

Status: implemented as Ex commands; old proposal suggested bracket-prefix
direct chords.

- `:CSTGlobalFind <kind>`: traverse document preorder to the next matching
  structural category.
- `:CSTGlobalFindLast <kind>`: same, backward.

Supported command arguments are `heading`, `code`, `math`, `reference`,
`markdownlink`, `wikilink`, `embed`, `typedblock`, and `blockanchor`.

Gap: task-list-item and diagnostic search are not supported by this command.

### Axis By Kind

Status: implemented as Ex commands.

- `:CSTAncestor <kind>`: traverse ancestors to the nearest matching category.
- `:CSTDescendant <kind>`: traverse the first-child descendant chain to the
  nearest matching category.

These are generic Traverse helpers rather than final product keybindings.

### Last Child And Document Endpoints

Status: implemented as Ex commands.

- `:CSTLastChild`: traverse down the last-child chain, skipping
  structural-glue wrappers.
- `:CSTDocumentStart`: jump to the same structural granularity that `gC` would
  choose at the start of the document.
- `:CSTDocumentEnd`: jump to the same structural granularity that `gC` would
  choose at the last meaningful byte of the document.

Gap: the old proposal's `gl`, "descend the full first-child chain to the
deepest navigable leaf," is not the same as `:CSTLastChild` and is not
currently implemented as a named command.

### Forest Marks

Status: implemented as Ex commands.

- `:CSTMark <letter>`: save the current CST forest selection to a forest mark.
- `:CSTJumpToMark <letter>`: restore the saved CST forest selection.
- `:CSTUnmark <letter>`: remove a saved forest mark.

These are not Traverse commands. They are structural selection persistence.
The old proposal suggested `m<a-z>` and `` `<a-z> `` direct visual-CST chords;
those direct chords are not wired.

### Smart Expand And Narrow

Status: implemented as Ex commands.

- `:CSTExpand`: ascend one navigable level and remember the child index that
  was exited.
- `:CSTNarrow`: descend back through the remembered child path, or fall back to
  first-child descent when the stack is empty or stale.

These commands are partly Traverse and partly selection-history management. The
old proposal suggested `+` / `-`, `<Tab>` / `<S-Tab>` style direct chords; those
direct chords are not wired.

## Retired Framing From The Old Proposal

The old proposal described three layers as:

1. a small CST search kernel,
2. a named motion catalog,
3. slide vs extend.

That was useful for implementing `ForestMotion`, but it is not the product
grammar. The product grammar is Lift / Traverse / Land / Apply. Direct
keybindings should be described in those terms, and pure visual-CST commands
should be understood as conveniences over the Traverse layer unless explicitly
stated otherwise.
