import CambiumCore
import Foundation

/// Pure cursor-motion math. Given a `CambiumSource` rope + a UTF-16
/// offset, returns the new offset after applying a `CursorMotion`.
/// AppKit-free so unit tests can exercise every motion without spinning
/// up an NSTextView.
///
/// UTF-16 offsets are the lingua franca with NSTextView/NSString. The
/// engine queries the rope's line aggregates for line motions (O(log N))
/// and walks `UTF16Cursor` for character categorization in word/line
/// motions (O(1) per step within a chunk, amortized cheap across
/// chunk boundaries).
///
/// Line-break semantics: the rope counts only `\n`. `\r\n` is detected
/// via a byte probe in `lineInfo`; bare `\r` is treated as content (no
/// line break). Exotic separators (U+2028, U+2029, NEL) are not
/// recognized — pasted content using them will see subtly different
/// line motion than NSString-based AppKit text.
public struct InsertEntryPlan: Equatable, Sendable {
    public let edit: Edit?
    /// Cursor's UTF-16 position after `edit` (if any) is applied.
    public let cursorAfter: Int

    public struct Edit: Equatable, Sendable {
        /// Pre-edit UTF-16 range to replace.
        public let range: NSRange
        public let replacement: String
    }
}

enum CursorMotionEngine {

    /// Resolve a vim-style motion to a UTF-16 offset.
    static func newOffset(
        for motion: CursorMotion,
        source: CambiumSource,
        from offset: Int,
        count: Int = 1
    ) -> Int {
        let textLength = source.utf16Count
        let clampedStart = max(0, min(offset, textLength))
        let steps = max(1, count)

        switch motion {
        case .left:
            return max(0, clampedStart - steps)
        case .right:
            return min(textLength, clampedStart + steps)
        case .up:
            return verticalMove(from: clampedStart, direction: .up,
                                count: steps, in: source)
        case .down:
            return verticalMove(from: clampedStart, direction: .down,
                                count: steps, in: source)
        case .lineStart:
            return lineInfo(at: clampedStart, in: source).start
        case .lineFirstNonBlank:
            return lineFirstNonBlank(at: clampedStart, in: source)
        case .lineEnd:
            return lineInfo(at: clampedStart, in: source).contentEnd
        case .wordForwardStart:
            return repeatedly(steps) { current in
                wordForwardStart(from: current, in: source)
            }(clampedStart)
        case .wordBackward:
            return repeatedly(steps) { current in
                wordBackward(from: current, in: source)
            }(clampedStart)
        case .wordForwardEnd:
            return repeatedly(steps) { current in
                wordForwardEnd(from: current, in: source)
            }(clampedStart)
        case .documentStart:
            // count == 1 (the default after vim's `gg`) targets line 1;
            // a higher count targets that absolute line number.
            let targetLine = count > 0 ? count : 1
            let lineStartOffset = offsetForLine(targetLine, in: source)
            return lineFirstNonBlank(at: lineStartOffset, in: source)
        case .documentEnd:
            // `G` with no count targets the last line; `<N>G` targets N.
            // Sentinel: count == Int.max means "last line".
            let targetLineStart: Int
            if count == Int.max {
                targetLineStart = lineInfo(at: textLength, in: source).start
            } else {
                targetLineStart = offsetForLine(count, in: source)
            }
            return lineFirstNonBlank(at: targetLineStart, in: source)
        }
    }

