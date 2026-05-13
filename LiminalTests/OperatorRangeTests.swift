import Foundation
import Testing
@testable import Liminal

@Suite("OperatorRange")
struct OperatorRangeTests {

    // MARK: - Motion + exclusive (h/l/0/^/w/b)

    @Test("dw deletes a word and trailing whitespace")
    func dwExclusive() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.wordForwardStart),
            in: "abc def ghi", cursor: 0, count: 1
        )
        #expect(r.range == NSRange(location: 0, length: 4))
        #expect(r.kind == .characterwise)
    }

    @Test("3dw deletes three words")
    func dwCount() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.wordForwardStart),
            in: "a b c d e", cursor: 0, count: 3
        )
        // w from 0 jumps b->c->d (stops at 'd' at index 6).
        #expect(r.range == NSRange(location: 0, length: 6))
        #expect(r.kind == .characterwise)
    }

    @Test("d0 deletes from cursor back to line start (exclusive end)")
    func d0() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.lineStart),
            in: "    abc", cursor: 5, count: 1
        )
        // 0 returns 0; range = [0, 5).
        #expect(r.range == NSRange(location: 0, length: 5))
    }

    @Test("d^ deletes from cursor back to first non-blank")
    func dCaret() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.lineFirstNonBlank),
            in: "    abc", cursor: 6, count: 1
        )
        // ^ returns 4; range = [4, 6).
        #expect(r.range == NSRange(location: 4, length: 2))
    }

    @Test("db deletes from cursor backward to word start")
    func db() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.wordBackward),
            in: "abc def ghi", cursor: 8, count: 1
        )
        // b from 8 returns 4; range = [4, 8).
        #expect(r.range == NSRange(location: 4, length: 4))
    }

    // MARK: - Motion + inclusive (e)

    @Test("de includes the last char of the word")
    func deInclusive() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.wordForwardEnd),
            in: "abc def", cursor: 0, count: 1
        )
        // e from 0 returns 2 ('c'); inclusive: range = [0, 3).
        #expect(r.range == NSRange(location: 0, length: 3))
    }

    @Test("d$ deletes through line end without crossing the newline")
    func dDollar() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.lineEnd),
            in: "abc def\nghi", cursor: 0, count: 1
        )
        // contentEnd = 7 (newline position); range = [0, 7) — keeps "\nghi".
        #expect(r.range == NSRange(location: 0, length: 7))
    }

    // MARK: - cw → ce quirk (resolved upstream in the controller, but
    // verified here at the engine level — the controller substitutes
    // wordForwardEnd before calling resolve)

    @Test("cw is dispatched as ce, deleting the word's chars only")
    func cwAsce() {
        let r = OperatorRange.resolve(
            op: .change, target: .motion(.wordForwardEnd),
            in: "abc def", cursor: 0, count: 1
        )
        // Same range as `de`: [0, 3). The controller will then enter insert mode.
        #expect(r.range == NSRange(location: 0, length: 3))
        #expect(r.kind == .characterwise)
    }

    // MARK: - Motion + linewise (j / k / G / gg)

    @Test("dj deletes the current line and the next, full linewise range")
    func dj() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.down),
            in: "abc\ndef\nghi", cursor: 1, count: 1
        )
        // current line: [0, 4) (incl. '\n'); next line: [4, 8) (incl. '\n').
        // Linewise range: [0, 8).
        #expect(r.range == NSRange(location: 0, length: 8))
        #expect(r.kind == .linewise)
    }

    @Test("dG from mid-doc deletes from current line through last")
    func dG() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.documentEnd),
            in: "abc\ndef\nghi", cursor: 4, count: Int.max
        )
        #expect(r.range == NSRange(location: 4, length: 7))
        #expect(r.kind == .linewise)
    }

    @Test("cj keeps the line shell — drops trailing newline")
    func cjPreservesLineShell() {
        let r = OperatorRange.resolve(
            op: .change, target: .motion(.down),
            in: "abc\ndef\nghi", cursor: 1, count: 1
        )
        // Still [start of first line, contentEnd of second line) = [0, 7).
        #expect(r.range == NSRange(location: 0, length: 7))
        #expect(r.kind == .linewise)
    }

    // MARK: - currentLine target (dd / cc / yy)

    @Test("dd deletes the current line including its newline")
    func dd() {
        let r = OperatorRange.resolve(
            op: .delete, target: .currentLine,
            in: "abc\ndef\nghi", cursor: 1, count: 1
        )
        #expect(r.range == NSRange(location: 0, length: 4))
        #expect(r.kind == .linewise)
    }

    @Test("2dd deletes two lines including their newlines")
    func twoDD() {
        let r = OperatorRange.resolve(
            op: .delete, target: .currentLine,
            in: "abc\ndef\nghi", cursor: 1, count: 2
        )
        #expect(r.range == NSRange(location: 0, length: 8))
        #expect(r.kind == .linewise)
    }

    @Test("cc preserves the line shell (drops trailing newline)")
    func cc() {
        let r = OperatorRange.resolve(
            op: .change, target: .currentLine,
            in: "abc\ndef\nghi", cursor: 1, count: 1
        )
        // Range covers "abc" only, leaves the "\ndef\nghi" intact.
        #expect(r.range == NSRange(location: 0, length: 3))
        #expect(r.kind == .linewise)
    }

    @Test("yy yields the same range shape as dd; nothing is deleted by the engine itself")
    func yy() {
        let r = OperatorRange.resolve(
            op: .yank, target: .currentLine,
            in: "abc\ndef\nghi", cursor: 1, count: 1
        )
        #expect(r.range == NSRange(location: 0, length: 4))
        #expect(r.kind == .linewise)
    }

    @Test("dd on the last line (no trailing newline) covers from line start to end-of-doc")
    func ddLastLineNoNewline() {
        let r = OperatorRange.resolve(
            op: .delete, target: .currentLine,
            in: "abc\ndef", cursor: 5, count: 1
        )
        // Last line: start=4, contentEnd=7, end=7. Range = [4, 7).
        #expect(r.range == NSRange(location: 4, length: 3))
        #expect(r.kind == .linewise)
    }

    @Test("3dd with only 2 remaining lines clamps to what's available")
    func ddClamp() {
        let r = OperatorRange.resolve(
            op: .delete, target: .currentLine,
            in: "abc\ndef", cursor: 1, count: 3
        )
        // Two lines: [0, 4) + [4, 7) → [0, 7).
        #expect(r.range == NSRange(location: 0, length: 7))
    }

    // MARK: - charsAtCursor (x / X)

    @Test("x deletes the char at cursor")
    func xSingle() {
        let r = OperatorRange.resolve(
            op: .delete, target: .charsAtCursor(before: false),
            in: "hello", cursor: 1, count: 1
        )
        #expect(r.range == NSRange(location: 1, length: 1))
        #expect(r.kind == .characterwise)
    }

    @Test("3x deletes three chars at cursor")
    func xCount() {
        let r = OperatorRange.resolve(
            op: .delete, target: .charsAtCursor(before: false),
            in: "hello", cursor: 1, count: 3
        )
        #expect(r.range == NSRange(location: 1, length: 3))
    }

    @Test("x clamps to line content end (won't delete past a newline)")
    func xClampsAtNewline() {
        let r = OperatorRange.resolve(
            op: .delete, target: .charsAtCursor(before: false),
            in: "abc\ndef", cursor: 2, count: 5
        )
        // Line 0: contentEnd = 3. Range [2, 3) — only 'c'.
        #expect(r.range == NSRange(location: 2, length: 1))
    }

    @Test("X deletes the char before cursor")
    func XSingle() {
        let r = OperatorRange.resolve(
            op: .delete, target: .charsAtCursor(before: true),
            in: "hello", cursor: 4, count: 1
        )
        #expect(r.range == NSRange(location: 3, length: 1))
    }

    @Test("X with count clamps to line start")
    func XClampsAtLineStart() {
        let r = OperatorRange.resolve(
            op: .delete, target: .charsAtCursor(before: true),
            in: "abc\ndefgh", cursor: 6, count: 10
        )
        // Line 1: start = 4. Range [4, 6).
        #expect(r.range == NSRange(location: 4, length: 2))
    }

    // MARK: - toLineEnd (D / C)

    @Test("D deletes from cursor to line content end (excluding newline)")
    func D() {
        let r = OperatorRange.resolve(
            op: .delete, target: .toLineEnd,
            in: "abc def\nghi", cursor: 2, count: 1
        )
        // contentEnd = 7; range = [2, 7).
        #expect(r.range == NSRange(location: 2, length: 5))
    }

    @Test("C deletes the same range as D, kind characterwise")
    func C() {
        let r = OperatorRange.resolve(
            op: .change, target: .toLineEnd,
            in: "abc def\nghi", cursor: 2, count: 1
        )
        #expect(r.range == NSRange(location: 2, length: 5))
        #expect(r.kind == .characterwise)
    }

    // MARK: - Edge cases

    @Test("dw at end-of-buffer where motion can't advance: empty range, no edit")
    func dwAtEOF() {
        let r = OperatorRange.resolve(
            op: .delete, target: .motion(.wordForwardStart),
            in: "abc", cursor: 3, count: 1
        )
        // wordForwardStart from end stays at end (3). Range = [3, 3).
        #expect(r.range.length == 0)
    }

    @Test("dd on a single-line doc covers the whole text")
    func ddSingleLine() {
        let r = OperatorRange.resolve(
            op: .delete, target: .currentLine,
            in: "only line", cursor: 4, count: 1
        )
        #expect(r.range == NSRange(location: 0, length: 9))
    }

    @Test("Y yields linewise range identical to yy")
    func Y() {
        let r = OperatorRange.resolve(
            op: .yank, target: .currentLine,
            in: "abc\ndef\n", cursor: 1, count: 1
        )
        #expect(r.range == NSRange(location: 0, length: 4))
        #expect(r.kind == .linewise)
    }

    @Test("structural / display / viewport motion targets degrade to no-op")
    func unsupportedMotionDegrades() {
        let r = OperatorRange.resolve(
            op: .delete, target: .structuralMotion(.nextHeading),
            in: "abc", cursor: 1, count: 1
        )
        #expect(r.range.length == 0)
        #expect(r.kind == .characterwise)
    }
}
