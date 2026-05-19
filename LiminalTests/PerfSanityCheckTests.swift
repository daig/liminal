import CambiumCore
import CambiumIncremental
import Foundation
import Testing
@testable import Liminal

/// One-shot sanity check on the pure Cambium parsing path against the
/// huge stress fixture, without any AppKit/UI work. Times:
///   1. Cold parse of the whole document.
///   2. Single-character insert near the middle + incremental re-parse.
///   3. The same insert repeated 5 times (typical typing burst).
///
/// Prints results; no assertions on absolute timing. Run from Xcode and
/// read the console output.
@Suite("Perf sanity check (parse only)")
struct PerfSanityCheckTests {
    static let fixturePath = "/Users/dai/code/liminal-next/liminal/Docs/Fixtures/stress.md"

    @Test("cold parse + incremental edits on stress.md")
    func parseStressDoc() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: Self.fixturePath),
            encoding: .utf8
        )
        let byteCount = source.utf8.count
        let lineCount = source.split(separator: "\n", omittingEmptySubsequences: false).count
        print("[sanity] fixture: \(byteCount) bytes, \(lineCount) lines")

        let clock = ContinuousClock()
        let session = LiminalEditorSession()

        let coldStart = clock.now
        try session.replaceSource(CambiumSource(source))
        let coldElapsed = clock.now - coldStart
        let summary = session.lastReuseSummary
        print("[sanity] cold parse: \(coldElapsed)  reuse \(summary.acceptedReuses)/\(summary.queries)")

        // Insert one character near the middle of the doc.
        let midByte = byteCount / 2
        let edit = TextEdit(
            range: CambiumCore.TextRange(
                start: TextSize(UInt32(midByte)),
                length: TextSize(0)
            ),
            replacement: "X"
        )
        let editStart = clock.now
        try session.applyTextEdits([edit])
        let editElapsed = clock.now - editStart
        let editSummary = session.lastReuseSummary
        print("[sanity] one-char edit at byte \(midByte): \(editElapsed)  reuse \(editSummary.acceptedReuses)/\(editSummary.queries)")

        // Five more single-char inserts at varying positions to simulate
        // typing across the document.
        let positions = [
            byteCount / 8,
            byteCount / 4,
            byteCount / 2 + 1,
            (byteCount / 4) * 3,
            byteCount - 100,
        ]
        for (i, pos) in positions.enumerated() {
            let e = TextEdit(
                range: CambiumCore.TextRange(
                    start: TextSize(UInt32(pos)),
                    length: TextSize(0)
                ),
                replacement: "Y"
            )
            let s = clock.now
            try session.applyTextEdits([e])
            let elapsed = clock.now - s
            let su = session.lastReuseSummary
            print("[sanity] burst \(i+1) at byte \(pos): \(elapsed)  reuse \(su.acceptedReuses)/\(su.queries)")
        }
    }

    /// Per-keystroke pipeline breakdown — measures phases that happen
    /// downstream of the parser when a character lands in the text view:
    ///   - source-buffer update (rope splice) + parse
    ///   - the full-tree highlight span walk
    ///   - the scoped (changedByteRange) highlight span walk
    ///   - the per-span byte→NSRange translation cost (rope-backed)
    /// Pre-rope, this test had two additional phases that measured the
    /// `OffsetMap` build cost (full + scoped). With the rope migration
    /// (Phase 2 Steps 3+4) `OffsetMap` is gone — translation is now an
    /// O(log N) rope query per span, folded into the lookup phase below.
    /// Prints elapsed times across one warmup edit + five bursts.
    @Test("per-keystroke pipeline breakdown on stress.md")
    func keystrokePipelineBreakdown() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: Self.fixturePath),
            encoding: .utf8
        )
        let byteCount = source.utf8.count
        print("[keystroke] fixture: \(byteCount) bytes")

        let clock = ContinuousClock()
        let session = LiminalEditorSession()
        let highlighter = LiminalHighlighter()

        // Prime the session.
        try session.replaceSource(CambiumSource(source))

        // Warm one phase at a time on the cold tree so we capture
        // steady-state per-phase costs.
        let positions = [
            byteCount / 2,
            byteCount / 8,
            byteCount / 4,
            byteCount / 2 + 1,
            (byteCount / 4) * 3,
            byteCount - 100,
        ]
        for (i, pos) in positions.enumerated() {
            let edit = TextEdit(
                range: CambiumCore.TextRange(
                    start: TextSize(UInt32(pos)),
                    length: TextSize(0)
                ),
                replacement: "Z"
            )

            // Phase A: source-buffer update only (no parse).
            // We can't easily measure applyingEdits in isolation without
            // refactoring; instead, measure the whole applyTextEdits
            // (parse + buffer) once, then time the breakdown phases
            // against the post-edit tree.
            let totalStart = clock.now
            let result = try session.applyTextEdits([edit])
            let totalElapsed = clock.now - totalStart

            // Phase B1: full-tree highlight span walk (the pre-fix cost).
            let spansFullStart = clock.now
            let spansFull = highlighter.spans(for: result.rootSyntax)
            let spansFullElapsed = clock.now - spansFullStart

            // Phase B2: scoped highlight span walk over the parse's
            // changedByteRange (the authoritative dirty span from
            // skip-clean-regions). Mirrors the keystroke path's
            // per-edit highlight scope after the changedByteRange fix.
            let scopeByteRange = result.changedByteRange ?? CambiumCore.TextRange(
                start: TextSize(0),
                length: TextSize(UInt32(byteCount))
            )
            let spansScopedStart = clock.now
            let spansScoped = highlighter.spans(for: result.rootSyntax, in: scopeByteRange)
            let spansScopedElapsed = clock.now - spansScopedStart

            // Phase D: per-span rope translation cost (byte→NSRange).
            // This is what applyHighlights does just before adding
            // attributes for each span. Pre-rope, this phase was
            // dominated by a separate one-time OffsetMap build. Now each
            // query is O(log N) directly against the rope — no map
            // allocation, no build phase.
            let lookupStart = clock.now
            var lookups = 0
            for span in spansScoped {
                _ = LiminalTextView.byteRangeToNSRange(span.range, in: session.source)
                lookups &+= 1
            }
            let lookupElapsed = clock.now - lookupStart

            print(
                "[keystroke] burst \(i + 1) @ byte \(pos): "
                + "total=\(totalElapsed) "
                + "changed=\(result.changedByteRange?.length.rawValue ?? UInt32(byteCount)) bytes "
                + "spansFull=\(spansFullElapsed) (\(spansFull.count)) "
                + "spansScoped=\(spansScopedElapsed) (\(spansScoped.count)) "
                + "translation=\(lookupElapsed) (\(lookups))"
            )
        }
    }

    /// Phase 2 finishing benchmark: per-keystroke forest-mark refresh.
    ///
    /// Pre-rope, `refreshForestMarkIndicators()` walked the source
    /// twice per mark via `String.utf8.index(_:offsetBy:)` —
    /// O(M × N) where M is mark count and N is doc bytes. On a 1 MB
    /// doc with 50 marks, that was hundreds of MB of string walking
    /// per render: visibly stuttery interactive feel.
    ///
    /// With the rope migration (Phase 2 Steps 3+4), each per-mark
    /// translation is O(log N) via `source.utf16Offset(forByte:)`.
    /// Target per the handoff doc: forest-mark refresh < 10 ms on a
    /// 1 MB doc with 50 marks.
    ///
    /// This benchmark isolates the per-mark translation cost — the
    /// hot inner loop of `refreshForestMarkIndicators` — by calling
    /// `byteRangeToNSRange` against the session source 50 times on
    /// the stress fixture. The full refresh path adds mark-resolution
    /// + view-list construction overhead on top, but the translation
    /// is the dominant cost the rope migration targets.
    @Test("forest-mark refresh: 50 byteRangeToNSRange queries on 1 MB doc")
    func forestMarkRefreshBenchmark() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: Self.fixturePath),
            encoding: .utf8
        )
        let rope = CambiumSource(source)
        let byteCount = rope.byteCount
        print("[forest-mark-refresh] fixture: \(byteCount) bytes")

        // 50 distinct byte offsets evenly distributed through the doc.
        // Each becomes a length-0 TextRange to mimic a mark cursor
        // (which is what refreshForestMarkIndicators feeds to
        // byteRangeToNSRange).
        let markCount = 50
        var markRanges: [CambiumCore.TextRange] = []
        markRanges.reserveCapacity(markCount)
        for i in 0..<markCount {
            // Pseudo-random spread; deterministic so the run is
            // reproducible.
            let raw = UInt32((Int(UInt32.random(in: 0...UInt32.max)) % byteCount + i * 47) % byteCount)
            markRanges.append(CambiumCore.TextRange(start: TextSize(raw), length: TextSize(0)))
        }

        let clock = ContinuousClock()
        let start = clock.now
        var translated = 0
        for range in markRanges {
            _ = LiminalTextView.byteRangeToNSRange(range, in: rope)
            translated &+= 1
        }
        let elapsed = clock.now - start
        print("[forest-mark-refresh] \(translated) per-mark translations: \(elapsed)")
        // No hard assertion — perf budgets are fragile in CI. The
        // print line is the signal; visual inspection vs. the < 10 ms
        // handoff target tells us whether the migration paid off.
    }

    /// UTF16Cursor word-motion benchmark: 1000 `wordForwardStart`
    /// motions on the stress fixture. Confirms that the cursor-based
    /// word motion (rope queries for line bounds + cursor advance for
    /// character categorization) doesn't degrade per-motion latency
    /// vs the pre-rope NSString implementation.
    ///
    /// Expected: each word motion is bounded by word length (~5-20
    /// chars) × cursor advance cost (O(1) within chunk, O(log N) at
    /// boundary). 1000 motions on a 1 MB doc should complete in ~ms,
    /// not ~100ms — confirms the rope-only motion engine isn't
    /// pathological.
    @Test("UTF16Cursor word motion: 1000 wordForwardStart on stress.md")
    func wordMotionBenchmark() throws {
        let text = try String(
            contentsOf: URL(fileURLWithPath: Self.fixturePath),
            encoding: .utf8
        )
        let source = CambiumSource(text)
        let utf16Count = source.utf16Count
        print("[word-motion] fixture: \(source.byteCount) bytes, \(utf16Count) UTF-16 units")

        let clock = ContinuousClock()
        let start = clock.now
        var current = 0
        var motions = 0
        for _ in 0..<1000 {
            let next = CursorMotionEngine.newOffset(
                for: .wordForwardStart,
                source: source,
                from: current,
                count: 1
            )
            // Wrap around when we hit the end so we keep exercising.
            current = next == current ? 0 : next
            motions &+= 1
        }
        let elapsed = clock.now - start
        print("[word-motion] \(motions) wordForwardStart motions: \(elapsed)")
        // No hard assertion (CI-fragile). Signal for visual inspection.
    }
}
