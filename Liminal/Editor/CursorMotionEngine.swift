import Foundation

/// Pure cursor-motion math. Given a text + UTF-16 offset, returns the
/// new offset after applying a `CursorMotion`. AppKit-free so unit tests
/// can exercise every motion without spinning up an NSTextView.
///
/// UTF-16 offsets are the lingua franca with NSTextView/NSString. The
/// engine bridges to NSString for line-boundary work where that's the
/// natural primitive, and walks the UTF-16 view directly for character
/// categorization in word motions.
enum CursorMotionEngine {

    static func newOffset(
        for motion: CursorMotion,
        in text: String,
        from offset: Int,
        count: Int = 1
    ) -> Int {
        let nsString = text as NSString
        let textLength = nsString.length
        let clampedStart = max(0, min(offset, textLength))
        let steps = max(1, count)

        switch motion {
        case .left:
            return max(0, clampedStart - steps)
        case .right:
            return min(textLength, clampedStart + steps)
        case .up:
            return verticalMove(from: clampedStart, direction: .up,
                                count: steps, in: nsString)
        case .down:
            return verticalMove(from: clampedStart, direction: .down,
                                count: steps, in: nsString)
        case .lineStart:
            return lineInfo(at: clampedStart, in: nsString).start
        case .lineFirstNonBlank:
            return lineFirstNonBlank(at: clampedStart, in: nsString)
        case .lineEnd:
            return lineInfo(at: clampedStart, in: nsString).contentEnd
        case .wordForwardStart:
            return repeatedly(steps) { current in
                wordForwardStart(from: current, in: nsString)
            }(clampedStart)
        case .wordBackward:
            return repeatedly(steps) { current in
                wordBackward(from: current, in: nsString)
            }(clampedStart)
        case .wordForwardEnd:
            return repeatedly(steps) { current in
                wordForwardEnd(from: current, in: nsString)
            }(clampedStart)
        case .documentStart:
            // count == 1 (the default after vim's `gg`) targets line 1;
            // a higher count targets that absolute line number.
            let targetLine = count > 0 ? count : 1
            let lineStart = offsetForLine(targetLine, in: nsString)
            return lineFirstNonBlank(at: lineStart, in: nsString)
        case .documentEnd:
            // `G` with no count targets the last line; `<N>G` targets N.
            // Disambiguate via the controller passing `count = 0` when no
            // count was typed — but our binding factories never pass 0, so
            // we rely on a sentinel: count == 1 means "no explicit count"
            // here, since `G` alone matches that. Cleaner alternative: use
            // a separate motion case for "go to last". Pragmatic compromise
            // for now: callers pass `count = Int.max` to mean "last line".
            let targetLineStart: Int
            if count == Int.max {
                targetLineStart = lineInfo(at: textLength, in: nsString).start
            } else {
                targetLineStart = offsetForLine(count, in: nsString)
            }
            return lineFirstNonBlank(at: targetLineStart, in: nsString)
        }
    }

    /// Resolve a viewport-relative motion to a UTF-16 offset. The
    /// caller hands us the visible character range from
    /// `NSLayoutManager` and we translate to a target line, then
    /// land on its first non-blank (vim's convention for `H`/`M`/`L`).
    ///
    /// `count`:
    ///   - `screenTop`: line `count - 1` below the top visible line.
    ///   - `screenBottom`: line `count - 1` above the bottom visible
    ///     line.
    ///   - `screenMiddle`: ignored (vim semantics).
    static func newOffset(
        for motion: ViewportMotion,
        in text: String,
        visibleCharRange: NSRange,
        count: Int = 1
    ) -> Int {
        let nsString = text as NSString
        guard nsString.length > 0 else { return 0 }
        guard visibleCharRange.length > 0 else { return 0 }

        let firstVisible = max(0, min(visibleCharRange.location, nsString.length - 1))
        let lastVisible = max(
            firstVisible,
            min(visibleCharRange.location + visibleCharRange.length - 1,
                nsString.length - 1)
        )

        let firstLineStart = lineInfo(at: firstVisible, in: nsString).start
        let lastLineStart = lineInfo(at: lastVisible, in: nsString).start

        let targetLineStart: Int
        switch motion {
        case .screenTop:
            targetLineStart = lineStart(
                offsetFrom: firstLineStart,
                lines: max(0, count - 1),
                direction: .down,
                limitLineStart: lastLineStart,
                in: nsString
            )
        case .screenBottom:
            targetLineStart = lineStart(
                offsetFrom: lastLineStart,
                lines: max(0, count - 1),
                direction: .up,
                limitLineStart: firstLineStart,
                in: nsString
            )
        case .screenMiddle:
            targetLineStart = midpointLineStart(
                between: firstLineStart,
                and: lastLineStart,
                in: nsString
            )
        }

        return lineFirstNonBlank(at: targetLineStart, in: nsString)
    }

