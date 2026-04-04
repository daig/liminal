import Foundation

struct VimChangeResult {
    let range: NSRange?
    let replacementString: String
    let insertionLocation: Int
    let clipboardPayload: VimPastePayload?
}

enum VimChangeResolver {
    static func changeResult(
        for target: VimOperatorTarget,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?
    ) -> VimChangeResult {
        guard let selection = VimSelectionResolver.selectionResult(
            for: target,
            in: text,
            from: position,
            preferredColumn: preferredColumn
        ) else {
            return VimChangeResult(
                range: nil,
                replacementString: "",
                insertionLocation: fallbackInsertionLocation(in: text, from: position),
                clipboardPayload: nil
            )
        }

        let selectedText = text.substring(with: selection.range)
        let replacementString = selection.linewise
            ? linewiseReplacementString(
                replacing: selection.range,
                in: text
            )
            : ""

        return VimChangeResult(
            range: selection.range,
            replacementString: replacementString,
            insertionLocation: selection.range.location,
            clipboardPayload: VimPastePayload(
                text: selectedText,
                style: selection.linewise ? .linewise : .characterwise
            )
        )
    }

    private static func linewiseReplacementString(
        replacing range: NSRange,
        in text: NSString
    ) -> String {
        NSMaxRange(range) < text.length ? "\n" : ""
    }

    private static func fallbackInsertionLocation(in text: NSString, from position: Int) -> Int {
        max(0, min(position, text.length))
    }
}
