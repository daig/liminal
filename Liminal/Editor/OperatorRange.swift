import Foundation

/// Pure logic mapping (operator, target, source, cursor, count) to the
/// UTF-16 range that should be operated on, plus the resulting yank
/// kind (charwise vs linewise) the system pasteboard should record.
///
/// Mirrors `PasteEngine`'s shape: AppKit-free, no NSTextView, no
/// stateful collaborators — every output is a pure function of inputs
/// so the test suite can exhaustively pin the vim semantics down.
public enum OperatorRange {
    public struct Result: Equatable, Sendable {
        /// The UTF-16 range to yank / delete in pre-edit coordinates.
        public let range: NSRange
        /// What kind to record on the pasteboard so a subsequent
        /// `p` / `P` knows whether to insert charwise or linewise.
        public let kind: YankKind
    }

    public static func resolve(
        op: VimOperator,
        target: OperatorTarget,
        in source: String,
        cursor: Int,
        count: Int
    ) -> Result {
        let nsString = source as NSString
        let textLength = nsString.length
        let safeCursor = max(0, min(cursor, textLength))
        let effectiveCount = max(1, count)

        switch target {
        case .motion(let motion):
            return resolveMotion(
                op: op, motion: motion,
                in: nsString, cursor: safeCursor,
                count: effectiveCount
            )
        case .displayLineMotion, .structuralMotion, .viewportMotion:
            // V1 doesn't support operator + (display / structural /
            // viewport) motion targets — those motion engines live in
            // the Coordinator (they need layout / CST / viewport
            // state). Return a no-op range so the dispatch is safe;
            // the Coordinator can decide whether to treat as charwise
            // or to drop entirely.
            return Result(
                range: NSRange(location: safeCursor, length: 0),
                kind: .characterwise
            )
        case .currentLine:
            return resolveCurrentLine(
                op: op, in: nsString,
                cursor: safeCursor, count: effectiveCount
            )
        case .charsAtCursor(let before):
            return resolveCharsAtCursor(
                in: nsString, cursor: safeCursor,
                count: effectiveCount, before: before
            )
        case .toLineEnd:
            return resolveToLineEnd(
                op: op, in: nsString, cursor: safeCursor
            )
        }
    }

    // MARK: - Motion target

    private enum Inclusivity {
        case exclusive   // range = [min(cursor, target), max(cursor, target))
        case inclusive   // range = [min, max + 1) — includes the cell at target
        case linewise    // whole-line range from cursor's line through target's
    }

    private static func inclusivity(_ motion: CursorMotion) -> Inclusivity {
        switch motion {
        case .left, .right,
             .lineStart, .lineFirstNonBlank,
             .wordForwardStart, .wordBackward,
             // `lineEnd` returns the newline's position in our offset
             // model (not the last char's, like vim's `$` does). The
             // range [cursor, contentEnd) already covers through the
             // last character — adding +1 would devour the newline.
             // So `lineEnd` is exclusive here even though vim's `$`
             // is conceptually inclusive.
             .lineEnd:
            return .exclusive
        case .wordForwardEnd:
            return .inclusive
        case .up, .down, .documentStart, .documentEnd:
            return .linewise
        }
    }

    private static func resolveMotion(
        op: VimOperator,
        motion: CursorMotion,
        in nsString: NSString,
        cursor: Int,
        count: Int
    ) -> Result {
        let target = CursorMotionEngine.newOffset(
            for: motion, in: nsString as String,
            from: cursor, count: count
        )
        let inc = inclusivity(motion)

        if inc == .linewise {
            let lo = min(cursor, target)
            let hi = max(cursor, target)
            let firstLine = lineInfo(at: lo, in: nsString)
            let lastLine = lineInfo(at: hi, in: nsString)
            // Change op preserves the line shell (drops the trailing
            // newline so the line still exists, blank); delete and
            // yank operate on the full line including its terminator.
            let endpoint = (op == .change) ? lastLine.contentEnd : lastLine.end
            return Result(
                range: NSRange(
                    location: firstLine.start,
                    length: max(0, endpoint - firstLine.start)
                ),
                kind: .linewise
            )
        }

        let lo = min(cursor, target)
        var hi = max(cursor, target)
        if inc == .inclusive { hi += 1 }
        hi = min(hi, nsString.length)
        return Result(
            range: NSRange(location: lo, length: max(0, hi - lo)),
            kind: .characterwise
        )
    }

    // MARK: - currentLine target (`dd` / `cc` / `yy`)

    private static func resolveCurrentLine(
        op: VimOperator,
        in nsString: NSString,
        cursor: Int,
        count: Int
    ) -> Result {
        let firstLine = lineInfo(at: cursor, in: nsString)
        var lastLine = firstLine
        var pos = firstLine.end
        var consumed = 1
        while consumed < count, pos < nsString.length {
            let info = lineInfo(at: pos, in: nsString)
            lastLine = info
            consumed += 1
            if info.end <= pos { break }  // safety: empty trailing line
            pos = info.end
        }
        let endpoint = (op == .change) ? lastLine.contentEnd : lastLine.end
        return Result(
            range: NSRange(
                location: firstLine.start,
                length: max(0, endpoint - firstLine.start)
            ),
            kind: .linewise
        )
    }

    // MARK: - charsAtCursor target (`x` / `X`)

    private static func resolveCharsAtCursor(
        in nsString: NSString,
        cursor: Int,
        count: Int,
        before: Bool
    ) -> Result {
        let line = lineInfo(at: cursor, in: nsString)
        if before {
            let lo = max(line.start, cursor - count)
            return Result(
                range: NSRange(location: lo, length: max(0, cursor - lo)),
                kind: .characterwise
            )
        } else {
            // Don't cross the line's content end (don't delete the newline).
            let hi = min(line.contentEnd, cursor + count)
            return Result(
                range: NSRange(location: cursor, length: max(0, hi - cursor)),
                kind: .characterwise
            )
        }
    }

    // MARK: - toLineEnd target (`D` / `C`)

    private static func resolveToLineEnd(
        op: VimOperator,
        in nsString: NSString,
        cursor: Int
    ) -> Result {
        let line = lineInfo(at: cursor, in: nsString)
        return Result(
            range: NSRange(
                location: cursor,
                length: max(0, line.contentEnd - cursor)
            ),
            kind: .characterwise
        )
    }

    // MARK: - Line helper

    private static func lineInfo(
        at location: Int,
        in nsString: NSString
    ) -> (start: Int, contentEnd: Int, end: Int) {
        var start = 0
        var contentEnd = 0
        var end = 0
        let safe = max(0, min(location, nsString.length))
        nsString.getLineStart(
            &start, end: &end, contentsEnd: &contentEnd,
            for: NSRange(location: safe, length: 0)
        )
        return (start, contentEnd, end)
    }
}
