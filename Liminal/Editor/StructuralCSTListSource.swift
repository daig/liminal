import CambiumCore

enum StructuralCSTListSource {
    enum Marker: Equatable {
        case unordered(Character)
        case ordered
    }

    static func marker(in text: String) -> Marker? {
        guard let firstLine = text.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else {
            return nil
        }
        let line = String(firstLine)
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let next = trimmed.index(after: trimmed.startIndex)
            guard next < trimmed.endIndex, isHorizontalWhitespace(trimmed[next]) else {
                return nil
            }
            return .unordered(first)
        }
        if first.isNumber {
            var cursor = trimmed.startIndex
            while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
                cursor = trimmed.index(after: cursor)
            }
            guard cursor < trimmed.endIndex, trimmed[cursor] == "." else {
                return nil
            }
            let afterDot = trimmed.index(after: cursor)
            guard afterDot < trimmed.endIndex, isHorizontalWhitespace(trimmed[afterDot]) else {
                return nil
            }
            return .ordered
        }
        return nil
    }

    static func markersAreCompatible(_ lhs: Marker, _ rhs: Marker) -> Bool {
        switch (lhs, rhs) {
        case (.unordered, .unordered), (.ordered, .ordered):
            true
        default:
            false
        }
    }

    static func normalizedMarker(
        sourceMarker: Marker,
        targetMarker: Marker
    ) -> Character? {
        switch (sourceMarker, targetMarker) {
        case (.unordered, .unordered(let marker)):
            marker
        default:
            nil
        }
    }

    static func rebase(
        _ source: String,
        sourceBaseIndent: Int,
        targetBaseIndent: Int,
        topLevelMarker: Character?
    ) -> String {
        let delta = targetBaseIndent - sourceBaseIndent
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        return lines.enumerated().map { offset, lineSub in
            var line = String(lineSub)
            if offset == lines.count - 1, line.isEmpty, source.hasSuffix("\n") {
                return line
            }
            let prefix = leadingHorizontalWhitespace(in: line)
            let oldColumn = indentationColumn(prefix)
            let newColumn = max(0, oldColumn + delta)
            line.removeFirst(prefix.count)
            if oldColumn == sourceBaseIndent, let topLevelMarker {
                line = replacingUnorderedMarker(in: line, with: topLevelMarker)
            }
            return String(repeating: " ", count: newColumn) + line
        }.joined(separator: "\n")
    }

    static func firstLineIndentColumn(in text: String) -> Int? {
        guard let firstLine = text.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else {
            return nil
        }
        return indentationColumn(leadingHorizontalWhitespace(in: String(firstLine)))
    }

    static func highlightRangesRebasedToZero(
        in source: String,
        sourceBaseIndent: Int
    ) -> [CambiumCore.TextRange] {
        highlightRanges(
            sourceByteCount: source.utf8.count,
            removing: baseIndentRemovalRanges(
                in: source,
                sourceBaseIndent: sourceBaseIndent
            )
        )
    }

    static func baseIndentRemovalRanges(
        in source: String,
        sourceBaseIndent: Int
    ) -> [CambiumCore.TextRange] {
        guard !source.isEmpty else { return [] }

        var ranges: [CambiumCore.TextRange] = []
        var lineStart = source.startIndex
        var lineStartByte = 0

        while lineStart < source.endIndex {
            var lineEnd = lineStart
            while lineEnd < source.endIndex,
                  source[lineEnd] != "\n",
                  source[lineEnd] != "\r"
            {
                lineEnd = source.index(after: lineEnd)
            }

            let contentStart = contentStartAfterRemovingBaseIndent(
                in: source,
                lineStart: lineStart,
                lineEnd: lineEnd,
                sourceBaseIndent: sourceBaseIndent
            )

            var nextLineStart = lineEnd
            if lineEnd < source.endIndex {
                if source[lineEnd] == "\r" {
                    let afterCR = source.index(after: lineEnd)
                    if afterCR < source.endIndex, source[afterCR] == "\n" {
                        nextLineStart = source.index(after: afterCR)
                    } else {
                        nextLineStart = afterCR
                    }
                } else {
                    nextLineStart = source.index(after: lineEnd)
                }
            }

            let contentStartByte = lineStartByte
                + source.utf8.distance(from: lineStart, to: contentStart)
            let nextLineStartByte = lineStartByte
                + source.utf8.distance(from: lineStart, to: nextLineStart)
            if contentStartByte > lineStartByte {
                ranges.append(CambiumCore.TextRange(
                    start: TextSize(UInt32(lineStartByte)),
                    end: TextSize(UInt32(contentStartByte))
                ))
            }

            lineStartByte = nextLineStartByte
            lineStart = nextLineStart
        }

        return ranges
    }

    static func listItemContentColumn(in source: String) -> Int? {
        guard let firstLine = source.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else {
            return nil
        }

        let line = String(firstLine)
        var cursor = line.startIndex
        var column = 0

        while cursor < line.endIndex, isHorizontalWhitespace(line[cursor]) {
            column += indentationWidth(of: line[cursor], atColumn: column)
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }

        if line[cursor] == "-" || line[cursor] == "*" || line[cursor] == "+" {
            column += 1
            cursor = line.index(after: cursor)
            guard cursor < line.endIndex,
                  isHorizontalWhitespace(line[cursor])
            else { return nil }
        } else if line[cursor].isNumber {
            repeat {
                column += 1
                cursor = line.index(after: cursor)
            } while cursor < line.endIndex && line[cursor].isNumber

            guard cursor < line.endIndex, line[cursor] == "." else {
                return nil
            }
            column += 1
            cursor = line.index(after: cursor)
            guard cursor < line.endIndex,
                  isHorizontalWhitespace(line[cursor])
            else { return nil }
        } else {
            return nil
        }

        repeat {
            column += indentationWidth(of: line[cursor], atColumn: column)
            cursor = line.index(after: cursor)
        } while cursor < line.endIndex && isHorizontalWhitespace(line[cursor])

        if let taskEnd = taskMarkerEnd(in: line, at: cursor) {
            column += line.utf8.distance(from: cursor, to: taskEnd)
            cursor = taskEnd
            if cursor < line.endIndex, isHorizontalWhitespace(line[cursor]) {
                column += indentationWidth(of: line[cursor], atColumn: column)
            }
        }

        return column
    }

    static func listItemContentRemovalRanges(
        in source: String,
        selectedByteRange: CambiumCore.TextRange,
        contentColumn: Int
    ) -> [CambiumCore.TextRange] {
        guard contentColumn > 0,
              !source.isEmpty,
              selectedByteRange.length.rawValue > 0
        else { return [] }

        let selectedStartByte = Int(selectedByteRange.start.rawValue)
        let selectedEndByte = Int(selectedByteRange.end.rawValue)
        precondition(selectedStartByte <= selectedEndByte)
        precondition(selectedEndByte <= source.utf8.count)

        // Hotspot #17: pre-rewrite this function used `utf8.index(offsetBy:)`
        // walks to convert byte offsets → String.Index, then walked the
        // resulting String character-by-character. Each conversion was
        // O(N) per the Swift String API contract. Now we materialize the
        // bytes once and operate in byte-space throughout via the
        // byte-typed helpers below.
        let bytes = Array(source.utf8)
        var lineStart = physicalLineStartByte(containing: selectedStartByte, in: bytes)
        var removals: [CambiumCore.TextRange] = []

        while lineStart < selectedEndByte {
            var lineEnd = lineStart
            while lineEnd < bytes.count,
                  bytes[lineEnd] != 0x0A,
                  bytes[lineEnd] != 0x0D
            {
                lineEnd += 1
            }

            if let contentStartByte = contentStartByte(
                after: contentColumn,
                in: bytes,
                lineStartByte: lineStart,
                lineEndByte: lineEnd
            ) {
                let removalStart = max(lineStart, selectedStartByte)
                let removalEnd = min(contentStartByte, selectedEndByte)
                if removalEnd > removalStart {
                    removals.append(CambiumCore.TextRange(
                        start: TextSize(UInt32(removalStart - selectedStartByte)),
                        length: TextSize(UInt32(removalEnd - removalStart))
                    ))
                }
            }

            lineStart = nextLineStartByte(afterLineEndingAt: lineEnd, in: bytes)
        }

        return removals
    }

    /// Byte-space variant of `physicalLineStart`. Walks backward through
    /// `bytes` from `offset` to the byte just after the most recent
    /// `\n` or `\r`.
    private static func physicalLineStartByte(
        containing offset: Int,
        in bytes: [UInt8]
    ) -> Int {
        var cursor = offset
        while cursor > 0 {
            let previous = cursor - 1
            if bytes[previous] == 0x0A || bytes[previous] == 0x0D {
                return cursor
            }
            cursor = previous
        }
        return 0
    }

    /// Byte-space variant of `nextLineStart`. Returns the byte offset
    /// of the line following the one ending at `lineEndByte`.
    private static func nextLineStartByte(
        afterLineEndingAt lineEndByte: Int,
        in bytes: [UInt8]
    ) -> Int {
        guard lineEndByte < bytes.count else { return lineEndByte }
        if bytes[lineEndByte] == 0x0D {
            let afterCR = lineEndByte + 1
            if afterCR < bytes.count, bytes[afterCR] == 0x0A {
                return afterCR + 1
            }
            return afterCR
        }
        return lineEndByte + 1
    }

    /// Byte-space variant of `contentStart`. Walks through horizontal
    /// whitespace (ASCII space + tab) at the start of the line,
    /// computing the visual column. Returns the byte offset where
    /// content begins after consuming `targetColumn` columns.
    private static func contentStartByte(
        after targetColumn: Int,
        in bytes: [UInt8],
        lineStartByte: Int,
        lineEndByte: Int
    ) -> Int? {
        var cursor = lineStartByte
        var column = 0
        while cursor < lineEndByte {
            let byte = bytes[cursor]
            // Only ASCII space (0x20) and tab (0x09) are horizontal
            // whitespace per the existing `isHorizontalWhitespace`
            // semantics; anything else (incl. multi-byte UTF-8 chars)
            // is non-whitespace and stops the walk.
            guard byte == 0x20 || byte == 0x09 else { break }
            let nextColumn = column + indentationByteWidth(of: byte, atColumn: column)
            guard nextColumn <= targetColumn else { return cursor }
            column = nextColumn
            cursor += 1
            if column == targetColumn { return cursor }
        }
        return column >= targetColumn ? cursor : nil
    }

    /// Byte-space variant of `indentationWidth`. Space = 1 column, tab
    /// = expand to next tab stop (multiples of 4 per the existing
    /// `indentationWidth` semantics).
    private static func indentationByteWidth(of byte: UInt8, atColumn column: Int) -> Int {
        switch byte {
        case 0x20: return 1
        case 0x09: return 4 - (column % 4)
        default:   return 0
        }
    }

    static func highlightRanges(
        sourceByteCount: Int,
        removing removalRanges: [CambiumCore.TextRange]
    ) -> [CambiumCore.TextRange] {
        guard sourceByteCount > 0 else { return [] }

        var ranges: [CambiumCore.TextRange] = []
        var cursor = 0
        for removal in removalRanges {
            let start = Int(removal.start.rawValue)
            let end = Int(removal.end.rawValue)
            if start > cursor {
                ranges.append(CambiumCore.TextRange(
                    start: TextSize(UInt32(cursor)),
                    end: TextSize(UInt32(start))
                ))
            }
            cursor = max(cursor, end)
        }
        if cursor < sourceByteCount {
            ranges.append(CambiumCore.TextRange(
                start: TextSize(UInt32(cursor)),
                end: TextSize(UInt32(sourceByteCount))
            ))
        }
        return ranges
    }

    private static func contentStartAfterRemovingBaseIndent(
        in source: String,
        lineStart: String.Index,
        lineEnd: String.Index,
        sourceBaseIndent: Int
    ) -> String.Index {
        guard sourceBaseIndent > 0 else { return lineStart }

        var cursor = lineStart
        var column = 0
        while cursor < lineEnd, isHorizontalWhitespace(source[cursor]) {
            let width = indentationWidth(of: source[cursor], atColumn: column)
            guard column + width <= sourceBaseIndent else { break }
            column += width
            cursor = source.index(after: cursor)
            if column >= sourceBaseIndent { break }
        }
        return cursor
    }

    private static func contentStart(
        after targetColumn: Int,
        in source: String,
        lineStart: String.Index,
        lineEnd: String.Index
    ) -> String.Index? {
        var cursor = lineStart
        var column = 0
        while cursor < lineEnd, isHorizontalWhitespace(source[cursor]) {
            let nextColumn = column + indentationWidth(
                of: source[cursor],
                atColumn: column
            )
            guard nextColumn <= targetColumn else { return cursor }
            column = nextColumn
            cursor = source.index(after: cursor)
            if column == targetColumn { return cursor }
        }
        return column >= targetColumn ? cursor : nil
    }

    private static func physicalLineStart(
        containing index: String.Index,
        in source: String
    ) -> String.Index {
        var cursor = index
        while cursor > source.startIndex {
            let previous = source.index(before: cursor)
            if source[previous] == "\n" || source[previous] == "\r" {
                return cursor
            }
            cursor = previous
        }
        return source.startIndex
    }

    private static func nextLineStart(
        afterLineEndingAt lineEnd: String.Index,
        in source: String
    ) -> String.Index {
        guard lineEnd < source.endIndex else { return lineEnd }
        if source[lineEnd] == "\r" {
            let afterCR = source.index(after: lineEnd)
            if afterCR < source.endIndex, source[afterCR] == "\n" {
                return source.index(after: afterCR)
            }
            return afterCR
        }
        return source.index(after: lineEnd)
    }

    private static func taskMarkerEnd(
        in line: String,
        at cursor: String.Index
    ) -> String.Index? {
        guard cursor < line.endIndex, line[cursor] == "[" else {
            return nil
        }
        let markIndex = line.index(after: cursor)
        guard markIndex < line.endIndex else { return nil }
        let closeIndex = line.index(after: markIndex)
        guard closeIndex < line.endIndex,
              line[closeIndex] == "]",
              line[markIndex] == " "
                || line[markIndex] == "x"
                || line[markIndex] == "X"
        else {
            return nil
        }
        return line.index(after: closeIndex)
    }

    private static func replacingUnorderedMarker(
        in line: String,
        with marker: Character
    ) -> String {
        guard let first = line.first,
              first == "-" || first == "*" || first == "+"
        else { return line }
        var copy = line
        copy.replaceSubrange(copy.startIndex...copy.startIndex, with: String(marker))
        return copy
    }

    private static func leadingHorizontalWhitespace(in line: String) -> String {
        String(line.prefix { isHorizontalWhitespace($0) })
    }

    private static func indentationColumn(_ whitespace: String) -> Int {
        var column = 0
        for character in whitespace {
            column += indentationWidth(of: character, atColumn: column)
        }
        return column
    }

    private static func indentationWidth(
        of character: Character,
        atColumn column: Int
    ) -> Int {
        character == "\t" ? 4 - (column % 4) : 1
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}
