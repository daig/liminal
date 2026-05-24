# Structured Motion Grammar Spec

Status: normative behavioral spec.

This document defines Liminal's structured motion grammar. It is the source of
truth for the terms Lift, Traverse, Land, and Apply. The keybinding catalog in
`Docs/structured_motion_keybinding_semantics.md` applies this grammar to
specific commands.

The grammar has four stages:

1. Lift: choose the structural context a command operates relative to.
2. Traverse: move among comparable structural units.
3. Land: project the resolved structural result into a typed editor target.
4. Apply: perform the command's editor action against that target.

The stages are conceptual, not a mandate for public Swift API shape. Current
implementation details may be split across `StructureCursor`, `DocumentIndex`,
`ForestMotion`, `StructuralCSTPasteTargetScope`, and app-level coordinators.

Structured editing distinguishes four structural values:

- Cursor position: a text-space point used as Lift input or motion output, not
  a structural edit target.
- CST node: one structural object in the parsed tree. Node targets are useful
  for inspection, mutation, or deriving an interior slot.
- CST forest: contiguous sibling children plus their parent role. Forest
  targets are useful for yank, delete, change, and replace.
- CST slot: a typed boundary in a parent/container child sequence. Slot targets
  are useful for insert, paste, generated structure, and splice-like edits.

## Grammar Contract

Every structured command must define which stages it uses, what each stage
produces, and which values are handed to Apply. A command may skip a stage only
when the skipped stage is genuinely irrelevant, such as a mutation command with
no traversal.

Normal-mode commands usually run all four stages. They start from a text
cursor, text selection, or editor action context, land on a text point, text
range, CST slot, mutation target, or navigation target, then Apply turns
that target into the visible editor action.

Text-visual modes use the same command semantics as normal mode, but Apply
extends the active text selection for motion targets unless the command is
explicitly an action rather than a motion.

Visual-CST commands start from an already-lifted `LiminalForest`. For those
commands, Lift is normally "the active forest selection." They mostly exercise
Traverse, Land usually produces a CST forest target or forest-head target, and
Apply updates the active forest selection and mirrored text projection.

Counts repeat Traverse by default. A command may give count to Lift, Land, or
Apply only when that behavior is explicitly part of the command's semantics.
Examples: heading motions repeat heading traversal; structural text-object
counts may widen the landed object range through sibling or ancestor structure;
operator commands may carry a count into Apply after the target is resolved.

Failure is no-op plus signal. If Lift, Traverse, or Land cannot resolve, Apply
must not run. The command must leave editor state unchanged and surface a quiet
failure signal, such as a beep or status affordance. Commands must not partially
land after a later-stage failure unless the command explicitly documents
saturation or partial progress.

Apply has its own preconditions. If Apply cannot use the landed target with the
command payload or current editor state, it must fail before mutating state, or
perform a single undoable transaction that can be cleanly reverted. A paste
whose payload is incompatible with the landed CST slot is an Apply failure, not
a reason for Land to silently choose a different slot.

Saturation is a Traverse policy, not the global failure rule. Pure forest
traversals may saturate at the last successful step for repeated counts, but a
normal-mode command that needs a final text point, object range, CST slot,
or external target must still fail without changing state if Land cannot
project the final result. Once Apply starts, commands should not expose partial
progress.

Glue policy belongs to Lift unless a command explicitly says otherwise. User
facing Lift should skip token-only and structural-glue wrappers when choosing a
meaningful structural unit. Raw CST positions are implementation details or
debug affordances, not the default product grammar.

## Stage Values And Apply Input

The landed target is the primary input to Apply, but it is not the whole command
state. Apply receives a command envelope, the landed target, narrowly retained
stage context, and the current editor transaction context.

The command envelope contains user intent that is not part of the target:
operator kind, direction, count, before/after flag, paste intent, paste payload,
mark name, requested object granularity, and the source mode that determines
whether a motion moves the cursor or extends a selection.

The landed target contains the resolved destination or object. For pure
motions, it is usually sufficient: a text point plus the source mode tells
Apply whether to move the cursor or extend the text selection. For text
objects, an object range plus the command envelope tells Apply whether to
select, delete, change, yank, or otherwise operate on that range.

Retained stage context is allowed only when it is semantic input to Apply, not
as an escape hatch for re-running earlier stages. Examples:

- A text-visual motion needs the existing selection anchor, which is editor
  state retained for Apply.
- A visual-CST extend command needs the active forest anchor and the landed head
  endpoint, not just the target forest as an isolated object.
- Structural paste needs more than a byte insertion point. Apply needs the
  payload, before/after intent, paste intent, and the landed CST slot or
  container target with enough resolved context to validate compatibility and
  build the edit plan.
