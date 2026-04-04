import Foundation

struct VimNavigationResult {
    let position: Int
    let preferredColumn: Int?
}

enum VimNavigator {
    static func destination(
        for motion: VimTextMotion,
        count: Int?,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?
    ) -> VimNavigationResult {
        guard text.length > 0 else {
            return VimNavigationResult(position: 0, preferredColumn: nil)
        }

        let currentPosition = clamp(position, in: text)

        switch motion {
        case .left:
            return horizontalMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                direction: -1
            )
        case .right:
            return horizontalMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                direction: 1
            )
        case .up:
            return verticalMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: preferredColumn,
                direction: -1
            )
        case .down:
            return verticalMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: preferredColumn,
                direction: 1
            )
        case .lineStart:
            return VimNavigationResult(
                position: text.lineRange(for: NSRange(location: currentPosition, length: 0))
                    .location,
                preferredColumn: nil
            )
        case .lineFirstNonBlank:
            return VimNavigationResult(
                position: firstNonBlankInLogicalLine(from: currentPosition, in: text),
                preferredColumn: nil
            )
        case .lineEnd:
            return VimNavigationResult(
                position: lineEndPosition(from: currentPosition, in: text, count: count ?? 1),
                preferredColumn: nil
            )
        case .wordForward:
            return repeatedMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: nil,
                move: moveWordForward
            )
        case .wordBackward:
            return repeatedMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: nil,
                move: moveWordBackward
            )
        case .wordEndForward:
            return repeatedMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: nil,
                move: moveWordEndForward
            )
        case .goToLine(let defaultDestination):
            return VimNavigationResult(
                position: goToLine(
                    in: text,
                    destination: defaultDestination,
                    count: count
                ),
                preferredColumn: nil
            )
        case .characterSearch(let search):
            return VimNavigationResult(
                position: performCharacterSearch(
                    search,
                    from: currentPosition,
                    in: text,
                    count: count ?? 1
                ),
                preferredColumn: nil
            )
        case .repeatCharacterSearch:
            return VimNavigationResult(position: currentPosition, preferredColumn: nil)
        case .paragraphForward:
            return repeatedMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: nil,
                move: moveParagraphForward
            )
        case .paragraphBackward:
            return repeatedMove(
                from: currentPosition,
                in: text,
                count: count ?? 1,
                preferredColumn: nil,
                move: moveParagraphBackward
            )
        }
    }

    private static func horizontalMove(
        from position: Int,
        in text: NSString,
        count: Int,
        direction: Int
    ) -> VimNavigationResult {
        let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
        let lowerBound = lineRange.location
        let upperBound = lineContentUpperBound(of: lineRange, in: text)

        guard upperBound > lowerBound else {
            return VimNavigationResult(position: lowerBound, preferredColumn: nil)
        }

        let lastCharacter = upperBound - 1
        let target = max(lowerBound, min(position + (count * direction), lastCharacter))

        return VimNavigationResult(position: target, preferredColumn: nil)
    }

    private static func verticalMove(
        from position: Int,
        in text: NSString,
        count: Int,
        preferredColumn: Int?,
        direction: Int
    ) -> VimNavigationResult {
        var currentPosition = position
        let currentLine = text.lineRange(for: NSRange(location: position, length: 0))
        let desiredColumn = preferredColumn ?? max(position - currentLine.location, 0)

        for _ in 0..<max(count, 1) {
            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            let nextLocation = direction < 0
                ? previousLineLocation(before: lineRange, in: text)
                : nextLineLocation(after: lineRange, in: text)

            guard let nextLocation else { break }

            let nextLineRange = text.lineRange(for: NSRange(location: nextLocation, length: 0))
            let nextLineLength = lineContentLength(of: nextLineRange, in: text)
            let newColumn = min(desiredColumn, nextLineLength)
            currentPosition = nextLineRange.location + newColumn
        }

        return VimNavigationResult(
            position: currentPosition,
            preferredColumn: desiredColumn
        )
    }

    private static func repeatedMove(
        from position: Int,
        in text: NSString,
        count: Int,
        preferredColumn: Int?,
        move: (Int, NSString) -> Int
    ) -> VimNavigationResult {
        var currentPosition = position

        for _ in 0..<max(count, 1) {
            currentPosition = move(currentPosition, text)
        }

        return VimNavigationResult(position: currentPosition, preferredColumn: preferredColumn)
    }

    private static func moveWordForward(from position: Int, in text: NSString) -> Int {
        var currentPosition = position

        while currentPosition < text.length
            && !isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        while currentPosition < text.length
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        return normalizedCursorPosition(currentPosition, in: text)
    }

    private static func moveWordBackward(from position: Int, in text: NSString) -> Int {
        var currentPosition = position

        if currentPosition > 0 {
            currentPosition -= 1
        }

        while currentPosition > 0
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition -= 1
        }

        while currentPosition > 0
            && !isWordBoundary(text.character(at: currentPosition - 1))
        {
            currentPosition -= 1
        }

        return normalizedCursorPosition(currentPosition, in: text)
    }

    private static func moveWordEndForward(from position: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        var currentPosition = normalizedCursorPosition(position, in: text)

        if !isWordBoundary(text.character(at: currentPosition)) {
            let nextIndex = currentPosition + 1

            if nextIndex < text.length && !isWordBoundary(text.character(at: nextIndex)) {
                while currentPosition + 1 < text.length
                    && !isWordBoundary(text.character(at: currentPosition + 1))
                {
                    currentPosition += 1
                }

                return normalizedCursorPosition(currentPosition, in: text)
            }

            currentPosition += 1
        }

        while currentPosition < text.length
            && isWordBoundary(text.character(at: currentPosition))
        {
            currentPosition += 1
        }

        guard currentPosition < text.length else {
            return normalizedCursorPosition(text.length - 1, in: text)
        }

        while currentPosition + 1 < text.length
            && !isWordBoundary(text.character(at: currentPosition + 1))
        {
            currentPosition += 1
        }

        return normalizedCursorPosition(currentPosition, in: text)
    }

    private static func moveParagraphForward(from position: Int, in text: NSString) -> Int {
        var currentPosition = position

        while currentPosition < text.length {
            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            if isBlankLine(text.substring(with: lineRange)) {
                break
            }
            currentPosition = NSMaxRange(lineRange)
        }

        while currentPosition < text.length {
            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            if !isBlankLine(text.substring(with: lineRange)) {
                break
            }
            currentPosition = NSMaxRange(lineRange)
        }

        return normalizedCursorPosition(currentPosition, in: text)
    }

    private static func moveParagraphBackward(from position: Int, in text: NSString) -> Int {
        var currentPosition = position

        if currentPosition > 0 {
            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            currentPosition = lineRange.location
        }

        if currentPosition > 0 {
            currentPosition -= 1
        }

        while currentPosition > 0 {
            let lineRange = text.lineRange(for: NSRange(location: currentPosition, length: 0))
            if !isBlankLine(text.substring(with: lineRange)) {
                currentPosition = lineRange.location
                break
            }
            currentPosition = max(lineRange.location - 1, 0)
        }

        while currentPosition > 0 {
            let lineRange = text.lineRange(
                for: NSRange(location: max(currentPosition - 1, 0), length: 0))
            if isBlankLine(text.substring(with: lineRange)) {
                break
            }
            currentPosition = lineRange.location
        }

        return normalizedCursorPosition(currentPosition, in: text)
    }

    private static func lineEndPosition(
        from position: Int,
        in text: NSString,
        count: Int
    ) -> Int {
        var lineRange = text.lineRange(for: NSRange(location: position, length: 0))

        for _ in 1..<max(count, 1) {
            guard let nextLocation = nextLineLocation(after: lineRange, in: text) else { break }
            lineRange = text.lineRange(for: NSRange(location: nextLocation, length: 0))
        }

        return lastCharacterIndex(in: lineRange, text: text)
    }

    private static func goToLine(
        in text: NSString,
        destination: VimDefaultLineDestination,
        count: Int?
    ) -> Int {
        let lineNumber: Int

        if let count {
            lineNumber = max(count, 1)
        } else {
            lineNumber = destination == .first ? 1 : totalLineCount(in: text)
        }

        let clampedLineNumber = min(lineNumber, totalLineCount(in: text))
        let lineRange = lineRange(forLineNumber: clampedLineNumber, in: text)
        return firstNonBlank(in: lineRange, text: text)
    }

    private static func performCharacterSearch(
        _ search: VimCharacterSearch,
        from position: Int,
        in text: NSString,
        count: Int
    ) -> Int {
        let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
        let lowerBound = lineRange.location
        let upperBound = lineContentUpperBound(of: lineRange, in: text)
        let target = String(search.character)
        let targetLength = (target as NSString).length

        guard targetLength > 0 else { return position }

        var remaining = max(count, 1)

        switch search.direction {
        case .forward:
            var currentIndex = min(position + 1, upperBound)

            while currentIndex < upperBound {
                if matches(target, at: currentIndex, in: text) {
                    remaining -= 1
                    if remaining == 0 {
                        let foundIndex = search.kind == .to
                            ? currentIndex
                            : max(position, currentIndex - 1)
                        return normalizedCursorPosition(foundIndex, in: text)
                    }
                }
                currentIndex += 1
            }
        case .backward:
            var currentIndex = position - 1

            while currentIndex >= lowerBound {
                if matches(target, at: currentIndex, in: text) {
                    remaining -= 1
                    if remaining == 0 {
                        let foundIndex = search.kind == .to
                            ? currentIndex
                            : min(position, currentIndex + targetLength)
                        return normalizedCursorPosition(foundIndex, in: text)
                    }
                }
                currentIndex -= 1
            }
        }

        return position
    }

    private static func firstNonBlankInLogicalLine(from position: Int, in text: NSString) -> Int {
        let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
        return firstNonBlank(in: lineRange, text: text)
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

    private static func totalLineCount(in text: NSString) -> Int {
        var lineCount = 0
        var currentIndex = 0

        while currentIndex < text.length {
            lineCount += 1
            let lineRange = text.lineRange(for: NSRange(location: currentIndex, length: 0))
            currentIndex = NSMaxRange(lineRange)
        }

        return max(lineCount, 1)
    }

    private static func lineRange(forLineNumber lineNumber: Int, in text: NSString) -> NSRange {
        var currentLine = 1
        var currentIndex = 0

        while currentLine < lineNumber && currentIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: currentIndex, length: 0))
            currentIndex = NSMaxRange(lineRange)
            currentLine += 1
        }

        let location = min(currentIndex, max(text.length - 1, 0))
        return text.lineRange(for: NSRange(location: location, length: 0))
    }

    private static func previousLineLocation(before lineRange: NSRange, in text: NSString) -> Int? {
        guard lineRange.location > 0 else { return nil }
        return lineRange.location - 1
    }

    private static func nextLineLocation(after lineRange: NSRange, in text: NSString) -> Int? {
        let nextLocation = NSMaxRange(lineRange)
        return nextLocation < text.length ? nextLocation : nil
    }

    private static func lineContentUpperBound(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return lineRange.location }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(lineRange)
    }

    private static func lineContentLength(of lineRange: NSRange, in text: NSString) -> Int {
        max(lineContentUpperBound(of: lineRange, in: text) - lineRange.location, 0)
    }

    private static func lastCharacterIndex(in lineRange: NSRange, text: NSString) -> Int {
        let upperBound = lineContentUpperBound(of: lineRange, in: text)
        return upperBound > lineRange.location ? upperBound - 1 : lineRange.location
    }

    private static func matches(_ target: String, at index: Int, in text: NSString) -> Bool {
        let targetLength = (target as NSString).length
        guard index >= 0, index + targetLength <= text.length else { return false }
        return text.substring(with: NSRange(location: index, length: targetLength)) == target
    }

    private static func isWordBoundary(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }

        return scalar.properties.isWhitespace
            || CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.newlines.contains(scalar)
    }

    private static func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalizedCursorPosition(_ position: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        var normalized = max(0, min(position, text.length - 1))

        if text.character(at: normalized) == 0x0A, normalized > 0 {
            let lineRange = text.lineRange(for: NSRange(location: normalized, length: 0))
            if normalized > lineRange.location {
                normalized -= 1
            }
        }

        return normalized
    }

    private static func clamp(_ position: Int, in text: NSString) -> Int {
        max(0, min(position, max(text.length - 1, 0)))
    }
}
