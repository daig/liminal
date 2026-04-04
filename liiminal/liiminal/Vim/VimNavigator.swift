import Foundation

struct VimNavigationResult {
    let position: Int
    let preferredColumn: Int?
}

enum VimNavigator {
    static func destination(
        for motion: VimMotion,
        count: Int,
        in text: NSString,
        from position: Int,
        preferredColumn: Int?
    ) -> VimNavigationResult {
        guard text.length > 0 else {
            return VimNavigationResult(position: 0, preferredColumn: nil)
        }

        let steps = max(count, 1)
        var currentPosition = clamp(position, in: text)
        var desiredColumn = preferredColumn

        for _ in 0..<steps {
            switch motion {
            case .left:
                currentPosition = clamp(currentPosition - 1, in: text)
                desiredColumn = nil
            case .right:
                currentPosition = clamp(currentPosition + 1, in: text)
                desiredColumn = nil
            case .up:
                let result = moveUp(
                    from: currentPosition, in: text, preferredColumn: desiredColumn)
                currentPosition = result.position
                desiredColumn = result.preferredColumn
            case .down:
                let result = moveDown(
                    from: currentPosition, in: text, preferredColumn: desiredColumn)
                currentPosition = result.position
                desiredColumn = result.preferredColumn
            case .wordForward:
                currentPosition = moveWordForward(from: currentPosition, in: text)
                desiredColumn = nil
            case .wordBackward:
                currentPosition = moveWordBackward(from: currentPosition, in: text)
                desiredColumn = nil
            case .paragraphForward:
                currentPosition = moveParagraphForward(from: currentPosition, in: text)
                desiredColumn = nil
            case .paragraphBackward:
                currentPosition = moveParagraphBackward(from: currentPosition, in: text)
                desiredColumn = nil
            }
        }

        return VimNavigationResult(
            position: currentPosition,
            preferredColumn: desiredColumn
        )
    }

    private static func moveUp(
        from position: Int,
        in text: NSString,
        preferredColumn: Int?
    ) -> VimNavigationResult {
        let currentLine = text.lineRange(for: NSRange(location: position, length: 0))
        let desired = preferredColumn ?? max(position - currentLine.location, 0)

        guard currentLine.location > 0 else {
            return VimNavigationResult(position: position, preferredColumn: desired)
        }

        let previousLine = text.lineRange(
            for: NSRange(location: currentLine.location - 1, length: 0))
        let newColumn = min(desired, lineContentLength(of: previousLine, in: text))

        return VimNavigationResult(
            position: previousLine.location + newColumn,
            preferredColumn: desired
        )
    }

    private static func moveDown(
        from position: Int,
        in text: NSString,
        preferredColumn: Int?
    ) -> VimNavigationResult {
        let currentLine = text.lineRange(for: NSRange(location: position, length: 0))
        let desired = preferredColumn ?? max(position - currentLine.location, 0)
        let nextLineStart = NSMaxRange(currentLine)

        guard nextLineStart < text.length else {
            return VimNavigationResult(position: position, preferredColumn: desired)
        }

        let nextLine = text.lineRange(for: NSRange(location: nextLineStart, length: 0))
        let newColumn = min(desired, lineContentLength(of: nextLine, in: text))

        return VimNavigationResult(
            position: nextLine.location + newColumn,
            preferredColumn: desired
        )
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

        return clamp(currentPosition, in: text)
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

        return clamp(currentPosition, in: text)
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

        return clamp(currentPosition, in: text)
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

        return clamp(currentPosition, in: text)
    }

    private static func lineContentLength(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return 0 }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return max(lineRange.length - (endsWithNewline ? 1 : 0), 0)
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

    private static func clamp(_ position: Int, in text: NSString) -> Int {
        max(0, min(position, max(text.length - 1, 0)))
    }
}
