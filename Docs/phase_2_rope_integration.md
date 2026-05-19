# Handoff — Phase 2: Liminal rope integration

**Status:** Ready to execute. Cambium foundation (Phases 1a–1d) shipped.
**Audience:** A fresh Claude session, or me in a new conversation, focused on Liminal.
**Plan file (full architectural context):** `/Users/dai/.claude-personal/plans/ok-1-xxh3-128-sounds-splendid-thacker.md`
**Original rope plan (still authoritative for per-hotspot detail):** `/Users/dai/code/cambium/Docs/rope_source_storage.md`

---

## What just shipped (Cambium Phases 1a–1d)

Four phases of Cambium-side foundation work, leaving Cambium ready for Liminal to migrate its source storage. All in one continuous push; 234 Cambium tests pass, 26 Calculator example tests pass, Liminal still builds with zero source changes.

### 1a — Content hashing
- `Sources/CambiumCore/ContentHashing.swift` — `ContentHash` (128-bit) + `ContentHasher` static API (`hash(_:)`, `tokenHash(...)`, `nodeHash(...)`, `Streaming` struct, `ContentHash.empty`).
- `structuralHash` (UInt64, key-indexed) replaced with `contentHash` (ContentHash, byte-stable) throughout the green layer: `GreenNode`, `GreenToken`, `GreenNodeHeader`, `GreenElement`, plus `ForestNodeFingerprint`/`ForestAnchor` in CambiumSelection.
- Liminal-side adapters updated: `CSTAnchor.NodeFingerprint.contentHash`, `CSTInspector`'s `CSTNodeDetails.contentHash`, `CSTInspectorView`'s hash display.
- `GreenSnapshotSerialization` now at format v3 (magic `CMBGRN03`); v1/v2 rejected on decode.