    /// Resolve a viewport-relative motion (H/M/L) to a UTF-16 offset.
    /// The caller hands us the visible character range from
    /// `NSLayoutManager`; we translate to a target line, then land on
    /// its first non-blank.
    ///
    /// `count`:
    ///   - `screenTop`: line `count - 1` below the top visible line.
    ///   - `screenBottom`: line `count - 1` above the bottom visible
    ///     line.
    ///   - `screenMiddle`: ignored (vim semantics).
    static func newOffset(
        for motion: ViewportMotion,
        source: CambiumSource,
        visibleCharRange: NSRange,
        count: Int = 1
    ) -> Int {
        let textLength = source.utf16Count
        guard textLength > 0 else { return 0 }
        guard visibleCharRange.length > 0 else { return 0 }

        let firstVisible = max(0, min(visibleCharRange.location, textLength - 1))
        let lastVisible = max(
            firstVisible,
            min(visibleCharRange.location + visibleCharRange.length - 1,
                textLength - 1)
        )

        let firstLineStart = lineInfo(at: firstVisible, in: source).start
        let lastLineStart = lineInfo(at: lastVisible, in: source).start

        let targetLineStart: Int
        switch motion {
        case .screenTop:
            targetLineStart = lineStart(
                offsetFrom: firstLineStart,
                lines: max(0, count - 1),
                direction: .down,
                limitLineStart: lastLineStart,
                in: source
            )
        case .screenBottom:
            targetLineStart = lineStart(
                offsetFrom: lastLineStart,
                lines: max(0, count - 1),
                direction: .up,
                limitLineStart: firstLineStart,
                in: source
            )
        case .screenMiddle:
            targetLineStart = midpointLineStart(
                between: firstLineStart,
                and: lastLineStart,
                in: source
            )
        }

        return lineFirstNonBlank(at: targetLineStart, in: source)
    }

    /// Resolve a display-line edge motion (`g0` / `g^` / `g$`) over a
    /// display line whose character range the caller has already
    /// extracted from `NSLayoutManager`. Pure logic; the layout query
    /// lives in the Coordinator since it can't be cleanly mocked.
    ///
    /// `down` and `up` cannot be resolved without layout metrics
    /// (preferred-x in the destination line fragment), so this helper
    /// returns the start of the input range — the Coordinator handles
    /// those motions directly.
    static func newOffset(
        for motion: DisplayLineMotion,
        source: CambiumSource,
        displayLineRange: NSRange
    ) -> Int {
        let textLength = source.utf16Count
        guard textLength > 0 else { return 0 }
        guard displayLineRange.length > 0 else { return displayLineRange.location }

        let lineStartOffset = displayLineRange.location
        let lineEndOpen = min(lineStartOffset + displayLineRange.length, textLength)

        switch motion {
        case .start:
            return lineStartOffset
        case .firstNonBlank:
            var cursor = source.utf16Cursor(at: lineStartOffset)
            var i = lineStartOffset
            while i < lineEndOpen, let ch = cursor.current, isWhitespace(ch) {
                cursor.advance()
                i += 1
            }
            // All-whitespace display row: land at the row's end so the
            // cursor stays on the row instead of at its start.
            if i == lineEndOpen { return max(lineStartOffset, lineEndOpen - 1) }
            return i
        case .end:
            // Land on the last visible character of the row. If the row
            // terminates with a newline (a hard wrap), back over it.
            var end = lineEndOpen - 1
            if end >= lineStartOffset, end < textLength {
                let last = source.utf16Unit(atOffset: end)
                if last == 0x0A { end -= 1 }
            }
            return max(lineStartOffset, end)
        case .down, .up:
            // Layout-bound; caller routes these through the
            // NSLayoutManager-driven path.
            return displayLineRange.location
        }
    }

    /// Walk `lines` lines from `start` toward `direction`, but never
    /// past `limitLineStart`. Returns the start of the resulting line.
    private enum WalkDirection { case up, down }

    private static func lineStart(
        offsetFrom start: Int,
        lines: Int,
        direction: WalkDirection,
        limitLineStart: Int,
        in source: CambiumSource
    ) -> Int {
        var current = start
        for _ in 0..<lines {
            let info = lineInfo(at: current, in: source)
            switch direction {
            case .down:
                guard info.end < source.utf16Count else { return current }
                let nextStart = lineInfo(at: info.end, in: source).start
                if nextStart > limitLineStart { return current }
                current = nextStart
            case .up:
                guard info.start > 0 else { return current }
                let prevStart = lineInfo(at: info.start - 1, in: source).start
                if prevStart < limitLineStart { return current }
                current = prevStart
            }
        }
        return current
    }

    /// The line whose start offset is closest to the midpoint of
    /// `firstLineStart` and `lastLineStart`. Walks line-by-line from
    /// the top — exact line counts beat byte-midpoint math because
    /// lines vary in length.
    private static func midpointLineStart(
        between firstLineStart: Int,
        and lastLineStart: Int,
        in source: CambiumSource
    ) -> Int {
        guard firstLineStart != lastLineStart else { return firstLineStart }
        var lineStarts: [Int] = [firstLineStart]
        var current = firstLineStart
        while current < lastLineStart {
            let info = lineInfo(at: current, in: source)
            guard info.end < source.utf16Count else { break }
            current = info.end
            lineStarts.append(current)
            if current >= lastLineStart { break }
        }
        return lineStarts[lineStarts.count / 2]
    }

