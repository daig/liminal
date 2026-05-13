import Foundation
import Testing
@testable import Liminal

@Suite("PasteEngine")
struct PasteEngineTests {
    // MARK: - Characterwise

    @Test("characterwise p inserts after cursor; cursor on last char of paste")
    func charwiseAfter() {
        let plan = PasteEngine.plan(
            text: "XY", kind: .characterwise,
            in: "abc", cursor: 1, after: true
        )
        #expect(plan.range == NSRange(location: 2, length: 0))
        #expect(plan.replacement == "XY")
        // After paste: "abXYc"; cursor on 'Y' at position 3.
        #expect(plan.cursorAfter == 3)
    }

    @Test("characterwise P inserts at cursor; cursor on last char of paste")
    func charwiseBefore() {
        let plan = PasteEngine.plan(
            text: "XY", kind: .characterwise,
            in: "abc", cursor: 1, after: false
        )
        #expect(plan.range == NSRange(location: 1, length: 0))
        // After paste: "aXYbc"; cursor on 'Y' at position 2.
        #expect(plan.cursorAfter == 2)
    }

    @Test("characterwise p clamps to line content end (no crossing newline)")
    func charwiseClampsToContentEnd() {
        let plan = PasteEngine.plan(
            text: "Z", kind: .characterwise,
            in: "abc\ndef", cursor: 2, after: true
        )
        // contentEnd of first line is 3; cursor + 1 = 3 = contentEnd, OK.
        // Result: "abcZ\ndef"; cursor on 'Z' at 3.
        #expect(plan.range == NSRange(location: 3, length: 0))
        #expect(plan.cursorAfter == 3)
    }

    // MARK: - Linewise

    @Test("linewise p adds a new line below; cursor at line start")
    func linewiseAfter() {
        let plan = PasteEngine.plan(
            text: "ZZZ\n", kind: .linewise,
            in: "abc\ndef", cursor: 1, after: true
        )
        // Line containing cursor: contentEnd=3.
        // Insert "\nZZZ" at position 3.
        // Result: "abc\nZZZ\ndef"; cursor at start of inserted "ZZZ" (position 4).
        #expect(plan.range == NSRange(location: 3, length: 0))
        #expect(plan.replacement == "\nZZZ")
        #expect(plan.cursorAfter == 4)
    }

    @Test("linewise P adds a new line above; cursor at line start")
    func linewiseBefore() {
        let plan = PasteEngine.plan(
            text: "ZZZ\n", kind: .linewise,
            in: "abc\ndef", cursor: 5, after: false
        )
        // Line containing cursor (second line): start=4.
        // Insert "ZZZ\n" at 4.
        // Result: "abc\nZZZ\ndef"; cursor at 4 (start of inserted "ZZZ").
        #expect(plan.range == NSRange(location: 4, length: 0))
        #expect(plan.replacement == "ZZZ\n")
        #expect(plan.cursorAfter == 4)
    }

    @Test("linewise p at EOF appends a new line")
    func linewiseAfterEOF() {
        let plan = PasteEngine.plan(
            text: "ZZZ\n", kind: .linewise,
            in: "abc", cursor: 1, after: true
        )
        // Last line has no terminator; contentEnd=3, end=3.
        // Insert "\nZZZ" at 3 → "abc\nZZZ".
        #expect(plan.range == NSRange(location: 3, length: 0))
        #expect(plan.replacement == "\nZZZ")
        #expect(plan.cursorAfter == 4)
    }

    // MARK: - Blockwise

    @Test("blockwise p inserts a column at cursor.column + 1")
    func blockwiseAfter() {
        // Doc has three lines of 5 chars each. Cursor on line 0, column 1.
        // Block yank "XX\nYY\nZZ" should appear at columns 2..3 on each line.
        let plan = PasteEngine.plan(
            text: "XX\nYY\nZZ", kind: .blockwise,
            in: "abcde\nfghij\nklmno", cursor: 1, after: true
        )
        // Each line gets 2 chars inserted at column 2.
        // Expected new text: "abXXcde\nfgYYhij\nklZZmno".
        // The plan's replacement covers the whole 3-line span.
        let expected = "abXXcde\nfgYYhij\nklZZmno"
        let original = "abcde\nfghij\nklmno"
        let originalNS = original as NSString
        let resultNS = NSMutableString(string: original)
        resultNS.replaceCharacters(in: plan.range, with: plan.replacement)
        #expect(resultNS as String == expected)
        // Cursor at first inserted cell: column 2 of first row = position 2.
        #expect(plan.cursorAfter == 2)
        // Sanity: range covers all three original lines.
        #expect(plan.range.location == 0)
        #expect(plan.range.length == originalNS.length)
    }

    @Test("blockwise pads short target lines with spaces")
    func blockwisePadShort() {
        // Two lines: "ab" and "cdefgh". Cursor on line 0, column 1.
        // Block yank "XX\nYY" should appear at column 2..3.
        // Line 0 is too short (only 2 chars, needs to reach column 2);
        // padding gives "ab" + "" pad + "XX" + "" → "abXX".
        // Line 1 has plenty: "cd" + "YY" + "efgh" → "cdYYefgh".
        let plan = PasteEngine.plan(
            text: "XX\nYY", kind: .blockwise,
            in: "ab\ncdefgh", cursor: 1, after: true
        )
        let result = NSMutableString(string: "ab\ncdefgh")
        result.replaceCharacters(in: plan.range, with: plan.replacement)
        #expect(result as String == "abXX\ncdYYefgh")
    }
}
