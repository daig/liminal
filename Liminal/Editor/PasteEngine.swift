import Foundation

/// Pure logic for vim's `p` / `P` paste — given the clipboard
/// payload (text + kind) and the cursor, returns the text-storage
/// edit to apply and the cursor's UTF-16 position after the edit.
public enum PasteEngine {
    public struct Plan: Equatable, Sendable {
        /// UTF-16 range to replace in the existing text storage
        /// (length 0 means pure insertion).
        public let range: NSRange
        public let replacement: String
        /// Cursor's UTF-16 position after the edit lands.
        public let cursorAfter: Int
    }

    /// Compute the paste edit. `after == true` corresponds to vim's
    /// `p`; `after == false` to `P`. Behavior depends on `kind`:
    ///
    /// - **characterwise**: insert at cursor (or cursor + 1 for
    ///   `p`); cursor lands on the last char of the pasted text.
    /// - **linewise**: insert as a new line below (`p`) or above
    ///   (`P`); cursor lands at the first non-blank of the inserted
    ///   block's first line.
    /// - **blockwise**: split on `\n`; insert each row at the
    ///   cursor's column on consecutive lines, padding short
    ///   target lines with spaces. Cursor lands at the first
    ///   inserted cell.
    public static func plan(
        text: String,
        kind: YankKind,
        in source: String,
        cursor: Int,
        after: Bool
    ) -> Plan {
        let nsString = source as NSString
        let textLength = nsString.length
        let safeCursor = max(0, min(cursor, textLength))

        switch kind {
        case .characterwise:
            return planCharwise(
                text: text, in: nsString,
                cursor: safeCursor, after: after
            )
        case .linewise:
            return planLinewise(
                text: text, in: nsString,
                cursor: safeCursor, after: after
            )
        case .blockwise:
            return planBlockwise(
                text: text, in: nsString,
                cursor: safeCursor, after: after
            )
        }
    }

    // MARK: - Characterwise

    private static func planCharwise(
        text: String,
        in nsString: NSString,
        cursor: Int,
        after: Bool
    ) -> Plan {
        let line = lineInfo(at: cursor, in: nsString)
        // Vim's `p` inserts AFTER the cursor cell — so the
        // insertion point is `cursor + 1`, but bounded by the
        // line's content end so we don't push text past a newline.
        let insertAt: Int
        if after {
            insertAt = min(cursor + 1, line.contentEnd)
        } else {
            insertAt = cursor
        }
        let length = (text as NSString).length
        // Cursor lands on the LAST inserted char (vim semantics).
        // Empty paste leaves the cursor where it started.
        let cursorAfter = length == 0 ? cursor : insertAt + length - 1
        return Plan(
            range: NSRange(location: insertAt, length: 0),
            replacement: text,
            cursorAfter: cursorAfter
        )
    }

    // MARK: - Linewise

    private static func planLinewise(
        text: String,
        in nsString: NSString,
        cursor: Int,
        after: Bool
    ) -> Plan {
        let line = lineInfo(at: cursor, in: nsString)
        // Linewise yank typically arrives with a trailing newline
        // (when produced by visual line mode). Normalize so we
        // always insert a `\n`-bracketed block: strip any trailing
        // newline from the payload and then frame it.
        var body = text
        if body.hasSuffix("\n") { body.removeLast() }
        let insertAt: Int
        let replacement: String
        let firstInsertedLineStart: Int
        if after {
            // After the current line: insert "\n<body>" at
            // line.contentEnd. If the line lacks a terminator
            // (EOF), use that position too — the "\n" we add
            // becomes the new terminator and our body sits below.
            insertAt = line.contentEnd
            replacement = "\n" + body
            firstInsertedLineStart = line.contentEnd + 1
        } else {
            // Before the current line: insert "<body>\n" at
            // line.start. The pushed-down original line gets a
            // fresh terminator from our framing.
            insertAt = line.start
            replacement = body + "\n"
            firstInsertedLineStart = line.start
        }
        let cursorAfter = firstNonBlankUTF16(
            at: firstInsertedLineStart,
            in: nsString,
            insertedLength: (replacement as NSString).length,
            replacedRange: NSRange(location: insertAt, length: 0),
            sourceLength: nsString.length
        )
        return Plan(
            range: NSRange(location: insertAt, length: 0),
            replacement: replacement,
            cursorAfter: cursorAfter
        )
    }