- A task toggle should carry the marker range and current marker state found by
  Lift or Land so Apply can flip that precise marker without searching again.
- A navigation command needs the resolved navigation target plus activation
  policy from the command envelope.

Retained context must be named in the command's semantics. It should be stable
enough for immediate Apply and should not be arbitrary parser or UI state that
would let Apply reinterpret the command target. If Apply discovers that retained
context is stale or incompatible, it fails without changing editor state.

## Lift Layer

Lift answers "what structural context is this command relative to?" It must not
decide where to go next, which target will be produced, or what editor action
will happen. Those belong to Traverse, Land, and Apply.

Standard Lift inputs:

- Text cursor: a byte offset in the current source.
- Text selection: a current text range, including visual selections.
- Active CST forest: the current visual-CST structural selection.
- Mark: a stored text or forest anchor.
- Paste focus: the cursor-projected structural focus used for paste.
- Indexed target: a heading, reference, diagnostic, or other document-indexed
  item.

Standard Lift outputs:

- Meaningful CST forest: a `LiminalForest` at the granularity a user expects,
  not necessarily the smallest raw node.
- Block container context: a container that owns document-item children, plus
  the child or insertion relationship around the cursor.
- Heading context: the nearest heading that owns the current section, or the
  current heading when the cursor is on a heading line.
- Reference context: the innermost reference containing the cursor, or a
  source-order pivot for reference traversal.
- Task item context: a list item with a task marker and marker location.
- Diagnostic context: a source-order pivot or containing diagnostic.
- Structural object context: the smallest enclosing object of a requested
  kind, such as section, paragraph, code, math, typed block, field, link, list
  item, or block quote.
- Insertion context: a target parent/container plus a reference child or slot.

Lift must be explicit about boundary affinity. At a boundary between structural
children, commands must define whether the downstream child, upstream child, or
CST slot is the intended context. Existing cursor-target behavior prefers
downstream selection for visual-CST entry; paste may prefer a slot relative to
the nearest child.

Lift must preserve enough metadata for Land and Apply. For example, a
block-container Lift needs not only the container but also the reference child;
a paste Lift needs a parent/container anchor plus boundary context; a
structural-object Lift needs inner and around candidate ranges when those
differ.

Lift may use indexes when the structural context is not represented by CST
ancestry alone. Heading sections and references are examples: their user-facing
context may be a source-order or document-index relation rather than a parent
chain.

## Traverse Layer

Traverse answers "among comparable units, which unit is next?" It must not
choose the initial structural context, decide which target kind Land should
produce, or perform the editor action.

`ForestMotion` is the current CST Traverse kernel. It supports:

- sibling traversal,
- ancestor traversal,
- first-child and last-child descendant traversal,
- document preorder traversal,
- subtree-bounded preorder traversal,
- predicates over structural categories,
- predicates over concrete kinds,
- glue-wrapper exclusion,
- category-difference runs,
- heading-level comparisons relative to a starting heading context,
- custom predicates for cases that cannot be represented as category checks.

Document-index traversal is also Traverse. It covers headings and references
today, and may later cover diagnostics, tasks, blocks, or other indexed
targets. Index-backed traversal is preferred when the traversal relation is
source-order or semantic rather than tree-local.

Traversal units must be comparable. Sibling traversal compares siblings under
one parent. Heading-level traversal compares ATX headings by level. Reference
traversal compares indexed source ranges. A command should not mix unrelated
unit types in one Traverse step.

Counts repeat one logical Traverse step. Each repeated step rebases from the
new current unit unless a command explicitly defines an absolute count. This
matches current forest behavior for category-difference runs and normal motion
behavior for repeated structural motions.

Traverse gaps that need non-category support:

- Task item traversal needs a predicate that inspects list-item children for a
  task marker.
- Diagnostic traversal should come from a diagnostic index rather than the CST
  traversal kernel alone.
- Paste target traversal may need to traverse containers or slots, not only
  selectable forests.

## Land Layer

Land answers "which editor target did the resolved structural result denote?"
It owns projection from structural coordinates into typed target coordinates.
It does not move the cursor, change selection, mutate text, paste, or navigate.
Those are Apply responsibilities.

Standard Land target kinds:

- Text point: a byte offset and affinity, usually converted through the
  editor's text coordinate system.
- Text range: a source range suitable for selection or operation.
- Object range: choose inner or around range for a structural text object.
- CST forest selection target: a forest intended to become the active
  visual-CST selection.
- CST forest head target: a new head endpoint for an active visual-CST
  selection whose anchor is retained by Apply.
- CST slot: choose a typed parent/container child-sequence role and a boundary
  for paste or generated structure.