    // MARK: - Insert-mode entry plans

    /// Compute what the editor needs to do to enter insert mode at the
    /// requested position: an optional pre-edit (for `o`, `O`, `s`, `S`)
    /// and the cursor's UTF-16 position after the edit. Pure logic;
    /// the Coordinator applies the plan against the live `NSTextView`.
    static func planInsertEntry(
        for position: InsertPosition,
        source: CambiumSource,
        cursor: Int
    ) -> InsertEntryPlan {
        let textLength = source.utf16Count
        let safeCursor = max(0, min(cursor, textLength))
        let info = lineInfo(at: safeCursor, in: source)

        switch position {
        case .atCursor:
            return InsertEntryPlan(edit: nil, cursorAfter: safeCursor)

        case .afterCursor:
            // Vim `a` lands one cell past the cursor, but never past
            // end-of-line content (the trailing `\n` is not an
            // editable column).
            return InsertEntryPlan(
                edit: nil,
                cursorAfter: min(safeCursor + 1, info.contentEnd)
            )

        case .atLineFirstNonBlank:
            return InsertEntryPlan(
                edit: nil,
                cursorAfter: lineFirstNonBlank(at: safeCursor, in: source)
            )

        case .atLineEnd:
            return InsertEntryPlan(edit: nil, cursorAfter: info.contentEnd)

        case .openLineBelow:
            return InsertEntryPlan(
                edit: InsertEntryPlan.Edit(
                    range: NSRange(location: info.contentEnd, length: 0),
                    replacement: "\n"
                ),
                cursorAfter: info.contentEnd + 1
            )

        case .openLineAbove:
            return InsertEntryPlan(
                edit: InsertEntryPlan.Edit(
                    range: NSRange(location: info.start, length: 0),
                    replacement: "\n"
                ),
                cursorAfter: info.start
            )

        case .substituteChar:
            // `s` deletes the char under cursor and enters insert mode.
            // Bounded by the line's content end — vim's `s` doesn't eat
            // the trailing `\n`.
            guard safeCursor < info.contentEnd else {
                return InsertEntryPlan(edit: nil, cursorAfter: safeCursor)
            }
            return InsertEntryPlan(
                edit: InsertEntryPlan.Edit(
                    range: NSRange(location: safeCursor, length: 1),
                    replacement: ""
                ),
                cursorAfter: safeCursor
            )

        case .substituteLine:
            // `S` deletes the entire line content (preserving the
            // line's existence — the `\n` terminator stays) and enters
            // insert mode at the line start.
            return InsertEntryPlan(
                edit: InsertEntryPlan.Edit(
                    range: NSRange(
                        location: info.start,
                        length: info.contentEnd - info.start
                    ),
                    replacement: ""
                ),
                cursorAfter: info.start
            )
        }
    }

    // MARK: - Line helpers (rope-native)

