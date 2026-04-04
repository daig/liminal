import Foundation

struct VimSelectionResult {
    let range: NSRange
    let cursorAnchor: Int
    let linewise: Bool
}

enum VimSelectionResolver {
    static func selectionResult(
        for target: VimOperatorTarget,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?
    ) -> VimSelectionResult? {
        guard text.length > 0 else { return nil }

        let currentPosition = clamp(position, in: text)

        switch target {
        case .currentLines(let count):
            return selectCurrentLines(
                count: max(count ?? 1, 1),
                in: text,
                from: currentPosition
            )
        case .characterwise(let motion, let count):
            return selectCharacterwise(
                motion: motion,
                count: max(count ?? 1, 1),
                in: text,
                from: currentPosition
            )
        case .linewise(let motion, let count):
            return selectLinewise(
                motion: motion,
                count: count,
                in: text,
                from: currentPosition,
                preferredColumn: preferredColumn
            )
        }
    }

    static func visualSelectionResult(
        kind: VimVisualKind,
        in text: NSString,
        anchor: Int,
        head: Int
    ) -> VimSelectionResult? {
        guard text.length > 0 else { return nil }

        let clampedAnchor = clamp(anchor, in: text)
        let clampedHead = clamp(head, in: text)

        switch kind {
        case .characterwise:
            let lowerBound = min(clampedAnchor, clampedHead)
            let upperBound = max(clampedAnchor, clampedHead) + 1
            let range = NSRange(location: lowerBound, length: upperBound - lowerBound)
            return range.length > 0
                ? VimSelectionResult(range: range, cursorAnchor: range.location, linewise: false)
                : nil
        case .linewise:
            let anchorLine = text.lineRange(for: NSRange(location: clampedAnchor, length: 0))
            let headLine = text.lineRange(for: NSRange(location: clampedHead, length: 0))
            let startLocation = min(anchorLine.location, headLine.location)
            let endLocation = max(NSMaxRange(anchorLine), NSMaxRange(headLine))
            let range = NSRange(location: startLocation, length: endLocation - startLocation)
            return range.length > 0
                ? VimSelectionResult(range: range, cursorAnchor: startLocation, linewise: true)
                : nil
        }
    }

    private static func selectCurrentLines(
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        let startLine = text.lineRange(for: NSRange(location: position, length: 0))
        var endLine = startLine

        for _ in 1..<count {
            let nextLocation = NSMaxRange(endLine)
            guard nextLocation < text.length else { break }
            endLine = text.lineRange(for: NSRange(location: nextLocation, length: 0))
        }

        let range = NSRange(
            location: startLine.location,
            length: NSMaxRange(endLine) - startLine.location
        )
        return range.length > 0
            ? VimSelectionResult(range: range, cursorAnchor: startLine.location, linewise: true)
            : nil
    }

    private static func selectCharacterwise(
        motion: VimTextMotion,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
        let lineLowerBound = lineRange.location
        let lineUpperBound = lineContentUpperBound(of: lineRange, in: text)

        let range: NSRange?

        switch motion {
        case .left:
            let start = max(lineLowerBound, position - count)
            range = nsRange(from: start, toExclusive: position)
        case .right:
            let end = min(lineUpperBound, position + count)
            range = nsRange(from: position, toExclusive: end)
        case .targetPosition(let targetPosition):
            let destination = VimNavigator.normalizedPosition(targetPosition, in: text)
            guard destination != position else { return nil }

            let lowerBound = min(position, destination)
            let upperBound = min(max(position, destination) + 1, text.length)
            range = nsRange(from: lowerBound, toExclusive: upperBound)
        case .lineStart:
            range = nsRange(from: lineLowerBound, toExclusive: position)
        case .lineFirstNonBlank:
            range = nsRange(
                from: firstNonBlank(in: lineRange, text: text),
                toExclusive: position
            )
        case .lineEnd:
            let destination = VimNavigator.destination(
                for: .lineEnd,
                count: count,
                in: text,
                from: position,
                preferredColumn: nil
            ).position
            range = nsRange(
                from: position,
                toExclusive: min(destination + 1, text.length)
            )
        case .wordForward:
            range = nsRange(
                from: position,
                toExclusive: wordForwardSelectionEndpoint(
                    from: position,
                    count: count,
                    in: text,
                    lineRange: lineRange
                )
            )
        case .wordBackward:
            range = nsRange(
                from: wordBackwardSelectionStart(
                    from: position,
                    count: count,
                    in: text,
                    lineRange: lineRange
                ),
                toExclusive: position
            )
        case .wordEndForward:
            let inclusiveEnd = wordEndSelectionInclusiveEnd(
                from: position,
                count: count,
                in: text,
                lineRange: lineRange
            )
            range = nsRange(from: position, toExclusive: inclusiveEnd + 1)
        case .characterSearch(let search):
            range = characterSearchSelectionRange(
                for: search,
                count: count,
                in: text,
                from: position,
                lineLowerBound: lineLowerBound,
                lineUpperBound: lineUpperBound
            )
        case .repeatCharacterSearch:
            return nil
        case .up, .down, .goToLine, .paragraphForward, .paragraphBackward:
            return nil
        }

        guard let range, range.length > 0 else { return nil }
        return VimSelectionResult(range: range, cursorAnchor: range.location, linewise: false)
    }

