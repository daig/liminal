import Foundation

struct VimPasteResult {
    let range: NSRange
    let replacementString: String
    let cursorAnchor: Int
    let linewise: Bool
}

enum VimPasteResolver {
    static func pasteResult(
        for payload: VimPastePayload,
        placement: VimPastePlacement,
        count: Int?,
        in text: NSString,
        from position: Int
    ) -> VimPasteResult? {
        guard !payload.text.isEmpty else { return nil }

        let effectiveCount = max(count ?? 1, 1)

        switch payload.style {
        case .characterwise:
            return characterwisePasteResult(
                for: payload.text,
                placement: placement,
                count: effectiveCount,
                in: text,
                from: position
            )
        case .linewise:
            return linewisePasteResult(
                for: payload.text,
                placement: placement,
                count: effectiveCount,
                in: text,
                from: position
            )
        }
    }

    static func replaceSelectionResult(
        for payload: VimPastePayload,
        replacing selection: VimSelectionResult,
        count: Int?
    ) -> VimPasteResult? {
        guard !payload.text.isEmpty else { return nil }

        let effectiveCount = max(count ?? 1, 1)
        let replacementString: String

        switch payload.style {
        case .characterwise:
            replacementString = repeatedText(payload.text, count: effectiveCount)
        case .linewise:
            replacementString = repeatedLinewiseText(payload.text, count: effectiveCount)
        }

        guard !replacementString.isEmpty else { return nil }

        let insertedLength = (replacementString as NSString).length
        let cursorAnchor = selection.range.location + max(insertedLength - 1, 0)

        return VimPasteResult(
            range: selection.range,
            replacementString: replacementString,
            cursorAnchor: cursorAnchor,
            linewise: payload.style == .linewise
        )
    }

    private static func characterwisePasteResult(
        for textToPaste: String,
        placement: VimPastePlacement,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimPasteResult? {
        let insertionLocation = characterwiseInsertionLocation(
            placement: placement,
            in: text,
            from: position
        )
        let repeatedText = repeatedText(textToPaste, count: count)
        let insertedLength = (repeatedText as NSString).length

        guard insertedLength > 0 else { return nil }

        return VimPasteResult(
            range: NSRange(location: insertionLocation, length: 0),
            replacementString: repeatedText,
            cursorAnchor: insertionLocation + insertedLength - 1,
            linewise: false
        )
    }

    private static func linewisePasteResult(
        for textToPaste: String,
        placement: VimPastePlacement,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimPasteResult? {
        let insertionLocation = linewiseInsertionLocation(
            placement: placement,
            in: text,
            from: position
        )
        let repeatedText = repeatedLinewiseText(textToPaste, count: count)
        let needsLeadingNewline =
            insertionLocation > 0
            && text.character(at: insertionLocation - 1) != 0x0A
        let needsTrailingNewline =
            insertionLocation < text.length
            && !repeatedText.hasSuffix("\n")

        let replacementString =
            (needsLeadingNewline ? "\n" : "")
            + repeatedText
            + (needsTrailingNewline ? "\n" : "")

        guard !replacementString.isEmpty else { return nil }

        let cursorAnchor = insertionLocation + (needsLeadingNewline ? 1 : 0)

        return VimPasteResult(
            range: NSRange(location: insertionLocation, length: 0),
            replacementString: replacementString,
            cursorAnchor: cursorAnchor,
            linewise: true
        )
    }

    private static func characterwiseInsertionLocation(
        placement: VimPastePlacement,
        in text: NSString,
        from position: Int
    ) -> Int {
        guard text.length > 0 else { return 0 }

        switch placement {
        case .afterCursor:
            let currentPosition = clamp(position, in: text)
            if text.character(at: currentPosition) == 0x0A {
                return currentPosition
            }

            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            return min(currentPosition + 1, lineContentUpperBound(of: lineRange, in: text))
        case .beforeCursor:
            return max(0, min(position, text.length))
        }
    }

    private static func linewiseInsertionLocation(
        placement: VimPastePlacement,
        in text: NSString,
        from position: Int
    ) -> Int {
        guard text.length > 0 else { return 0 }

        let currentPosition = clamp(position, in: text)
        let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))

        switch placement {
        case .afterCursor:
            return NSMaxRange(lineRange)
        case .beforeCursor:
            return lineRange.location
        }
    }

    private static func repeatedText(_ text: String, count: Int) -> String {
        var result = ""
        result.reserveCapacity((text as NSString).length * count)

        for _ in 0..<count {
            result += text
        }

        return result
    }

    private static func repeatedLinewiseText(_ text: String, count: Int) -> String {
        var result = ""

        for index in 0..<count {
            if index > 0 && !result.hasSuffix("\n") {
                result += "\n"
            }
            result += text
        }

        return result
    }

    private static func lineContentUpperBound(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return lineRange.location }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(lineRange)
    }

    private static func clamp(_ position: Int, in text: NSString) -> Int {
        max(0, min(position, max(text.length - 1, 0)))
    }
}