    /// Compute (start, contentEnd, end) UTF-16 offsets for the line
    /// containing `offset`. `contentEnd` is the position of the line
    /// terminator (or end of doc for the last line); `end` is the
    /// position past the terminator (i.e., start of next line, or end
    /// of doc).
    ///
    /// Recognizes `\n` and `\r\n` line terminators via a byte probe at
    /// the line end. Other separators (bare `\r`, U+2028, etc.) are
    /// treated as content.
    private static func lineInfo(
        at offset: Int,
        in source: CambiumSource
    ) -> (start: Int, contentEnd: Int, end: Int) {
        let totalUTF16 = source.utf16Count
        let totalBytes = source.byteCount
        if totalBytes == 0 { return (0, 0, 0) }
        let safeOffset = max(0, min(offset, totalUTF16))
        let byteOffset = source.byteOffset(forUTF16: safeOffset)
        let (line1, _) = source.lineColumn(forByte: byteOffset)

        let startByte = Int((source.byteOffset(forLine: line1, column: 1) ?? TextSize(0)).rawValue)
        let endByte: Int
        if let nextStart = source.byteOffset(forLine: line1 + 1, column: 1) {
            endByte = Int(nextStart.rawValue)
        } else {
            endByte = totalBytes
        }

        let startUTF16 = source.utf16Offset(forByte: TextSize(UInt32(startByte)))
        let endUTF16 = source.utf16Offset(forByte: TextSize(UInt32(endByte)))

        // Detect \r\n vs \n vs no-terminator at the end of the line.
        let contentEndUTF16: Int
        if endByte > startByte {
            // Fetch up to 2 bytes preceding endByte to detect terminator.
            let probeStart = max(startByte, endByte - 2)
            let probe = source.bytes(in: CambiumCore.TextRange(
                start: TextSize(UInt32(probeStart)),
                end: TextSize(UInt32(endByte))
            ))
            if let last = probe.last, last == 0x0A {
                // Line ends with \n. Check for preceding \r.
                if probe.count >= 2, probe[probe.count - 2] == 0x0D {
                    // CRLF: \r\n is one UTF-16 unit each (both BMP),
                    // so subtract 2.
                    contentEndUTF16 = endUTF16 - 2
                } else {
                    // LF only.
                    contentEndUTF16 = endUTF16 - 1
                }
            } else {
                // No \n terminator (last line in non-newline-terminated
                // doc, or rope reached doc end).
                contentEndUTF16 = endUTF16
            }
        } else {
            contentEndUTF16 = endUTF16
        }

        return (startUTF16, contentEndUTF16, endUTF16)
    }

    /// First non-whitespace UTF-16 offset on the line containing `location`,
    /// or `info.contentEnd` if the line is all whitespace.
    private static func lineFirstNonBlank(at location: Int, in source: CambiumSource) -> Int {
        let info = lineInfo(at: location, in: source)
        guard info.start < info.contentEnd else { return info.start }
        var cursor = source.utf16Cursor(at: info.start)
        var i = info.start
        while i < info.contentEnd, let ch = cursor.current, isWhitespace(ch) {
            cursor.advance()
            i += 1
        }
        return i
    }

    /// UTF-16 offset of the start of `targetLine` (1-based). O(log N).
    private static func offsetForLine(_ targetLine: Int, in source: CambiumSource) -> Int {
        guard targetLine > 0, source.byteCount > 0 else { return 0 }
        let cappedLine = min(targetLine, source.lineCount + 1)
        guard let byteOffset = source.byteOffset(forLine: cappedLine, column: 1)
        else { return 0 }
        return source.utf16Offset(forByte: byteOffset)
    }

    // MARK: - Vertical (h/j/k/l up/down)

    private enum VerticalDirection { case up, down }

    /// Move the cursor up/down by `count` lines, preserving the UTF-16
    /// column offset within each line (clamped to that line's content
    /// length).
    private static func verticalMove(
        from location: Int,
        direction: VerticalDirection,
        count: Int,
        in source: CambiumSource
    ) -> Int {
        var current = location
        let totalUTF16 = source.utf16Count
        for _ in 0..<count {
            let curUTF16 = max(0, min(current, totalUTF16))
            let curByte = source.byteOffset(forUTF16: curUTF16)
            let (curLine1, _) = source.lineColumn(forByte: curByte)
            let curLineStartByte = source.byteOffset(forLine: curLine1, column: 1)
                ?? TextSize(0)
            let curLineStartUTF16 = source.utf16Offset(forByte: curLineStartByte)
            let column = current - curLineStartUTF16

            let targetLine1: Int
            switch direction {
            case .up:
                guard curLine1 > 1 else { return current }
                targetLine1 = curLine1 - 1
            case .down:
                guard source.byteOffset(forLine: curLine1 + 1, column: 1) != nil
                else { return current }
                targetLine1 = curLine1 + 1
            }

            guard let targetStartByte = source.byteOffset(forLine: targetLine1, column: 1)
            else { return current }
            let targetStartUTF16 = source.utf16Offset(forByte: targetStartByte)

            // Content-end UTF-16 = either (next line start - \n's UTF-16 units)
            // or doc end if target is the last line.
            let targetContentLenUTF16: Int
            if let nextStartByte = source.byteOffset(forLine: targetLine1 + 1, column: 1) {
                let nextStartUTF16 = source.utf16Offset(forByte: nextStartByte)
                targetContentLenUTF16 = max(0, nextStartUTF16 - targetStartUTF16 - 1)
            } else {
                targetContentLenUTF16 = max(0, totalUTF16 - targetStartUTF16)
            }

            current = targetStartUTF16 + min(column, targetContentLenUTF16)
        }
        return current
    }