    private static func selectLinewise(
        motion: VimTextMotion,
        count: Int?,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?
    ) -> VimSelectionResult? {
        let targetPosition: Int

        switch motion {
        case .up, .down, .goToLine, .paragraphForward, .paragraphBackward:
            targetPosition = VimNavigator.destination(
                for: motion,
                count: count,
                in: text,
                from: position,
                preferredColumn: preferredColumn
            ).position
        default:
            return nil
        }

        let currentLine = text.lineRange(for: NSRange(location: position, length: 0))
        let targetLine = text.lineRange(for: NSRange(location: targetPosition, length: 0))
        let startLocation = min(currentLine.location, targetLine.location)
        let endLocation = max(NSMaxRange(currentLine), NSMaxRange(targetLine))
        let range = NSRange(location: startLocation, length: endLocation - startLocation)

        guard range.length > 0 else { return nil }
        return VimSelectionResult(range: range, cursorAnchor: startLocation, linewise: true)
    }

    private static func wordForwardSelectionEndpoint(
        from position: Int,
        count: Int,
        in text: NSString,
        lineRange: NSRange
    ) -> Int {
        let lineUpperBound = lineContentUpperBound(of: lineRange, in: text)
        var currentPosition = position

        for _ in 0..<count {
            let nextWordStart = nextWordStart(in: text, from: currentPosition, upperBound: lineUpperBound)

            if nextWordStart == nil {
                return lineUpperBound
            }

            currentPosition = nextWordStart!
        }

        return currentPosition
    }

    private static func wordBackwardSelectionStart(
        from position: Int,
        count: Int,
        in text: NSString,
        lineRange: NSRange
    ) -> Int {
        var currentPosition = position

        for _ in 0..<count {
            currentPosition = previousWordStart(
                in: text,
                from: currentPosition,
                lowerBound: lineRange.location
            )
        }

        return currentPosition
    }

    private static func wordEndSelectionInclusiveEnd(
        from position: Int,
        count: Int,
        in text: NSString,
        lineRange: NSRange
    ) -> Int {
        let upperBound = lineContentUpperBound(of: lineRange, in: text)
        var currentPosition = position

        for _ in 0..<count {
            currentPosition = endOfCurrentOrNextWord(
                in: text,
                from: currentPosition,
                upperBound: upperBound
            )
        }

        return currentPosition
    }

    private static func characterSearchSelectionRange(
        for search: VimCharacterSearch,
        count: Int,
        in text: NSString,
        from position: Int,
        lineLowerBound: Int,
        lineUpperBound: Int
    ) -> NSRange? {
        let destination = characterSearchSelectionDestination(
            for: search,
            count: count,
            in: text,
            from: position,
            lineLowerBound: lineLowerBound,
            lineUpperBound: lineUpperBound
        )

        guard let destination else { return nil }

        switch search.direction {
        case .forward:
            return nsRange(from: position, toExclusive: destination + 1)
        case .backward:
            return nsRange(from: destination, toExclusive: position + 1)
        }
    }

