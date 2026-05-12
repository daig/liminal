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
}