    // MARK: - Word motions (cursor-based)

    private enum CharCategory: Equatable {
        case keyword     // letters, digits, underscore
        case other       // non-keyword, non-whitespace (punctuation/symbols)
        case whitespace  // space, tab, newline, etc.
    }

    private static func category(_ ch: unichar) -> CharCategory {
        if isWhitespace(ch) { return .whitespace }
        if isKeyword(ch) { return .keyword }
        return .other
    }

    private static func isWhitespace(_ ch: unichar) -> Bool {
        switch ch {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    private static func isKeyword(_ ch: unichar) -> Bool {
        switch ch {
        case 0x30...0x39: return true            // 0-9
        case 0x41...0x5A: return true            // A-Z
        case 0x5F:        return true            // _
        case 0x61...0x7A: return true            // a-z
        default:          return false
        }
    }

    /// `w` — start of next word.
    private static func wordForwardStart(from offset: Int, in source: CambiumSource) -> Int {
        let end = source.utf16Count
        guard offset < end else { return offset }
        var cursor = source.utf16Cursor(at: offset)
        var i = offset
        guard let firstUnit = cursor.current else { return offset }
        let startCat = category(firstUnit)
        // Advance through the current word/non-word run.
        if startCat != .whitespace {
            while i < end, let ch = cursor.current, category(ch) == startCat {
                cursor.advance()
                i += 1
            }
        }
        // Skip whitespace to land on the next word's first char.
        while i < end, let ch = cursor.current, category(ch) == .whitespace {
            cursor.advance()
            i += 1
        }
        return i
    }

    /// `b` — start of previous word.
    private static func wordBackward(from offset: Int, in source: CambiumSource) -> Int {
        guard offset > 0 else { return 0 }
        var cursor = source.utf16Cursor(at: offset - 1)
        var i = offset - 1
        // Skip whitespace going backward.
        while i > 0, let ch = cursor.current, category(ch) == .whitespace {
            cursor.retreat()
            i -= 1
        }
        guard let unitAtI = cursor.current else { return 0 }
        if category(unitAtI) == .whitespace { return 0 }
        // Walk back through the current word/non-word run to its start.
        let cat = category(unitAtI)
        // Peek prev; if same category, retreat and continue.
        while i > 0 {
            var probe = cursor
            probe.retreat()
            guard let prev = probe.current, category(prev) == cat else { break }
            cursor = probe
            i -= 1
        }
        return i
    }

    /// `e` — end (last char) of current or next word.
    private static func wordForwardEnd(from offset: Int, in source: CambiumSource) -> Int {
        let end = source.utf16Count
        guard end > 0 else { return 0 }
        guard offset < end - 1 else { return min(offset, end - 1) }

        var cursor = source.utf16Cursor(at: offset + 1)
        var i = offset + 1
        // Skip whitespace forward.
        while i < end, let ch = cursor.current, category(ch) == .whitespace {
            cursor.advance()
            i += 1
        }
        if i >= end { return min(offset, end - 1) }
        guard let unitAtI = cursor.current else { return min(offset, end - 1) }
        // Walk forward to the last char of the current word/non-word run.
        let cat = category(unitAtI)
        while i + 1 < end {
            var probe = cursor
            probe.advance()
            guard let nextUnit = probe.current, category(nextUnit) == cat else { break }
            cursor = probe
            i += 1
        }
        return i
    }

    // MARK: - Utilities

    /// Returns a closure that applies `step` exactly `n` times.
    private static func repeatedly(_ n: Int, _ step: @escaping (Int) -> Int) -> (Int) -> Int {
        return { initial in
            var current = initial
            for _ in 0..<n {
                let next = step(current)
                if next == current { return current } // motion saturated
                current = next
            }
            return current
        }
    }
}
