import Foundation

struct VimChangeResult {
    let range: NSRange?
    let replacementString: String
    let insertionLocation: Int
    let clipboardPayload: VimPastePayload?
}

enum VimChangeResolver {
    static func changeResult(
        replacing selection: VimSelectionResult,
        in text: NSString,
        from position: Int
    ) -> VimChangeResult {
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
