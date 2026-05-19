import CambiumCore
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
        in source: CambiumSource,
        cursor: Int,
        count: Int
    ) -> Result {
        let textLength = source.utf16Count
        let safeCursor = max(0, min(cursor, textLength))
        let effectiveCount = max(1, count)

        switch target {
        case .motion(let motion):
            return resolveMotion(
                op: op, motion: motion,
                in: source, cursor: safeCursor,
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
                op: op, in: source,
                cursor: safeCursor, count: effectiveCount
            )
        case .charsAtCursor(let before):
            return resolveCharsAtCursor(
                in: source, cursor: safeCursor,
                count: effectiveCount, before: before
            )
        case .toLineEnd:
            return resolveToLineEnd(
                op: op, in: source, cursor: safeCursor
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
        in source: CambiumSource,
        cursor: Int,
        count: Int
    ) -> Result {
        let target = CursorMotionEngine.newOffset(
            for: motion, source: source,
            from: cursor, count: count
        )
        let inc = inclusivity(motion)

        if inc == .linewise {
            let lo = min(cursor, target)
            let hi = max(cursor, target)
            let firstLine = lineInfo(at: lo, in: source)
            let lastLine = lineInfo(at: hi, in: source)
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
        hi = min(hi, source.utf16Count)
        return Result(
            range: NSRange(location: lo, length: max(0, hi - lo)),
            kind: .characterwise
        )
    }

    // MARK: - currentLine target (`dd` / `cc` / `yy`)

    private static func resolveCurrentLine(
        op: VimOperator,
        in source: CambiumSource,
        cursor: Int,
        count: Int
    ) -> Result {
        let firstLine = lineInfo(at: cursor, in: source)
        var lastLine = firstLine
        var pos = firstLine.end
        var consumed = 1
        while consumed < count, pos < source.utf16Count {
            let info = lineInfo(at: pos, in: source)
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
        in source: CambiumSource,
        cursor: Int,
        count: Int,
        before: Bool
    ) -> Result {
        let line = lineInfo(at: cursor, in: source)
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
        in source: CambiumSource,
        cursor: Int
    ) -> Result {
        let line = lineInfo(at: cursor, in: source)
        return Result(
            range: NSRange(
                location: cursor,
                length: max(0, line.contentEnd - cursor)
            ),
            kind: .characterwise
        )
    }

    // MARK: - Line helper (rope-native)

    /// (start, contentEnd, end) UTF-16 offsets for the line containing
    /// `location`. Recognizes `\n` and `\r\n`; bare `\r` and exotic
    /// separators (U+2028 etc.) are treated as content. Matches the
    /// `lineInfo` shape in CursorMotionEngine.
    private static func lineInfo(
        at location: Int,
        in source: CambiumSource
    ) -> (start: Int, contentEnd: Int, end: Int) {
        let totalUTF16 = source.utf16Count
        let totalBytes = source.byteCount
        if totalBytes == 0 { return (0, 0, 0) }
        let safeOffset = max(0, min(location, totalUTF16))
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

        let contentEndUTF16: Int
        if endByte > startByte {
            let probeStart = max(startByte, endByte - 2)
            let probe = source.bytes(in: CambiumCore.TextRange(
                start: TextSize(UInt32(probeStart)),
                end: TextSize(UInt32(endByte))
            ))
            if let last = probe.last, last == 0x0A {
                if probe.count >= 2, probe[probe.count - 2] == 0x0D {
                    contentEndUTF16 = endUTF16 - 2  // CRLF
                } else {
                    contentEndUTF16 = endUTF16 - 1  // LF only
                }
            } else {
                contentEndUTF16 = endUTF16
            }
        } else {
            contentEndUTF16 = endUTF16
        }

        return (startUTF16, contentEndUTF16, endUTF16)
    }
}