### 1b — `CambiumSource` rope
- `Sources/CambiumCore/CambiumSource.swift` — persistent B+tree-with-order-8 rope. Chunks up to 1024 bytes, UTF-8-boundary-respecting. Per-chunk and per-branch `Aggregates` (byteCount, utf16Count, lineCount, hash).
- Public API: `byteCount` / `utf16Count` / `lineCount` (O(1)), `applying(_ edits: [TextEdit])`, `utf16Offset(forByte:)` / `byteOffset(forUTF16:)` / `lineColumn(forByte:)` / `byteOffset(forLine:column:)` (O(log N)), `substring(in:)`, `makeChunkIterator()`, `withContiguousUTF8(_:)`, `toString()`, `contentHash`, `contentHash(in:)`.
- `TextEdit` moved from CambiumIncremental to CambiumCore (it's a fundamental byte-range type both layers need).

### 1c — Persistent splice
- `applying(_:)` no longer rebuilds the whole tree per edit. Real `split(at:) -> (RopeBranch, RopeBranch)` + `concat(_:_:)` on RopeBranch, with split-split-concat-concat composition. O(log N + edit_size) per edit.
- Lazy rebalance heuristic: full rebuild via `RopeBranch.balanced(fromChunks:)` if tree depth exceeds `2·log₈(chunkCount) + 4`. Rarely fires under realistic workloads; depth-bound property test (10,000 prepends) confirms.

### 1d — Polynomial hash unification
- `Sources/CambiumCore/PolynomialHash.swift` — two-polynomial Rabin-Karp fingerprints (bases 131 + 137 mod Mersenne M₆₁). `PolyHash.combine(of(a), of(b)) == of(a ++ b)` (composition property).
- Both green tree and rope use polynomial. `ContentHasher` public API unchanged; SHA-256/CryptoKit backing replaced with polynomial.
- `Aggregates` regained its `hash: PolyHash` field. `RopeBranch.contentHash` is now a one-line stored-field read — no lazy cache, no `NSLock`. Always O(1), always current.
- `CambiumSource.contentHash` is honestly O(1) — querying it after an edit takes microseconds, not the ~3 ms an SHA-256 rescan would have taken.

### `ParseInput.Buffer` enum (additive)
- `Sources/CambiumIncremental/IncrementalParsing.swift` — `ParseInput<Lang>` now holds a `Buffer` enum:
  ```swift
  public enum Buffer: Sendable {
      case flat([UInt8])
      case source(CambiumSource)
  }
  ```
- All convenience inits preserved: `init(textUTF8:...)` and `init(text:...)` produce `.flat`; new `init(source:...)` produces `.source`.
- `Buffer.withContiguousUTF8(_:)` extension makes the variant choice transparent to parsers that don't want chunked ingest — they call it and treat the rope and flat-array paths identically.

### Worked example
- `Examples/Calculator/Sources/CalculatorCore/CalculatorSession.parse(source:edits:)` — demonstrates the `.source` ingest path, bridging into the existing String-based lexer via `Buffer.withContiguousUTF8`. Comment notes that a production parser with a streaming lexer (Liminal) can consume `rope.makeChunkIterator()` directly.

---

## Goal of Phase 2

Migrate Liminal to use `CambiumSource` as the source-storage primitive. This:

1. **Fixes the 17 documented hotspots** in `/Users/dai/code/cambium/Docs/rope_source_storage.md` (especially the per-keystroke ones: forest-mark overlay walking hundreds of MB per keystroke on large docs).
2. **Replaces `LiminalEditorSession.source: String`** with `CambiumSource`, eliminating the O(N) full-buffer rewrite on every edit (`Liminal/Editor/LiminalEditor.swift:182–196` `applyingEdits`).
3. **Threads rope through the parser** via `ParseInput.Buffer.source(_:)`.
4. **Sets up Phase 3 (commit graph)** — undo snapshots can hold a `CambiumSource` cheaply (persistent + always-current contentHash); commits will key by `tree.contentHash` with a rope's `contentHash` as a parallel fingerprint of source bytes.

---

## Liminal's current state (what needs to change)

### The source-of-truth field
`Liminal/Editor/LiminalEditor.swift:26`:
```swift
public private(set) var source: String
```
Set at construction, replaced wholesale on every `applyTextEdits` call (line 90). This is the load-bearing change — the field type changes to `CambiumSource`.

### The 17 hotspots
Full table in `/Users/dai/code/cambium/Docs/rope_source_storage.md` (Section "Concrete Liminal hotspots"). Briefly:

**🔥 Per-keystroke / per-render (the urgent ones):**
1. `LiminalTextView.swift:2480` (`applyHighlights`) — builds `OffsetMap`, full-tree highlight
2. `CSTInspector.swift:148–155` (`makeCursorPosition`) — linear scan from byte 0 to cursor
3. `DocumentIndexBuilder.swift:37–93` (`snippet()`) — byte-by-byte UTF-8 walk per reference
4. `LiminalTextView.swift:327–363` (`refreshMarkIndicators`) — O(M × N) per render
5. `LiminalTextView.swift:2282–2350` (`mirrorCSTSelection`) — same shape

**🌡️ Per-command / per-motion:**
6–13. (See original doc for full list)

**❄️ Cold paths (worth fixing after the hot ones):**
14–17. (See original doc)

The **central refactor** that makes most hotspots fall out for free: `Liminal/App/LiminalTextView.swift:2655` `byteRangeToNSRange` and its inverse `utf16RangeToByteRange`. Today they each call `String.utf8.index(_:offsetBy:)` twice — O(N) per call. Replacing both with rope queries (`source.utf16Offset(forByte:)` / `source.byteOffset(forUTF16:)`) drops them to O(log N), and the dozen-plus call sites inherit the improvement automatically.

### Cambium-side files Liminal will interact with (read-only orientation)
- `/Users/dai/code/cambium/Sources/CambiumCore/CambiumSource.swift` — the rope type
- `/Users/dai/code/cambium/Sources/CambiumIncremental/IncrementalParsing.swift` — `ParseInput.Buffer`
- `/Users/dai/code/cambium/Examples/Calculator/Sources/CalculatorCore/CalculatorSession.swift` (`parse(source:edits:)`) — ingest pattern reference

---

## Migration playbook

Follow in order — each step is independently verifiable; don't proceed until the previous step's tests pass.

### Step 1 — `LiminalEditorSession.source: String` → `CambiumSource`
**File:** `Liminal/Editor/LiminalEditor.swift`

Change the field type and all initializers/setters. The five sites where `self.source = newSource` appears (or similar) become `self.source = CambiumSource(newSource)` where `newSource` is the post-edit content — but the inner shape changes too:

- The `applyingEdits` helper at line 182–196 (full-buffer materialization) **goes away** entirely. Replace with `self.source = try self.source.applying(edits)`. This alone eliminates the largest per-edit O(N) cost.
- Any caller reading `session.source` expects a `String`. Either:
  - Keep an explicit `var sourceString: String { source.toString() }` for back-compat during the migration, then phase out gradually
  - Or change call sites to consume `CambiumSource` directly (preferred — the whole point is to query positionally without materializing)

**Verify:** All Liminal tests still pass. Some will get slower (because `sourceString` round-trips through `toString()`) — that's OK, the per-call-site fixes in later steps undo this.

### Step 2 — Pass rope to parser via `ParseInput.Buffer.source(_:)`
**Files:** `Liminal/Syntax/LiminalSyntax.swift` (`LiminalParseSession.parse(...)`), `Liminal/Syntax/LiminalCSTParser.swift`

Change the parse path to take `CambiumSource` and construct `ParseInput(source: ...)`. Then either:

- **Quick win**: keep `LiminalCSTParser`'s lexer String-based, bridge via `input.buffer.withContiguousUTF8 { ... }`. Same pattern Calculator uses. Phase 2 ships; chunk-streaming lexer is a follow-up.
- **Full integration**: rewrite the lexer to consume `rope.makeChunkIterator()` directly. Bigger change; can defer.

Recommend the quick win for Phase 2; mark the streaming lexer as a follow-up TODO with a doc comment.

**Verify:** All Liminal tests still pass. The parse path now goes `ParseInput.Buffer.source` → `withContiguousUTF8` bridge → existing String-based lexer.

### Step 3 — Rewrite `byteRangeToNSRange` and `utf16RangeToByteRange`
**File:** `Liminal/App/LiminalTextView.swift`

These two static functions are the bottleneck for hotspots #4, #5, #11, #12, #13. Today they walk the String byte-by-byte; under the rope they become:

```swift
static func byteRangeToNSRange(_ range: TextRange, in source: CambiumSource) -> NSRange? {
    let start = source.utf16Offset(forByte: range.start)
    let end = source.utf16Offset(forByte: range.end)
    return NSRange(location: start, length: end - start)
}

static func utf16RangeToByteRange(_ nsRange: NSRange, in source: CambiumSource) -> TextRange? {
    let startByte = source.byteOffset(forUTF16: nsRange.location)
    let endByte = source.byteOffset(forUTF16: nsRange.location + nsRange.length)
    return TextRange(start: startByte, end: endByte)
}
```

(Adapt signatures based on whether callers can hand in `CambiumSource` directly vs needing the bridge from a String — see Step 1 decision.)

**Verify:** All Liminal tests still pass. The 11+ call sites in `LiminalTextView.swift` that touch these helpers now run O(log N) instead of O(N). Forest-mark-overlay refresh on a multi-MB doc should be visibly fast (the original motivating user complaint).

### Step 4 — Delete `OffsetMap`
**File:** `Liminal/App/OffsetMap.swift`

This type was Liminal's hand-rolled "byte ↔ UTF-16 cache for one highlight pass." The rope's translation queries make it redundant. Update `applyHighlights` (hotspot #1) to query the rope directly; delete the file.

**Verify:** `applyHighlights` full-doc fallback no longer allocates an `OffsetMap`. Liminal tests pass.

### Step 5 — Address targeted hotspots #2, #3, #6–#10, #14–#17
Each is a single-function rewrite, mostly mechanical:
- `CSTInspector.makeCursorPosition` → `source.lineColumn(forByte:)`
- `DocumentIndexBuilder.snippet()` → `source.substring(in:)` (no more byte-by-byte continuation scanning + `Array(sourceUTF8[lower..<upper])` slicing)
- `visual-block lineAndColumn` → `source.lineColumn(forByte:)`
- `CursorMotionEngine.offsetForLine` → `source.byteOffset(forLine:column:)`
- `CursorMotionEngine.verticalMove` → rope line aggregates instead of AppKit's `getLineStart` loop
- `HoverPreviewController` slice → `source.substring(in:)`
- The four `utf8.index(_:offsetBy:)` cold-path call sites (vault cache, CST clipboard, paste planner, list source) → rope queries

These can land in one commit each or batched; reviewer's choice.

**Verify:** Per the per-hotspot "What helps" column in the original doc, each call site drops to its target complexity.

### Step 6 — Run full Liminal test suite + benchmarks
Existing baseline: ~1006 tests passing (per the rope plan's reference point on commit `54a51df`). After Phase 2, **all should still pass with no semantic changes**. The change is purely performance-shaped.

For per-keystroke benchmarks (not currently in the suite but worth adding):
- Forest-mark refresh on a 1 MB markdown doc: should be sub-millisecond (was hundreds of MB of string walking per keystroke on 10 MB docs — pathological on the existing implementation).
- Single-byte edit on a 1 MB doc: should be sub-millisecond end-to-end.
- `:Reload` re-parse of a 10 MB doc: should be measurably faster.

---

## What's deliberately **not** in Phase 2

- **`SharedSyntaxTree` holding/borrowing `CambiumSource`.** The tree currently doesn't own source bytes — it reconstructs via `sourceText()` from token interner state. Migrating the tree to hold a rope reference is a wider ownership change touching every tree-creation site; Phase 2 keeps the rope owned by `LiminalEditorSession` and passes it into parses explicitly via `ParseInput.Buffer.source`.
- **Wiring rope chunk hashes into token `contentHash` construction.** This optimization was enabled by Phase 1d's polynomial unification (the token hash can be derived in O(1) from `rope.contentHash(in: tokenRange)` plus kind/length metadata). The win is real but small (~5 ms on 10 MB initial parse); land it as a separate optimization pass after Phase 2 ships, if profiling motivates it.
- **Streaming-lexer rewrite for `LiminalCSTParser`.** The Calculator worked example bridges via `withContiguousUTF8` for simplicity. Liminal can do the same for Phase 2 and rewrite the lexer to consume `rope.makeChunkIterator()` in a follow-up if profiling shows the bridge's transient `[UInt8]` copy matters.
- **Commit graph / version control.** That's Phase 3.

---

## Risks and pitfalls

### Discovered during Cambium-side work — read these before starting Phase 2

1. **Two ropes with the same content always have equal `contentHash`** — this is the property the polynomial unification (Phase 1d) was specifically designed to give. Cross-build-path equality, encode/decode round-trip, and incremental-vs-one-shot equivalence are all validated. Don't second-guess and add byte comparisons where hash comparison suffices.

2. **`CambiumSource.contentHash` is honestly O(1)** — no lazy cache, no first-access penalty. Query freely.

3. **`==` on `CambiumSource` is three-tier**: pointer (`===` on the root), then `byteCount` mismatch fast-fail, then `contentHash` compare. The byteCount fast-fail catches the "obviously not equal" case in O(1); don't add another length check.

4. **`Hashable` on `CambiumSource` hashes by `contentHash`** — safe to use as a Dictionary key. Two byte-equal ropes from different allocations end up in the same bucket.

5. **Persistent rope share storage** — holding multiple `CambiumSource` values from an edit chain costs roughly the byte delta, not N copies. Undo snapshots will benefit from this in Phase 3.

6. **Edit batches must be in descending-start order, non-overlapping** — `CambiumSourceEditError` thrown on contract violation. Matches `LiminalEditorSession.applyingEdits`'s existing contract, so Liminal's edit batches already satisfy this; just preserve the ordering when migrating.

7. **UTF-8 chunk boundaries are respected** — `Chunk.split(bytes:capacity:)` never splits mid-codepoint. The rope handles arbitrary UTF-8 input correctly (validated by emoji/CJK/combining-marks tests). Edits must arrive byte-aligned per Cambium's existing contract.

8. **Calculator example showed a stack-overflow risk in deep expressions** — when first testing the rope-based ingest with a 256-segment chained arithmetic expression, the recursive-descent parser blew the stack. Calculator's case is artificial; Liminal's markdown parser shouldn't have an analogous issue, but worth keeping in mind for any future synthetic benchmarks.

### Things the rope plan flagged that are still relevant

(From the original `rope_source_storage.md`, Section "Risks and migration notes"):

1. **Parser ingest is the hardest part** — but Phase 1b's `ParseInput.Buffer.flat([UInt8])` path is preserved as a fallback, so Liminal can take the bridge route initially (Step 2's "Quick win") and only commit to the streaming lexer rewrite when ready.

2. **Memory characteristics change** — the rope has per-chunk overhead (~64 bytes for leaf struct + branch nodes). For very small docs (<1 KB), the rope is *less* memory-efficient than a flat String. Measure on realistic notes; only an issue for tens-of-thousands-of-tiny-files workloads.

3. **Anchor stability** — `ForestAnchor.parentPath` / `CSTAnchor.path` are tree paths, not byte offsets — unaffected by the source migration. Byte-range fields (`textRange`) are unaffected too; they still index into the rope.

4. **Undo snapshots include the source** — with the persistent rope, snapshots become cheap by construction. This is what Phase 3 (commit graph) builds on.

5. **A handful of Liminal tests compare `session.source == "..."` against literals** — under the migration, this becomes `session.source.toString() == "..."`. Trivial update.

---

## Verification at the end

Phase 2 is done when:

1. **All Liminal tests pass** (~1006 baseline).
2. **`LiminalEditorSession.source` is `CambiumSource`** (no `String` field for source-of-truth).
3. **The five per-keystroke hotspots (#1–#5) are at their target complexity.** Spot-check by reading the call sites; they should all funnel through rope queries.
4. **`OffsetMap` is deleted.**
5. **`byteRangeToNSRange` / `utf16RangeToByteRange` are rope-backed** (O(log N)).
6. **`applyingEdits` in `LiminalEditor.swift` is gone**; its replacement is one line: `self.source = try self.source.applying(edits)`.
7. **Per-keystroke benchmark on a 1 MB markdown doc with 50 marks**: forest-mark refresh under 10 ms (was hundreds of ms on the prior implementation per the original symptom).

---

## Pointers

- **Cambium foundation plan** (full context, decision history): `/Users/dai/.claude-personal/plans/ok-1-xxh3-128-sounds-splendid-thacker.md`
- **Original rope plan** (per-hotspot detail, full design rationale): `/Users/dai/code/cambium/Docs/rope_source_storage.md`
- **`CambiumSource` source**: `/Users/dai/code/cambium/Sources/CambiumCore/CambiumSource.swift`
- **`ParseInput.Buffer` source**: `/Users/dai/code/cambium/Sources/CambiumIncremental/IncrementalParsing.swift`
- **Calculator worked example**: `/Users/dai/code/cambium/Examples/Calculator/Sources/CalculatorCore/CalculatorSession.swift` (`parse(source:edits:)`)
- **Polynomial hash primitives** (reference, not directly used by Liminal): `/Users/dai/code/cambium/Sources/CambiumCore/PolynomialHash.swift`
- **CambiumSource tests** (reference for rope semantics): `/Users/dai/code/cambium/Tests/CambiumCoreTests/CambiumSourceTests.swift`
- **Liminal hotspot sites** (to be modified): `/Users/dai/code/liminal-next/liminal/Liminal/App/LiminalTextView.swift` (most), `Liminal/Editor/LiminalEditor.swift`, `Liminal/Editor/CSTInspector.swift`, `Liminal/Editor/CursorMotionEngine.swift`, `Liminal/Workspace/DocumentIndexBuilder.swift`, `Liminal/App/HoverPreviewController.swift`, `Liminal/App/OffsetMap.swift` (delete).

---

## Notes for the next session

- Cambium is at format v3 (polynomial-backed `ContentHash`). Liminal doesn't persist any commits yet, so there's no v2→v3 migration to do on the Liminal side.
- The Liminal test suite was at **1006 passing tests** when the rope plan was first written. Cambium-side foundation work didn't change this number; that's still the baseline.
- The user has consistently prioritized **elegant architecture + correctness** over implementation effort. They explicitly approved bumping the format version twice during the Cambium foundation work rather than carrying compat shims. Phase 2 doesn't need any new format bumps but is free to make similar architectural calls.
- The user has indicated **commits are explicit (never automatic)** — Phase 2 doesn't introduce commits, but keep this in mind when designing follow-on undo-snapshot interactions: the rope is cheap to snapshot, but a snapshot isn't a commit.
- **17 hotspots already pre-investigated** — the original rope plan's hotspot table is the authoritative list, with per-site complexity targets ("What helps" column). Use it as the verification checklist, not a starting point for re-investigation.
