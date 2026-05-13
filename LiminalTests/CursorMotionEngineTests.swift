import Foundation
import Testing
@testable import Liminal

@Suite("CursorMotionEngine")
struct CursorMotionEngineTests {

    // MARK: - Cardinal

    @Test("left clamps at 0")
    func leftClamps() {
        let offset = CursorMotionEngine.newOffset(for: .left, in: "abc", from: 0, count: 5)
        #expect(offset == 0)
    }

    @Test("right clamps at end of text")
    func rightClamps() {
        let offset = CursorMotionEngine.newOffset(for: .right, in: "abc", from: 0, count: 10)
        #expect(offset == 3)
    }

    @Test("right moves count code units")
    func rightCount() {
        let offset = CursorMotionEngine.newOffset(for: .right, in: "abc", from: 0, count: 2)
        #expect(offset == 2)
    }

    @Test("up moves to the same column on the previous line")
    func upPreservesColumn() {
        let text = "abcdef\nghi"
        // start on 'h' (index 8: 'g'=7, 'h'=8); column 1 on second line.
        let offset = CursorMotionEngine.newOffset(for: .up, in: text, from: 8, count: 1)
        // expect column 1 on first line: 'b' (index 1)
        #expect(offset == 1)
    }

    @Test("down clamps column to next line's content length")
    func downClampsColumn() {
        let text = "abcdef\nxy"
        // start on 'f' (index 5); column 5 on first line.
        let offset = CursorMotionEngine.newOffset(for: .down, in: text, from: 5, count: 1)
        // next line "xy" has content length 2; clamp column → index 7 + 2 = 9 (end of 'y' content)
        #expect(offset == 9)
    }

    // MARK: - Line motion

    @Test("lineStart returns start of current line")
    func lineStartReturnsLineBeginning() {
        let text = "abc\ndefgh"
        let offset = CursorMotionEngine.newOffset(for: .lineStart, in: text, from: 7, count: 1)
        #expect(offset == 4) // 'd'
    }

    @Test("lineStart on first line returns 0")
    func lineStartFirstLine() {
        let offset = CursorMotionEngine.newOffset(for: .lineStart, in: "abc", from: 2, count: 1)
        #expect(offset == 0)
    }

    @Test("lineFirstNonBlank skips leading spaces and tabs")
    func lineFirstNonBlankSkipsWhitespace() {
        let text = "  \t  hello"
        let offset = CursorMotionEngine.newOffset(for: .lineFirstNonBlank, in: text, from: 8, count: 1)
        #expect(offset == 5) // 'h'
    }

    @Test("lineFirstNonBlank on all-whitespace line returns line end (contentEnd)")
    func lineFirstNonBlankAllWhitespace() {
        let text = "   \nhello"
        let offset = CursorMotionEngine.newOffset(for: .lineFirstNonBlank, in: text, from: 1, count: 1)
        #expect(offset == 3) // past all 3 spaces, at contentEnd
    }

    @Test("lineEnd returns content end of current line")
    func lineEndReturnsContentEnd() {
        let text = "abc\ndefgh"
        let offset = CursorMotionEngine.newOffset(for: .lineEnd, in: text, from: 5, count: 1)
        #expect(offset == 9) // after 'h', before EOF
    }

    @Test("lineEnd on line with trailing newline excludes the newline")
    func lineEndExcludesNewline() {
        let text = "abc\ndef"
        let offset = CursorMotionEngine.newOffset(for: .lineEnd, in: text, from: 1, count: 1)
        #expect(offset == 3) // 'c' is at index 2; contentEnd = 3 (right after 'c')
    }

    // MARK: - Word motion

