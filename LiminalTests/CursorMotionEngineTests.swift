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
}