    /// Resolve a display-line edge motion (`g0` / `g^` / `g$`) over
    /// a display line whose character range the caller has already
    /// extracted from `NSLayoutManager`. Pure logic; the layout
    /// query lives in the Coordinator since it can't be cleanly
    /// mocked.
    ///
    /// `down` and `up` cannot be resolved without layout metrics
    /// (preferred-x in the destination line fragment), so this
    /// helper traps them — the Coordinator handles those directly.
    static func newOffset(
        for motion: DisplayLineMotion,
        in text: String,
        displayLineRange: NSRange
    ) -> Int {
        let nsString = text as NSString
        let textLength = nsString.length
        guard textLength > 0 else { return 0 }
        guard displayLineRange.length > 0 else { return displayLineRange.location }

        let lineStart = displayLineRange.location
        let lineEndOpen = min(lineStart + displayLineRange.length, textLength)

        switch motion {
        case .start:
            return lineStart
        case .firstNonBlank:
            var i = lineStart
            while i < lineEndOpen {
                let ch = nsString.character(at: i)
                if !isWhitespace(ch) { break }
                i += 1
            }
            // All-whitespace display row: land at the row's end so
            // the cursor stays on the row instead of at its start.
            if i == lineEndOpen { return max(lineStart, lineEndOpen - 1) }
            return i
        case .end:
            // Land on the last *visible* character of the row. If
            // the row terminates with a newline (a hard-wrap, not a
            // soft one), back over it so the cursor sits on
            // content, matching vim's `$` semantics.
            var end = lineEndOpen - 1
            if end >= lineStart, end < textLength,
               nsString.character(at: end) == 0x0A {
                end -= 1
            }
            return max(lineStart, end)
        case .down, .up:
            // Layout-bound; caller routes these through the
            // NSLayoutManager-driven path.
            return displayLineRange.location
        }
    }

    /// Walk `lines` lines from `start` toward `direction`, but never
    /// past `limitLineStart`. Returns the start of the resulting
    /// line.
    private enum WalkDirection { case up, down }

    private static func lineStart(
        offsetFrom start: Int,
        lines: Int,
        direction: WalkDirection,
        limitLineStart: Int,
        in nsString: NSString
    ) -> Int {
        var current = start
        for _ in 0..<lines {
            let info = lineInfo(at: current, in: nsString)
            switch direction {
            case .down:
                guard info.end < nsString.length else { return current }
                let nextStart = lineInfo(at: info.end, in: nsString).start
                if nextStart > limitLineStart { return current }
                current = nextStart
            case .up:
                guard info.start > 0 else { return current }
                let prevStart = lineInfo(at: info.start - 1, in: nsString).start
                if prevStart < limitLineStart { return current }
                current = prevStart
            }
        }
        return current
    }

    /// The line whose start offset is closest to the midpoint of
    /// `firstLineStart` and `lastLineStart`. Walks line-by-line
    /// from the top — exact line counts beat byte-midpoint math
    /// because lines vary in length.
    private static func midpointLineStart(
        between firstLineStart: Int,
        and lastLineStart: Int,
        in nsString: NSString
    ) -> Int {
        guard firstLineStart != lastLineStart else { return firstLineStart }
        // Count total lines in the visible band.
        var lineStarts: [Int] = [firstLineStart]
        var current = firstLineStart
        while current < lastLineStart {
            let info = lineInfo(at: current, in: nsString)
            guard info.end < nsString.length else { break }
            current = info.end
            lineStarts.append(current)
            if current >= lastLineStart { break }
        }
        return lineStarts[lineStarts.count / 2]
    }

    // MARK: - Line helpers

    private static func lineInfo(
        at location: Int,
        in nsString: NSString
    ) -> (start: Int, contentEnd: Int, end: Int) {
        var start = 0
        var end = 0
        var contentEnd = 0
        let safeLocation = max(0, min(location, nsString.length))
        nsString.getLineStart(
            &start,
            end: &end,
            contentsEnd: &contentEnd,
            for: NSRange(location: safeLocation, length: 0)
        )
        return (start, contentEnd, end)
    }

