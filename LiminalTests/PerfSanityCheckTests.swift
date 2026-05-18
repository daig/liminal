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

            // Phase C1: full-source OffsetMap build (pre-fix cost).
            let mapFullStart = clock.now
            let mapFull = OffsetMap(source: session.source.toString())
            let mapFullElapsed = clock.now - mapFullStart

            // Phase C2: scoped OffsetMap build over the dirty byte range.
            let scopeLower = Int(scopeByteRange.start.rawValue)
            let scopeUpper = scopeLower + Int(scopeByteRange.length.rawValue)
            let mapScopedStart = clock.now
            let mapScoped = OffsetMap(source: session.source.toString(), byteRange: scopeLower..<scopeUpper)
            let mapScopedElapsed = clock.now - mapScopedStart

            // Phase D: iterate scoped spans and look up nsRange via the
            // scoped map (mirrors what applyHighlights does just before
            // adding attributes).
            let lookupStart = clock.now
            var lookups = 0
            for span in spansScoped {
                _ = mapScoped.nsRange(
                    forByteStart: span.range.start.rawValue,
                    length: span.range.length.rawValue
                )
                lookups &+= 1
            }
            let lookupElapsed = clock.now - lookupStart

            _ = mapFull  // referenced so the build cost is included in mapFullElapsed

            print(
                "[keystroke] burst \(i + 1) @ byte \(pos): "
                + "total=\(totalElapsed) "
                + "changed=\(result.changedByteRange?.length.rawValue ?? UInt32(byteCount)) bytes "
                + "spansFull=\(spansFullElapsed) (\(spansFull.count)) "
                + "spansScoped=\(spansScopedElapsed) (\(spansScoped.count)) "
                + "mapFull=\(mapFullElapsed) "
                + "mapScoped=\(mapScopedElapsed) "
                + "lookups=\(lookupElapsed) (\(lookups))"
            )
        }
    }
}
