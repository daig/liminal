import Foundation

struct VimVisualState: Equatable {
    let kind: VimVisualKind
    let anchorPosition: Int
    let headPosition: Int

    var mode: VimMode {
        kind.mode
    }

    var cursorPosition: Int {
        headPosition
    }

    static func begin(
        kind: VimVisualKind,
        at cursorPosition: Int,
        in text: NSString
    ) -> VimVisualState {
        let clampedPosition = clamp(cursorPosition, in: text)
        return VimVisualState(
            kind: kind,
            anchorPosition: clampedPosition,
            headPosition: clampedPosition
        )
    }

    func changingKind(
        to kind: VimVisualKind,
        in text: NSString
    ) -> VimVisualState {
        VimVisualState(
            kind: kind,
            anchorPosition: Self.clamp(anchorPosition, in: text),
            headPosition: Self.clamp(headPosition, in: text)
        )
    }

    func movingHead(
        to position: Int,
        in text: NSString
    ) -> VimVisualState {
        VimVisualState(
            kind: kind,
            anchorPosition: Self.clamp(anchorPosition, in: text),
            headPosition: Self.clamp(position, in: text)
        )
    }

    func selection(in text: NSString) -> VimSelectionResult? {
        guard text.length > 0 else { return nil }

        let clampedAnchor = Self.clamp(anchorPosition, in: text)
        let clampedHead = Self.clamp(headPosition, in: text)

        switch kind {
        case .characterwise:
            let lowerBound = Swift.min(clampedAnchor, clampedHead)
            let upperBound = Swift.max(clampedAnchor, clampedHead) + 1
            let range = NSRange(location: lowerBound, length: upperBound - lowerBound)
            return range.length > 0
                ? VimSelectionResult(range: range, cursorAnchor: range.location, linewise: false)
                : nil
        case .linewise:
            let anchorLine = text.lineRange(for: NSRange(location: clampedAnchor, length: 0))
            let headLine = text.lineRange(for: NSRange(location: clampedHead, length: 0))
            let startLocation = Swift.min(anchorLine.location, headLine.location)
            let endLocation = Swift.max(NSMaxRange(anchorLine), NSMaxRange(headLine))
            let range = NSRange(location: startLocation, length: endLocation - startLocation)
            return range.length > 0
                ? VimSelectionResult(range: range, cursorAnchor: startLocation, linewise: true)
                : nil
        }
    }

    func displayRange(in text: NSString) -> NSRange {
        selection(in: text)?.range ?? NSRange(location: 0, length: 0)
    }

    private static func clamp(_ position: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        return max(0, min(position, text.length - 1))
    }
}