    private static func lineFirstNonBlank(at location: Int, in nsString: NSString) -> Int {
        let info = lineInfo(at: location, in: nsString)
        var i = info.start
        while i < info.contentEnd {
            let ch = nsString.character(at: i)
            if !isWhitespace(ch) { break }
            i += 1
        }
        return i
    }

    private static func offsetForLine(_ targetLine: Int, in nsString: NSString) -> Int {
        let textLength = nsString.length
        guard targetLine > 0, textLength > 0 else { return 0 }
        var currentOffset = 0
        var lineNum = 1
        while currentOffset < textLength && lineNum < targetLine {
            let info = lineInfo(at: currentOffset, in: nsString)
            // `info.end` includes the line terminator; the next line begins there.
            if info.end <= currentOffset { break } // guard against zero-length step
            currentOffset = info.end
            lineNum += 1
        }
        return min(currentOffset, textLength)
    }

    // MARK: - Vertical (h/j/k/l up/down)

    private enum VerticalDirection { case up, down }

    private static func verticalMove(
        from location: Int,
        direction: VerticalDirection,
        count: Int,
        in nsString: NSString
    ) -> Int {
        var current = location
        for _ in 0..<count {
            let cur = lineInfo(at: current, in: nsString)
            let column = current - cur.start
            switch direction {
            case .up:
                guard cur.start > 0 else { return current }
                let prev = lineInfo(at: cur.start - 1, in: nsString)
                let prevContentLen = prev.contentEnd - prev.start
                current = prev.start + min(column, prevContentLen)
            case .down:
                guard cur.end < nsString.length else { return current }
                let next = lineInfo(at: cur.end, in: nsString)
                let nextContentLen = next.contentEnd - next.start
                current = next.start + min(column, nextContentLen)
            }
        }
        return current
    }

    // MARK: - Word motions

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
        // Treat space, tab, line terminators, and the no-break space group
        // as whitespace. unicode scalars give us \r \n \t \v \f and \u{0020}.
        switch ch {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    private static func isKeyword(_ ch: unichar) -> Bool {
        // ASCII letter/digit/underscore. Matches vim's default 'iskeyword'
        // for English text. Unicode word handling can be layered later.
        switch ch {
        case 0x30...0x39: return true            // 0-9
        case 0x41...0x5A: return true            // A-Z
        case 0x5F:        return true            // _
        case 0x61...0x7A: return true            // a-z
        default:          return false
        }
    }

    /// `w` — start of next word.
    private static func wordForwardStart(from offset: Int, in nsString: NSString) -> Int {
        let end = nsString.length
        guard offset < end else { return offset }

        var i = offset
        let startCat = category(nsString.character(at: i))
        // Advance through the current word/non-word run.
        if startCat != .whitespace {
            while i < end && category(nsString.character(at: i)) == startCat {
                i += 1
            }
        }
        // Skip whitespace to land on the next word's first char.
        while i < end && category(nsString.character(at: i)) == .whitespace {
            i += 1
        }
        return i
    }

    /// `b` — start of previous word.
    private static func wordBackward(from offset: Int, in nsString: NSString) -> Int {
        guard offset > 0 else { return 0 }
        var i = offset - 1
        // Skip whitespace going backward.
        while i > 0 && category(nsString.character(at: i)) == .whitespace {
            i -= 1
        }
        if category(nsString.character(at: i)) == .whitespace {
            return 0
        }
        // Walk back through the current word/non-word run to its start.
        let cat = category(nsString.character(at: i))
        while i > 0 && category(nsString.character(at: i - 1)) == cat {
            i -= 1
        }
        return i
    }

    /// `e` — end (last char) of current or next word.
    private static func wordForwardEnd(from offset: Int, in nsString: NSString) -> Int {
        let end = nsString.length
        guard end > 0 else { return 0 }
        guard offset < end - 1 else { return min(offset, end - 1) }

        var i = offset + 1
        // Skip whitespace forward.
        while i < end && category(nsString.character(at: i)) == .whitespace {
            i += 1
        }
        if i >= end { return min(offset, end - 1) }
        // Walk forward to the last char of the current word/non-word run.
        let cat = category(nsString.character(at: i))
        while i + 1 < end && category(nsString.character(at: i + 1)) == cat {
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
