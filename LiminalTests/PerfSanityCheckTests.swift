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
        try session.replaceSource(source)
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
    ///   - source-buffer update (applyingEdits + utf8/decode round-trip)
    ///   - the parse itself
    ///   - the full-tree highlight span walk
    ///   - the OffsetMap build (UTF-8 → UTF-16 lookup)
    /// Prints elapsed times for each phase across one warmup edit + five
    /// bursts so we can see which step dominates a real keystroke vs.
    /// what the parse-only test measures.
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
        try session.replaceSource(source)

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

            // Phase B2: scoped highlight span walk over a 1 KB byte window
            // centered on the edit — mirrors the keystroke path's
            // per-edit highlight scope.
            let scopeHalf = 512
            let lo = max(0, pos - scopeHalf)
            let hi = min(byteCount, pos + scopeHalf)
            let scopeByteRange = CambiumCore.TextRange(
                start: TextSize(UInt32(lo)),
                end: TextSize(UInt32(hi))
            )
            let spansScopedStart = clock.now
            let spansScoped = highlighter.spans(for: result.rootSyntax, in: scopeByteRange)
            let spansScopedElapsed = clock.now - spansScopedStart

            // Phase C: OffsetMap build over the new source.
            let mapStart = clock.now
            let map = OffsetMap(source: session.source)
            let mapElapsed = clock.now - mapStart

            // Phase D: iterate scoped spans and look up nsRange (mirrors
            // what applyHighlights does just before adding attributes).
            let lookupStart = clock.now
            var lookups = 0
            for span in spansScoped {
                _ = map.nsRange(
                    forByteStart: span.range.start.rawValue,
                    length: span.range.length.rawValue
                )
                lookups &+= 1
            }
            let lookupElapsed = clock.now - lookupStart

            print(
                "[keystroke] burst \(i + 1) @ byte \(pos): "
                + "total=\(totalElapsed) "
                + "spansFull=\(spansFullElapsed) (\(spansFull.count)) "
                + "spansScoped=\(spansScopedElapsed) (\(spansScoped.count)) "
                + "map=\(mapElapsed) "
                + "lookups=\(lookupElapsed) (\(lookups))"
            )
        }
    }
}