- Mutation target: identify the precise source bytes or CST handle to edit.
- Navigation target: a destination descriptor for another document,
  same-document anchor, or external URL.

Land must define mode-sensitive target shape, but not mode side effects. In
normal mode, a motion usually lands as a text point. In text-visual modes, the
same motion usually lands as the same text point while Apply uses the existing
selection anchor to extend the selection. In visual-CST, a traverse command
lands as a CST forest selection target or CST forest head target while Apply
updates the structural selection and mirrors its projected source ranges.

Land must define object granularity. For structural text objects, `i` lands on
the inner/content range and `a` lands on the around/whole-object range. If the
inner range is empty but meaningful, the command may land an empty range only
when the editor can represent it; otherwise it must no-op plus signal.

Land must treat CST slots as first-class structural targets. A stable slot is
not a raw byte offset and is not a raw child index. Its semantic identity is:

- the parent/container anchor;
- the typed child-sequence role, such as `root.documentItems`, `list.items`,
  `blockQuote.documentItems`, `pipeTable.rows`, `pipeTableRow.cells`,
  `inlineContent.children`, `fields.children`, or `listValue.values`;
- a boundary anchor: `atStart`, `atEnd`, `before(reference child)`,
  `after(reference child)`, or a `between(left, right, affinity)` form.

A resolved CST slot is current-tree-only execution data. It should normalize
the anchor into the parent handle/path, the typed role, the insertion child
index, the insertion byte offset, and left/right neighbor metadata. Stable slot
anchors may resolve as strong, weak, recovered, or lost, mirroring the existing
CST anchor and forest-anchor model. Apply may use a resolved slot immediately,
but persistent marks, deferred execution, and target-picking UI should store
slot anchors and re-resolve them against the current tree.

Land must define CST slot semantics. A splice lands at a sibling slot in
the target parent's child sequence. A nest lands at a slot inside a target
container. A block paste lands at a document-item slot. Slot choice must be
explicitly before or after the reference child; it must not be guessed from a
raw cursor offset after Lift has already resolved a structural site.

Block, splice, append-inside, and prepend-inside are different ways to acquire
a slot, not different final rendering operations. Once Land has produced a
typed slot, Apply renders from the logical payload family, the slot role, and
the slot's boundary context. Nest commands may start from a CST node, but a
successful nest lowers that node target to an interior slot before insertion.

Land must not repair incompatible Traverse results by silently choosing a new
target. If a traversal found a forest but the command needs a text point,
object range, or CST slot that cannot be projected, the command fails
without changing state.

## Apply Layer

Apply answers "what operation does this command perform with the landed target?"
It is the only stage that changes editor state, external navigation state, mark
registries, pasteboards, or undo history.

Standard Apply actions:

- Move the text cursor to a landed text point.
- Extend the active text selection to a landed text point.
- Select a landed text range or object range.
- Feed a landed object range to an operator such as delete, change, or yank.
- Replace the active visual-CST forest or move its head endpoint, then mirror
  the projected source ranges in the text view.
- Mutate a landed source range or CST handle, such as toggling a task marker.
- Insert a compatible payload at a landed CST slot. Block paste and splice
  paste are slot insertions. Nest paste first resolves a container node to an
  interior slot, then inserts there.
- Open or focus a landed navigation target.
- Save, restore, or clear structural selection marks.

Apply must respect the target chosen by Land. It may validate compatibility and
derive concrete edits from the target, but it must not silently re-lift from the
current cursor or re-traverse to a nearby alternative. If Apply needs fallback
behavior, the command must document it as part of Apply, not hide it as a target
repair.

For structural paste, Apply must not use the command's block/splice/nest label
as a rendering shortcut. Those labels describe paste intent and slot acquisition
semantics. Concrete target rendering is selected by the logical payload family
and the resolved slot role, with local boundary context for separator,
indentation, marker, quote-prefix, and delimiter policy.

Apply owns post-action editor context. Mutations such as task toggle should keep
the cursor or selection stable unless the command explicitly defines a new
target position. Paste commands should set the cursor according to the paste
plan. Navigation commands should let the navigation subsystem choose focus and
selection for the resolved destination.

Apply should be transaction-aware. A command that mutates text should create or
join the appropriate undo unit before applying edits. A command that only moves
selection or focus does not need an edit transaction, but it still must leave
state unchanged on failure.

## Validation Examples

These examples validate the grammar. They are not an implementation order.

### `]r`: Next Reference

Lift: use the current text cursor as a source-order reference pivot.

Traverse: move to the next indexed reference source range.

Land: produce a text point at the start of the reference source range.

Apply: in normal mode, move the text cursor to that point. In text-visual
modes, extend the active selection to that point.

### `][`: Next Same-Level Heading