    @Test("w from start of word goes to start of next word")
    func wFromWordStart() {
        let text = "foo bar baz"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardStart, in: text, from: 0, count: 1)
        #expect(offset == 4) // 'b' in "bar"
    }

    @Test("w from middle of word goes to start of next word")
    func wFromWordMiddle() {
        let text = "foo bar baz"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardStart, in: text, from: 1, count: 1)
        #expect(offset == 4)
    }

    @Test("w with count repeats")
    func wCount() {
        let text = "foo bar baz"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardStart, in: text, from: 0, count: 2)
        #expect(offset == 8) // 'b' in "baz"
    }

    @Test("w treats punctuation as a separate word")
    func wPunctuation() {
        let text = "foo, bar"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardStart, in: text, from: 0, count: 1)
        #expect(offset == 3) // ',' is its own word
    }

    @Test("b from start of word goes to start of previous word")
    func bFromWordStart() {
        let text = "foo bar"
        let offset = CursorMotionEngine.newOffset(for: .wordBackward, in: text, from: 4, count: 1)
        #expect(offset == 0)
    }

    @Test("b from middle of word goes to start of current word")
    func bFromWordMiddle() {
        let text = "foo bar"
        let offset = CursorMotionEngine.newOffset(for: .wordBackward, in: text, from: 6, count: 1)
        #expect(offset == 4) // 'b' in "bar"
    }

    @Test("b at offset 0 stays")
    func bAtStart() {
        let offset = CursorMotionEngine.newOffset(for: .wordBackward, in: "foo", from: 0, count: 1)
        #expect(offset == 0)
    }

    @Test("e from word start goes to last char of word")
    func eFromWordStart() {
        let text = "foo bar"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardEnd, in: text, from: 0, count: 1)
        #expect(offset == 2) // 'o' (last char of "foo")
    }

    @Test("e from end of word goes to end of next word")
    func eFromWordEnd() {
        let text = "foo bar"
        let offset = CursorMotionEngine.newOffset(for: .wordForwardEnd, in: text, from: 2, count: 1)
        #expect(offset == 6) // 'r' (last char of "bar")
    }

    // MARK: - Document jumps

    @Test("documentStart with count 1 returns offset 0")
    func documentStartDefault() {
        let text = "abc\ndef\nghi"
        let offset = CursorMotionEngine.newOffset(for: .documentStart, in: text, from: 8, count: 1)
        #expect(offset == 0)
    }

    @Test("documentStart with count N jumps to line N first-non-blank")
    func documentStartLineN() {
        let text = "abc\n  def\nghi"
        let offset = CursorMotionEngine.newOffset(for: .documentStart, in: text, from: 0, count: 2)
        #expect(offset == 6) // 'd' after two leading spaces
    }

    @Test("documentEnd with Int.max jumps to last line")
    func documentEndDefault() {
        let text = "abc\ndef\nghi"
        let offset = CursorMotionEngine.newOffset(for: .documentEnd, in: text, from: 0, count: Int.max)
        #expect(offset == 8) // 'g' on line 3
    }

    @Test("documentEnd with count N jumps to line N")
    func documentEndLineN() {
        let text = "abc\ndef\nghi\njkl"
        let offset = CursorMotionEngine.newOffset(for: .documentEnd, in: text, from: 0, count: 2)
        #expect(offset == 4) // 'd' on line 2
    }

    // MARK: - Edge cases

    @Test("empty text: all motions stay at 0")
    func emptyText() {
        #expect(CursorMotionEngine.newOffset(for: .lineStart, in: "", from: 0, count: 1) == 0)
        #expect(CursorMotionEngine.newOffset(for: .lineEnd, in: "", from: 0, count: 1) == 0)
        #expect(CursorMotionEngine.newOffset(for: .wordForwardStart, in: "", from: 0, count: 1) == 0)
        #expect(CursorMotionEngine.newOffset(for: .wordBackward, in: "", from: 0, count: 1) == 0)
        #expect(CursorMotionEngine.newOffset(for: .documentStart, in: "", from: 0, count: 1) == 0)
    }

    @Test("offset past end is clamped before motion")
    func offsetClampedAtStart() {
        let offset = CursorMotionEngine.newOffset(for: .lineStart, in: "abc", from: 100, count: 1)
        #expect(offset == 0)
    }

    // MARK: - Viewport (H/M/L)

    @Test("H lands on first non-blank of the top visible line")
    func screenTopLandsOnFirstNonBlank() {
        // Lines: 0:"abc", 4:"  def", 11:"ghi"
        // Visible char range covers all three lines.
        let text = "abc\n  def\nghi"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenTop, in: text, visibleCharRange: visible, count: 1
        )
        #expect(offset == 0) // 'a'
    }

    @Test("H respects count: 2H goes to second visible line, first non-blank")
    func screenTopCountTwo() {
        let text = "abc\n  def\nghi"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenTop, in: text, visibleCharRange: visible, count: 2
        )
        // Line 2 is "  def" (start=4, contentEnd=9); first non-blank is 'd' at 6.
        #expect(offset == 6)
    }

    @Test("H clamped to last visible line when count exceeds visible lines")
    func screenTopOverCount() {
        let text = "a\nb\nc\nd"
        // Visible range covers only the first three lines (0..5).
        let visible = NSRange(location: 0, length: 5)
        let offset = CursorMotionEngine.newOffset(
            for: .screenTop, in: text, visibleCharRange: visible, count: 99
        )
        // Line 3 is "c" at offset 4. 99H clamps to bottom of visible.
        #expect(offset == 4)
    }

    @Test("L lands on first non-blank of the bottom visible line")
    func screenBottomLandsOnFirstNonBlank() {
        let text = "abc\ndef\n  xyz"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenBottom, in: text, visibleCharRange: visible, count: 1
        )
        // Bottom line "  xyz" starts at 8; first non-blank is 'x' at 10.
        #expect(offset == 10)
    }

    @Test("L respects count: 2L goes to second-from-bottom visible line")
    func screenBottomCountTwo() {
        let text = "a\nb\nc\nd"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenBottom, in: text, visibleCharRange: visible, count: 2
        )
        // 4 visible lines; 2L → second from bottom = line 3 ("c") at offset 4.
        #expect(offset == 4)
    }

    @Test("L clamped to first visible line when count exceeds visible lines")
    func screenBottomOverCount() {
        let text = "a\nb\nc"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenBottom, in: text, visibleCharRange: visible, count: 99
        )
        // 99L clamps to top of visible — 'a' at 0.
        #expect(offset == 0)
    }

    @Test("M lands on the middle visible line")
    func screenMiddle() {
        let text = "a\nb\nc\nd\ne"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let offset = CursorMotionEngine.newOffset(
            for: .screenMiddle, in: text, visibleCharRange: visible, count: 1
        )
        // 5 visible lines: middle is line 3 ("c") at offset 4.
        #expect(offset == 4)
    }

    @Test("M ignores count")
    func screenMiddleIgnoresCount() {
        let text = "a\nb\nc\nd\ne"
        let visible = NSRange(location: 0, length: text.utf16.count)
        let withCount = CursorMotionEngine.newOffset(
            for: .screenMiddle, in: text, visibleCharRange: visible, count: 99
        )
        let withoutCount = CursorMotionEngine.newOffset(
            for: .screenMiddle, in: text, visibleCharRange: visible, count: 1
        )
        #expect(withCount == withoutCount)
    }

    @Test("viewport motion: visible range starts mid-document")
    func viewportRangeMidDocument() {
        // Doc has 5 lines; only lines 2-4 ("c","d","e") are visible.
        let text = "a\nb\nc\nd\ne"
        // Line 'c' starts at 4, line 'e' ends at 9 (no trailing newline).
        let visible = NSRange(location: 4, length: 5)
        let topOffset = CursorMotionEngine.newOffset(
            for: .screenTop, in: text, visibleCharRange: visible, count: 1
        )
        #expect(topOffset == 4) // 'c'
        let bottomOffset = CursorMotionEngine.newOffset(
            for: .screenBottom, in: text, visibleCharRange: visible, count: 1
        )
        #expect(bottomOffset == 8) // 'e'
        let middleOffset = CursorMotionEngine.newOffset(
            for: .screenMiddle, in: text, visibleCharRange: visible, count: 1
        )
        #expect(middleOffset == 6) // 'd'
    }

    @Test("viewport motion: empty visible range falls back to 0")
    func viewportEmptyVisible() {
        let text = "abc"
        let visible = NSRange(location: 0, length: 0)
        #expect(
            CursorMotionEngine.newOffset(
                for: .screenTop, in: text, visibleCharRange: visible, count: 1
            ) == 0
        )
    }

    @Test("viewport motion: empty text returns 0")
    func viewportEmptyText() {
        let visible = NSRange(location: 0, length: 0)
        #expect(
            CursorMotionEngine.newOffset(
                for: .screenMiddle, in: "", visibleCharRange: visible, count: 1
            ) == 0
        )
    }

    // MARK: - Display line (g0/g^/g$)

    @Test("g0 returns the start of the display line range")
    func displayLineStart() {
        let text = "abcdefghij"
        // Synthesize a display line covering chars 3...8 (e.g. a soft-wrap).
        let range = NSRange(location: 3, length: 6)
        let offset = CursorMotionEngine.newOffset(
            for: .start, in: text, displayLineRange: range
        )
        #expect(offset == 3)
    }

    @Test("g^ skips leading whitespace inside the display line")
    func displayLineFirstNonBlank() {
        let text = "   xyz"
        let range = NSRange(location: 0, length: 6)
        let offset = CursorMotionEngine.newOffset(
            for: .firstNonBlank, in: text, displayLineRange: range
        )
        #expect(offset == 3) // 'x'
    }

    @Test("g^ on an all-whitespace display line lands at the row's last column")
    func displayLineFirstNonBlankAllWhitespace() {
        let text = "    "
        let range = NSRange(location: 0, length: 4)
        let offset = CursorMotionEngine.newOffset(
            for: .firstNonBlank, in: text, displayLineRange: range
        )
        #expect(offset == 3) // last char in the row
    }

    @Test("g$ lands on the last visible char (skipping trailing newline)")
    func displayLineEndSkipsNewline() {
        let text = "abc\n"
        let range = NSRange(location: 0, length: 4) // includes \n
        let offset = CursorMotionEngine.newOffset(
            for: .end, in: text, displayLineRange: range
        )
        #expect(offset == 2) // 'c', not the newline at 3
    }

    @Test("g$ on a soft-wrapped row (no trailing newline) lands on the last char")
    func displayLineEndSoftWrap() {
        let text = "abcdef"
        let range = NSRange(location: 0, length: 3) // soft wrap after 'c'
        let offset = CursorMotionEngine.newOffset(
            for: .end, in: text, displayLineRange: range
        )
        #expect(offset == 2) // 'c'
    }

    @Test("g0 on an empty display line returns the location unchanged")
    func displayLineStartEmptyRange() {
        let text = "abc"
        let range = NSRange(location: 1, length: 0)
        let offset = CursorMotionEngine.newOffset(
            for: .start, in: text, displayLineRange: range
        )
        #expect(offset == 1)
    }

    @Test("g0/g^/g$ on empty text return 0")
    func displayLineEmptyText() {
        let range = NSRange(location: 0, length: 0)
        #expect(
            CursorMotionEngine.newOffset(
                for: .start, in: "", displayLineRange: range
            ) == 0
        )
        #expect(
            CursorMotionEngine.newOffset(
                for: .firstNonBlank, in: "", displayLineRange: range
            ) == 0
        )
        #expect(
            CursorMotionEngine.newOffset(
                for: .end, in: "", displayLineRange: range
            ) == 0
        )
    }

    // MARK: - Insert entry plans

    @Test("i (atCursor): no edit, cursor unchanged")
    func insertEntryAtCursor() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .atCursor, in: "abc", cursor: 1
        )
        #expect(plan.edit == nil)
        #expect(plan.cursorAfter == 1)
    }

    @Test("a (afterCursor): cursor advances by one within the line")
    func insertEntryAfterCursorMid() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .afterCursor, in: "abc", cursor: 1
        )
        #expect(plan.edit == nil)
        #expect(plan.cursorAfter == 2)
    }

    @Test("a (afterCursor): clamps to line content end on the last char")
    func insertEntryAfterCursorClamp() {
        // "abc\ndef" — cursor on 'c' (position 2). +1 = 3 = contentEnd of first line.
        let plan = CursorMotionEngine.planInsertEntry(
            for: .afterCursor, in: "abc\ndef", cursor: 2
        )
        #expect(plan.cursorAfter == 3)
    }

    @Test("a (afterCursor): never crosses a newline")
    func insertEntryAfterCursorNoCrossNewline() {
        // "abc\ndef" — cursor at end of 'c' (position 3, on the \n). +1 would
        // cross to next line; clamp to contentEnd = 3.
        let plan = CursorMotionEngine.planInsertEntry(
            for: .afterCursor, in: "abc\ndef", cursor: 3
        )
        #expect(plan.cursorAfter == 3)
    }

    @Test("I (atLineFirstNonBlank): skips leading whitespace on the line")
    func insertEntryFirstNonBlank() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .atLineFirstNonBlank, in: "  abc", cursor: 4
        )
        #expect(plan.edit == nil)
        #expect(plan.cursorAfter == 2)
    }

    @Test("A (atLineEnd): cursor lands at content end (before newline)")
    func insertEntryAtLineEnd() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .atLineEnd, in: "abc\ndef", cursor: 1
        )
        #expect(plan.edit == nil)
        #expect(plan.cursorAfter == 3)
    }

    @Test("o (openLineBelow): inserts \\n at content end; cursor on the new empty line")
    func insertEntryOpenLineBelowMidDoc() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .openLineBelow, in: "abc\ndef", cursor: 1
        )
        #expect(plan.edit?.range == NSRange(location: 3, length: 0))
        #expect(plan.edit?.replacement == "\n")
        // After insertion: "abc\n\ndef"; cursor at 4 = on the new empty line.
        #expect(plan.cursorAfter == 4)
    }

    @Test("o (openLineBelow): EOF case appends \\n; cursor on the new trailing empty line")
    func insertEntryOpenLineBelowEOF() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .openLineBelow, in: "abc", cursor: 1
        )
        #expect(plan.edit?.range == NSRange(location: 3, length: 0))
        #expect(plan.edit?.replacement == "\n")
        // After insertion: "abc\n"; cursor at 4 = past EOF on the new line.
        #expect(plan.cursorAfter == 4)
    }

    @Test("O (openLineAbove): inserts \\n at line start; cursor on the new empty line")
    func insertEntryOpenLineAboveMidDoc() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .openLineAbove, in: "abc\ndef", cursor: 5
        )
        #expect(plan.edit?.range == NSRange(location: 4, length: 0))
        #expect(plan.edit?.replacement == "\n")
        // After insertion: "abc\n\ndef"; cursor at 4 = on the new empty line.
        #expect(plan.cursorAfter == 4)
    }

    @Test("O (openLineAbove): top of document inserts \\n at 0")
    func insertEntryOpenLineAboveTop() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .openLineAbove, in: "abc", cursor: 1
        )
        #expect(plan.edit?.range == NSRange(location: 0, length: 0))
        #expect(plan.edit?.replacement == "\n")
        #expect(plan.cursorAfter == 0)
    }

    @Test("s (substituteChar): deletes one char under cursor; cursor stays")
    func insertEntrySubstituteChar() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .substituteChar, in: "abc", cursor: 1
        )
        #expect(plan.edit?.range == NSRange(location: 1, length: 1))
        #expect(plan.edit?.replacement == "")
        #expect(plan.cursorAfter == 1)
    }

    @Test("s on a newline / past content end is a no-op (just enters insert mode)")
    func insertEntrySubstituteCharBoundary() {
        // "abc\ndef" — cursor on the \n at position 3. content end is 3,
        // so the cursor IS at content end → no deletion.
        let plan = CursorMotionEngine.planInsertEntry(
            for: .substituteChar, in: "abc\ndef", cursor: 3
        )
        #expect(plan.edit == nil)
        #expect(plan.cursorAfter == 3)
    }

    @Test("S (substituteLine): deletes the entire line content; cursor at line start")
    func insertEntrySubstituteLine() {
        // "abc\ndef" cursor on 'e' (position 5). Line: start=4, contentEnd=7.
        let plan = CursorMotionEngine.planInsertEntry(
            for: .substituteLine, in: "abc\ndef", cursor: 5
        )
        #expect(plan.edit?.range == NSRange(location: 4, length: 3))
        #expect(plan.edit?.replacement == "")
        #expect(plan.cursorAfter == 4)
    }

    @Test("S on the only line of a single-line document leaves the line empty")
    func insertEntrySubstituteLineOnlyLine() {
        let plan = CursorMotionEngine.planInsertEntry(
            for: .substituteLine, in: "abc", cursor: 1
        )
        #expect(plan.edit?.range == NSRange(location: 0, length: 3))
        #expect(plan.cursorAfter == 0)
    }

    @Test("display-line range mid-document: g0/g^/g$ all stay on that row")
    func displayLineMidDocument() {
        // Document with three rows; row 2 is offset 4..9 (chars "  xyz")
        let text = "abc\n  xyz\n123"
        let range = NSRange(location: 4, length: 6) // "  xyz\n"
        #expect(
            CursorMotionEngine.newOffset(
                for: .start, in: text, displayLineRange: range
            ) == 4
        )
        #expect(
            CursorMotionEngine.newOffset(
                for: .firstNonBlank, in: text, displayLineRange: range
            ) == 6 // 'x'
        )
        #expect(
            CursorMotionEngine.newOffset(
                for: .end, in: text, displayLineRange: range
            ) == 8 // 'z' (skips the trailing '\n' at 9)
        )
    }
}