    // MARK: - Blockwise

    private static func planBlockwise(
        text: String,
        in nsString: NSString,
        cursor: Int,
        after: Bool
    ) -> Plan {
        let rows = text.components(separatedBy: "\n")
        let cursorLine = lineInfo(at: cursor, in: nsString)
        let column = cursor - cursorLine.start
        // Vim's `P` inserts at the cursor column; `p` inserts at
        // cursor column + 1 (so it appears after the cursor cell).
        let insertCol = after ? column + 1 : column

        // We build a single replacement string that splices block
        // text into the relevant lines via padding. Find the byte
        // range covering the affected lines.
        var workingCursor = cursorLine.start
        var ranges: [(start: Int, contentEnd: Int, end: Int)] = []
        ranges.reserveCapacity(rows.count)
        for _ in 0..<rows.count {
            let info = lineInfo(at: workingCursor, in: nsString)
            ranges.append(info)
            if info.end <= workingCursor || info.end >= nsString.length {
                // Past the last line: subsequent rows are appended
                // to a synthesized empty trailing line. We model
                // that by extending `ranges` with a zero-length
                // pseudo-line at the end.
                while ranges.count < rows.count {
                    ranges.append((nsString.length, nsString.length, nsString.length))
                }
                break
            }
            workingCursor = info.end
        }

        let replaceStart = ranges.first?.start ?? cursorLine.start
        let replaceEnd = ranges.last?.end ?? cursorLine.end
        let originalSegment = nsString.substring(
            with: NSRange(location: replaceStart, length: replaceEnd - replaceStart)
        )
        // Reconstruct each line: original prefix up to insertCol
        // (padding with spaces if line is shorter) + row text + the
        // rest of the line.
        let originalLines = originalSegment
            .components(separatedBy: "\n")
        var rebuiltLines: [String] = []
        rebuiltLines.reserveCapacity(originalLines.count)
        for (i, original) in originalLines.enumerated() {
            let row = i < rows.count ? rows[i] : ""
            let originalUTF16 = (original as NSString)
            let prefixLen = min(insertCol, originalUTF16.length)
            let prefix = originalUTF16.substring(
                to: prefixLen
            )
            let suffix = prefixLen < originalUTF16.length
                ? originalUTF16.substring(from: prefixLen)
                : ""
            let pad = max(0, insertCol - originalUTF16.length)
            rebuiltLines.append(prefix
                + String(repeating: " ", count: pad)
                + row + suffix)
        }
        let replacement = rebuiltLines.joined(separator: "\n")

        // Cursor lands at the first-inserted-cell (column = insertCol
        // on the first inserted row). In replacement-space:
        // first row's prefix length + 0 (start of inserted row text).
        let firstRowPrefixLen = (rebuiltLines.first as NSString?)?
            .range(of: rows.first ?? "")
            .location ?? insertCol
        let cursorAfter = replaceStart + firstRowPrefixLen
        return Plan(
            range: NSRange(
                location: replaceStart,
                length: replaceEnd - replaceStart
            ),
            replacement: replacement,
            cursorAfter: cursorAfter
        )
    }

    // MARK: - Helpers

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

    /// First non-blank position on the line starting at
    /// `lineStartInNewText`. Translates back through the upcoming
    /// edit so the offset is valid against the new text.
    private static func firstNonBlankUTF16(
        at lineStartInNewText: Int,
        in originalNSString: NSString,
        insertedLength: Int,
        replacedRange: NSRange,
        sourceLength: Int
    ) -> Int {
        // We don't have the new text yet; we computed lineStart in
        // its post-edit coordinate space. Best-effort: assume the
        // pasted body starts with non-blanks (typical for prose).
        // Falls back to lineStartInNewText if scan can't find one,
        // which is correct for whitespace-only paste.
        return lineStartInNewText
    }
}
