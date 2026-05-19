# Phase 2 — Completion notes + lingering items

Phase 2 (Cambium rope migration in Liminal) shipped across three PRs covering Steps 1–6 and all 17 hotspots from the rope plan. This doc catalogs what's left, what was closed, and what to watch for in future work.

**Status as of completion:** 1009/1009 Liminal tests pass. 238/238 Cambium tests pass. Forest-mark refresh benchmark: 3.98 ms on 1.2 MB stress fixture (target was < 10 ms).

---

## Open action items

### 1. Verify Landmine 1: full-document highlight perf
**What:** `applyHighlights(scope: .fullDocument)` no longer pre-builds a UTF-8↔UTF-16 cache. It now does M rope queries (one per highlight span), each O(log N). Pre-rewrite did one O(N) `OffsetMap` build + O(1) per-span lookup.

**Why this might be a real regression:** for the stress fixture (1.2 MB, ~233k spans on full-doc), back-of-envelope math is ambiguous — rope queries have higher per-call constant factors but no upfront build cost. The crossover point depends on the OffsetMap ASCII fast path (which synthesized answers without a table for pure-ASCII docs) — for highly ASCII content, pre-rewrite was essentially O(1) build + O(M) lookups, in which case rope is meaningfully slower.

**When this path fires:** initial document load, `EditorPreferences.highlightingEnabled` toggle, programmatic source replace (`replaceSource`). NOT per-keystroke (`.parserDirtyRange` with a `changed` range goes through a scoped paint with M ≈ 14-93, where rope wins decisively).

**Recommendation:** add a benchmark variant to `PerfSanityCheckTests` that times `applyHighlights(scope: .fullDocument)` on the stress fixture. If it's > ~30 ms, restore a full-doc OffsetMap-equivalent cache for that scope only (keeping per-edit scoped paint on rope). If it's < 10 ms, ignore.

**Priority:** medium. Affects cold-load UX on large docs but not interactive perf.

### 2. `applyTextEdits` contract change (deliberate but undocumented externally)
**What:** Pre-migration, `LiminalEditorSession.applyTextEdits([TextEdit])` internally sorted edits in descending order. Post-migration, it requires the caller to supply edits in descending order and throws `CambiumSourceEditError.unorderedOrOverlapping` otherwise.

**Status:** the contract change matches the rope's contract, but it's a public API behavior change. The `multiEditOrdering` test that previously locked in "any order accepted" was deleted.