Lift: find the heading context for the current cursor. If the cursor is inside
a section body, use that section's heading. If the cursor is on a heading, use
that heading.

Traverse: move forward to the next heading at the same level.

Land: produce a text point at the first non-blank byte of the target heading
line.

Apply: move the cursor to that point, or extend the active text selection in
text-visual modes.

### `{` and `}`: Block Peer Motion

Lift: choose the smallest enclosing block container that owns document-item
children and identify the child relationship around the cursor.

Traverse: move to the previous or next non-blank document-item sibling.

Land: produce a text point at the start of the target child.

Apply: move the cursor to that point, or extend the active text selection in
text-visual modes.

### `gC`: Enter Visual-CST

Lift: project the current text cursor to a meaningful CST forest, skipping
token-oriented and structural-glue wrappers.

Traverse: none.

Land: produce a CST forest selection target for the lifted forest.

Apply: enter visual-CST mode with that forest as the active structural selection
and mirror the forest projection into the text view.

### `:CSTGlobalFind heading`: Visual-CST Heading Search

Lift: use the active visual-CST forest.

Traverse: move forward in document preorder to the next heading.

Land: produce a CST forest selection target for the traversed forest.

Apply: replace the active visual-CST forest with that target and mirror the
resulting source projection into the text view.

### Visual-CST Extend To Next Sibling

Lift: use the active visual-CST forest selection, including its anchor and head.

Traverse: move from the current head endpoint to the next sibling.

Land: produce a CST forest head target for the traversed sibling.

Apply: move the active forest head to that target while preserving the retained
anchor, then mirror the resulting forest projection into the text view.

### `iH`: Inner Section Text Object

Lift: find the smallest heading section containing the cursor.

Traverse: if a count is supplied, widen through sibling sections at the same
level according to the text-object count policy.

Land: produce an object range for the section content, excluding the heading
itself.

Apply: select that range in text-visual mode, or provide it to the pending
operator as the operator target.

### Structural Paste Splice

Lift: project the current cursor to an exact structural focus with a target
parent and reference child.

Traverse: none today. A future paste-target command may traverse to a different
focus before landing.

Land: produce a typed sibling CST slot relative to the reference child. For the
current list splice command, this is a `list.items` slot before or after the
focused `listItem`.

Apply: consume the landed slot, the structural paste payload, the before/after
flag, and the retained resolved-slot context. Validate compatibility, choose
the renderer from payload family plus slot role, apply the edit transaction,
and set the post-paste cursor from the paste plan.

The landed target alone is sufficient only if it includes the structural site,
not merely a byte offset. A byte offset would lose the target parent, reference
child, typed slot role, origin focus, and exact target forest that the paste
planner needs.

### Structural Paste Nest

Lift: project the current cursor to the target container node.

Traverse: none today. A future paste-target command may traverse to a different
container before landing.

Land: produce the container node target and derive an interior CST slot from
that node according to the command's nest semantics. For the current nested
list command, a `listItem` node derives a child `list.items` slot, creating or
choosing that child-list position as needed.

Apply: insert the compatible payload into the derived slot. Rendering is chosen
from payload family plus slot role, not from the fact that the command was
called "nest."

### Structural Paste Block

Lift: project the current cursor to the root document-item sequence, preserving
the root child nearest the cursor as the reference item.

Traverse: none today.

Land: produce a `root.documentItems` CST slot before or after the reference root
child.

Apply: insert the compatible payload into that slot. Root separator
normalization is part of the `root.documentItems` renderer.

### `<Space>t`: Toggle Task

Lift: find the task list item containing the cursor and identify its task
marker.

Traverse: none.

Land: produce a mutation target containing the marker source range, current
marker state, and enclosing task-item context.

Apply: flip that marker in place and keep the user's cursor or selection stable
unless a future task-toggle command explicitly defines a new post-toggle
position.

### `gd`: Follow Reference At Cursor

Lift: find the innermost reference containing the current cursor.

Traverse: resolve that reference through the workspace/navigation index. This
is a semantic traversal over navigation targets, not a CST sibling or preorder
traversal.

Land: produce a navigation target for the resolved same-document anchor,
document, or external URL.

Apply: activate that navigation target through the existing navigation flow.
For same-document anchors, focus the anchor location; for ambiguous or missing
targets, hand off to the navigation UI.

## Relationship To Command Semantics

The keybinding semantics document classifies specific commands against this
grammar. When a command appears to need special behavior, update this grammar
only if the behavior changes the meaning of Lift, Traverse, Land, or Apply.
Otherwise, record the command-specific detail in the keybinding semantics
document.

Future implementation plans should use this document to choose abstractions,
but this document intentionally does not prescribe concrete type names,
protocols, or source file boundaries.