    private static func characterSearchSelectionDestination(
        for search: VimCharacterSearch,
        count: Int,
        in text: NSString,
        from position: Int,
        lineLowerBound: Int,
        lineUpperBound: Int
    ) -> Int? {
        let target = String(search.character)
        let targetLength = (target as NSString).length
        guard targetLength > 0 else { return nil }

        var remaining = count

        switch search.direction {
        case .forward:
            var currentIndex = min(position + 1, lineUpperBound)

            while currentIndex < lineUpperBound {
                if matches(target, at: currentIndex, in: text) {
                    remaining -= 1
                    if remaining == 0 {
                        return search.kind == .to
                            ? currentIndex
                            : max(position, currentIndex - 1)
                    }
                }
                currentIndex += 1
            }
        case .backward:
            var currentIndex = position - 1

            while currentIndex >= lineLowerBound {
                if matches(target, at: currentIndex, in: text) {
                    remaining -= 1
                    if remaining == 0 {
                        return search.kind == .to
                            ? currentIndex
                            : min(position, currentIndex + targetLength)
                    }
                }
                currentIndex -= 1
            }
        }

        return nil
    }

    private static func nextWordStart(
        in text: NSString,
        from position: Int,
        upperBound: Int
    ) -> Int? {
        var currentPosition = position

        while currentPosition < upperBound
            && !isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        while currentPosition < upperBound
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        return currentPosition < upperBound ? currentPosition : nil
    }

    private static func previousWordStart(
        in text: NSString,
        from position: Int,
        lowerBound: Int
    ) -> Int {
        var currentPosition = position

        if currentPosition > lowerBound {
            currentPosition -= 1
        }

        while currentPosition > lowerBound
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition -= 1
        }

        while currentPosition > lowerBound
            && !isWordBoundary(text.character(at: currentPosition - 1))
        {
            currentPosition -= 1
        }

        return currentPosition
    }

    private static func endOfCurrentOrNextWord(
        in text: NSString,
        from position: Int,
        upperBound: Int
    ) -> Int {
        guard upperBound > 0 else { return 0 }

        var currentPosition = min(position, upperBound - 1)

        if !isWordBoundary(text.character(at: currentPosition)) {
            let nextIndex = currentPosition + 1

            if nextIndex < upperBound && !isWordBoundary(text.character(at: nextIndex)) {
                while currentPosition + 1 < upperBound
                    && !isWordBoundary(text.character(at: currentPosition + 1))
                {
                    currentPosition += 1
                }

                return currentPosition
            }

            currentPosition += 1
        }

        while currentPosition < upperBound
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        guard currentPosition < upperBound else { return upperBound - 1 }

        while currentPosition + 1 < upperBound
            && !isWordBoundary(text.character(at: currentPosition + 1))
        {
            currentPosition += 1
        }

        return currentPosition
    }

    private static func lineContentUpperBound(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return lineRange.location }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(lineRange)
    }

    private static func firstNonBlank(in range: NSRange, text: NSString) -> Int {
        let upperBound = lineContentUpperBound(of: range, in: text)
        var currentIndex = range.location

        while currentIndex < upperBound {
            let character = text.character(at: currentIndex)
            guard let scalar = Unicode.Scalar(character) else { break }
            if !CharacterSet.whitespaces.contains(scalar) {
                return currentIndex
            }
            currentIndex += 1
        }

        return range.location
    }

    private static func matches(_ target: String, at index: Int, in text: NSString) -> Bool {
        let targetLength = (target as NSString).length
        guard index >= 0, index + targetLength <= text.length else { return false }
        return text.substring(with: NSRange(location: index, length: targetLength)) == target
    }

    private static func isWordBoundary(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
            || CharacterSet.punctuationCharacters.contains(scalar)
    }

    private static func nsRange(from lowerBound: Int, toExclusive upperBound: Int) -> NSRange? {
        guard upperBound > lowerBound else { return nil }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private static func clamp(_ position: Int, in text: NSString) -> Int {
        max(0, min(position, max(text.length - 1, 0)))
    }
}