**Recommendation:** if this codebase has any convention for documenting public API changes (a CHANGELOG, release notes, etc.), capture it. If not, this is just a code-comment-level concern (already in `LiminalEditor.swift`'s doc comment).

**Priority:** low. No known external consumers; Liminal's internal call sites all pass single-edit batches or already-sorted lists.

---

## Flagged but probably-not-actionable

### 3. Landmine 2: `StructuralCSTListSource.listItemContentRemovalRanges` near-start regression
**Concern:** pre-rewrite did two `utf8.index(_:offsetBy:)` walks (O(selectedStartByte) and O(selectedEndByte)). Post-rewrite does one `Array(source.utf8)` materialization (O(N)). For pathological case (large source, selection near byte 0), the new code is asymptotically slower in absolute terms.

**Why it's likely not actionable:** the function operates on FRAGMENT text — a list item being copied or pasted. Fragments are typically paragraph-sized. The pathological case (copying a giant list item from a 1MB doc) is implausible.

**Recommendation:** **don't add defensive code preemptively.** Document the limitation here. If profiling ever shows it firing in real use, add a small-near-edge heuristic that falls back to walks.

**Priority:** none unless someone hits it.

### 4. CambiumSource `bytes(in:)` API addition
**What I did:** added `public func bytes(in range: TextRange) -> [UInt8]` to `CambiumSource` to support `DocumentIndexBuilder.snippet`'s continuation-byte boundary walking. Was previously a private `appendBytes` internal helper.

**Why I flagged it:** I added the API unilaterally without asking. It expands Cambium's public surface area.

**Honest assessment:** the addition is small, semantically obvious, and parallel to the existing `substring(in:)` (just returns raw bytes instead of String). The justification (continuation-byte inspection requires raw bytes, since `substring(in:)` inserts U+FFFD for mid-char cuts) is sound. No good reason to revert.

**Recommendation:** ratify or revert. If ratifying, no further action.

**Priority:** none beyond confirming the ratification.

### 5. Rope line-counting vs. NSString line-counting in `visual-block` motion (Hotspot #7)
**What:** `lineAndColumn(forUTF16:in:source:)` was rewritten to use `source.lineColumn(forByte:)`. The rope counts only `\n` byte breaks. NSString's `getLineStart` recognizes `\n`, `\r`, CRLF, U+2028 (LINE SEPARATOR), U+2029 (PARAGRAPH SEPARATOR), and NEL.

**Why it's likely not actionable:** Liminal's documents are markdown — typically `\n`-only. CRLF support matters for cross-platform but matches between rope and NSString (rope counts CRLF as one break too). The exotic separators (U+2028, U+2029, NEL) almost never appear in real markdown.

**Recommendation:** documented in the code comment at the function. No further action unless a user reports visual-block selection misbehavior on a doc with exotic separators.

**Priority:** none.

### 6. Per-call rope build in `StructuralCSTSelectionProjection.logicalText` (Hotspot #15 fix)
**What:** the fix builds `CambiumSource(source)` once per `logicalText` call, then slices via `substring(in:)` for each removal range.

**Why I flagged it:** the rope build is O(N) per call. For `logicalText` calls with 0 or 1 removal ranges (degenerate cases), it's overhead vs. the original walks.

**Honest assessment:** the function early-returns when `removalRanges.isEmpty`, so the 0-range case doesn't pay the cost. The 1-range case is rare; typical projections have multiple removals (one per affected line). Net: build amortizes in practice.

**Recommendation:** no action.

### 7. HoverPreviewController per-slice CambiumSource builds
**What:** `buildAttributedString` builds `CambiumSource(sliceText)` once per hover, for span translation. `computeSliceRange` and `sliceContent` now take `CambiumSource`.

**Why I flagged it:** rope build per hover.

**Honest assessment:** hover slices are paragraph-sized (12-line / 2048-byte cap). Rope build cost is microseconds. Hover is rare (one per user hover event). Imperceptible.

**Recommendation:** no action.

---

## Closed / resolved

### 8. CursorMotionEngine dual rope/NSString paths
**Was:** opt-in `source: CambiumSource?` with default-nil fallback. Created two code paths, dead-in-production but live-in-tests.

**Resolution:** **fixed by user post-completion.**

### 9. `byteOffset(forUTF16:)` round-trip guard in Liminal
**Was:** `utf16RangeToByteRange` did two extra rope queries per call to detect surrogate-mid input and return nil. Could have been a Cambium-side check.

**Resolution:** **fixed by user post-completion** (presumably lifted into Cambium's API itself or otherwise restructured).

### 10. Cambium `chunkByteOffset` mid-character return bug
**Was:** `byteOffset(forUTF16:)` returned positions inside multi-byte UTF-8 sequences for inputs landing right after a multibyte char (e.g., utf16=2 on "héllo" returned byte 2 — mid-é — instead of byte 3).

**Resolution:** Cambium-side fix in `chunkByteOffset` advances past continuation bytes when the target is reached. Regression test added: `byteOffsetForUTF16AfterMultiByteChar` covers 2-byte (é), 3-byte (CJK), and 4-byte (emoji) cases.

**Note for future Cambium consumers:** this is a semantic change to `byteOffset(forUTF16:)`. Calculator example tests pass (no observable impact). Any future Cambium adopter that depended on the OLD (broken) behavior would see different return values — flag at adoption time.

### 11. The 17 hotspots themselves
All addressed. Per the retrospective in our session log.

---

## Cambium-side notes (for future consumers)

1. **`byteOffset(forUTF16:)` advances past continuation bytes.** Confirmed correct via the new regression test. Document this in the API doc-comment if not already.
2. **`bytes(in:)` is a public API** as of this work. Use it (not `substring(in:)`) when raw bytes are needed for boundary inspection.
3. **The polynomial hash family** is unchanged by Phase 2. Content-stable equality and O(1) `contentHash` queries are the foundation Phase 3 (commit graph) builds on.

---

## Phase 3 entry criteria

The deferred items above do NOT block Phase 3 (Liminal commit graph in-memory, per the umbrella plan at `~/.claude-personal/plans/ok-1-xxh3-128-sounds-splendid-thacker.md`). Specifically:

- The rope foundation is stable.
- `LiminalEditorSession.source: CambiumSource` is the source-of-truth and gives cheap snapshots for undo via structural sharing.
- All per-keystroke hot paths are O(log N).
- The cold-path landmines flagged above don't affect Phase 3's design.

Recommended: address item 1 (full-doc highlight benchmark) before Phase 3 if cold-load UX matters; otherwise proceed.
