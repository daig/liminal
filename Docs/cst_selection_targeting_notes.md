# CST Selection Targeting Notes

These notes capture the current CST targeting confusion before we keep changing
code. There are two related but distinct issues:

1. point targeting at syntax boundaries
2. CST visual mode's initial selection granularity

## Boundary Targeting

Cambium's `SyntaxForest.containing(offset:in:)` currently treats child end
boundaries as contained by that child. It walks children left-to-right using
`containsAllowingEnd`.

That creates this behavior:

```text
before

|- foo
```

At the `|` byte, the previous blank line ends and the list item begins. Raw
forest containment can return the blank line:

```text
parent=root child=blankLine
```

For an editor block cursor, that is the wrong target. The cursor visually
occupies the character starting at the byte offset, so the desired target is
downstream:

```text
parent=list child=listItem
```

This is not really list-specific. It is a general "point affinity" question.
Cambium already exposes richer point behavior at the token layer via
`withTokenAtOffset`, which can distinguish `single` from `between(left, right)`.
The forest selection API does not yet expose an equivalent boundary choice.

Current Liminal-side probing (`offset`, then `offset + 1`) is therefore a
workaround for an API mismatch. The cleaner design is an additive Cambium API,
for example:

```swift
enum PointAffinity {
    case upstream
    case downstream
}

SyntaxForest.containing(offset, in: tree, affinity: .downstream)
```

or a similarly named `pointTarget` / `atPoint` API. Existing
`containing(offset:)` can keep its current behavior for compatibility.

Liminal would use downstream affinity for normal-mode block cursor operations
and for CST visual mode entry. Other caret-like features may still want the
existing upstream/end-inclusive behavior.

## Visual Entry Granularity

Boundary targeting only answers "which syntax is under the cursor?" It does not
answer "how far should visual CST mode ascend before showing the initial
selection?"

For example:

```text
- fo|o|
  - bar
```

The most specific target chain is roughly:

```text
inlineText("foo")
inlineContent
paragraph
listItem
list
root
```

Current Liminal visual entry has custom logic that ascends past `.allChildren`
parents and "glue" wrappers such as `inlineContent`. That was intended to avoid
starting visual CST mode on tiny text-token selections, but it mixes UX policy
into the targeting primitive. If the desired model is "start at the most
specific meaningful CST target, then let `h` expand," this ascension should be
removed or narrowed.

This is Liminal-specific policy, not Cambium policy. Cambium should provide the
smallest valid target for a point, with explicit boundary affinity. Liminal
should decide whether visual mode starts at that exact target, at a semantic
leaf, or at a block-level unit.

## Proposed Cleanup

1. Add a Cambium selection API that supports explicit point affinity.
2. Replace Liminal's local boundary probes with the Cambium downstream point
   API.
3. Revisit `LiminalForest.cstVisualEntry`.
   - Prefer starting from the smallest downstream target.
   - If inline text is too granular, define that as an explicit Liminal visual
     entry granularity rule rather than hiding it inside boundary targeting.
4. Keep paste/splice commands precise.
   - They may use the same downstream point target.
   - They should still validate that the original cursor byte is actually on
     the required marker/token/range.

## Regression Cases To Preserve

```text
before

|- foo
```

Entering CST visual mode should not select the preceding blank line.

```text
- fo|o|
  - bar
```

The raw point target should be the inline/text content under the cursor. The
initial visual selection may be inline text or paragraph depending on the final
UX decision, but it should not jump to the root list as a side effect of target
resolution.

```text
before

|- foo
```

Explicit list-item splice paste should target the list item whose marker starts
at the cursor, not the preceding blank line.
