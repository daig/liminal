import Foundation

enum VimTextObjectResolver {
    static func selectionResult(
        for argument: VimTextObjectArgument,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        guard text.length > 0 else { return nil }

        let currentPosition = clamp(position, in: text)
        let count = max(argument.count ?? 1, 1)

        switch argument.kind {
        case .word:
            return sequenceSelectionResult(
                for: tokenizeWords(in: text, bigWord: false),
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .wordBig:
            return sequenceSelectionResult(
                for: tokenizeWords(in: text, bigWord: true),
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .sentence:
            return sequenceSelectionResult(
                for: tokenizeSentences(in: text),
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .paragraph:
            return sequenceSelectionResult(
                for: tokenizeParagraphs(in: text),
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .parenBlock:
            return blockSelectionResult(
                open: "(",
                close: ")",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .braceBlock:
            return blockSelectionResult(
                open: "{",
                close: "}",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .bracketBlock:
            return blockSelectionResult(
                open: "[",
                close: "]",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .angleBlock:
            return blockSelectionResult(
                open: "<",
                close: ">",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .tagBlock:
            return tagSelectionResult(
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .doubleQuote:
            return quoteSelectionResult(
                delimiter: "\"",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .singleQuote:
            return quoteSelectionResult(
                delimiter: "'",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        case .backtickQuote:
            return quoteSelectionResult(
                delimiter: "`",
                scope: argument.scope,
                count: count,
                in: text,
                from: currentPosition
            )
        }
    }
}

private extension VimTextObjectResolver {
    struct TokenSequence {
        let units: [NSRange]
        let separators: [NSRange?]
        let linewise: Bool
    }

    struct ObjectCandidate {
        let innerRange: NSRange
        let aroundCoreRange: NSRange
        let leadingWhitespace: NSRange?
        let trailingWhitespace: NSRange?
        let cursorInLeadingWhitespace: Bool
        let cursorInTrailingWhitespace: Bool
        let linewise: Bool
    }

    struct BlockPair {
        let openIndex: Int
        let closeIndex: Int

        var outerRange: NSRange {
            NSRange(location: openIndex, length: closeIndex - openIndex + 1)
        }

        var innerRange: NSRange {
            NSRange(location: openIndex + 1, length: max(closeIndex - openIndex - 1, 0))
        }
    }

    struct TagToken {
        let name: String
        let range: NSRange
        let isClosing: Bool
        let isSelfClosing: Bool
    }

    struct TagPair {
        let name: String
        let openRange: NSRange
        let closeRange: NSRange

        var outerRange: NSRange {
            NSRange(location: openRange.location, length: NSMaxRange(closeRange) - openRange.location)
        }

        var innerRange: NSRange {
            NSRange(
                location: NSMaxRange(openRange),
                length: max(closeRange.location - NSMaxRange(openRange), 0)
            )
        }
    }

    struct QuoteBounds {
        let startQuoteIndex: Int
        let endQuoteIndex: Int
    }

    static func sequenceSelectionResult(
        for sequence: TokenSequence,
        scope: VimTextObjectScope,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        if sequence.units.isEmpty {
            guard let whitespace = sequence.separators.first ?? nil, contains(whitespace, position) else {
                return nil
            }
            return makeSelection(range: whitespace, linewise: sequence.linewise)
        }

        guard let candidate = sequenceCandidate(
            for: sequence,
            count: count,
            from: position
        ) else {
            return nil
        }

        return selectionResult(from: candidate, scope: scope)
    }

    static func blockSelectionResult(
        open: Character,
        close: Character,
        scope: VimTextObjectScope,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        let pairs = matchedBlockPairs(open: open, close: close, in: text)
        let containingPairs = pairs
            .filter { contains($0.outerRange, position) }
            .sorted { $0.outerRange.length < $1.outerRange.length }

        guard !containingPairs.isEmpty else { return nil }

        let pair = containingPairs[min(count - 1, containingPairs.count - 1)]
        let range: NSRange

        switch scope {
        case .around:
            range = pair.outerRange
        case .inner:
            guard pair.innerRange.length > 0 else { return nil }
            range = pair.innerRange
        }

        return makeSelection(range: range, linewise: false)
    }

    static func quoteSelectionResult(
        delimiter: Character,
        scope: VimTextObjectScope,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
        let lineUpperBound = lineContentUpperBound(of: lineRange, in: text)
        let positions = quotePositions(
            delimiter: delimiter,
            in: text,
            lowerBound: lineRange.location,
            upperBound: lineUpperBound
        )

        guard let bounds = selectQuoteBounds(
            from: positions,
            delimiter: delimiter,
            in: text,
            lineRange: lineRange,
            position: position
        ) else {
            return nil
        }

        let innerRange = NSRange(
            location: bounds.startQuoteIndex + 1,
            length: max(bounds.endQuoteIndex - bounds.startQuoteIndex - 1, 0)
        )
        let aroundCoreRange = NSRange(
            location: bounds.startQuoteIndex,
            length: bounds.endQuoteIndex - bounds.startQuoteIndex + 1
        )
        let leadingWhitespace = horizontalWhitespaceRunBefore(
            aroundCoreRange.location,
            in: text,
            lowerBound: lineRange.location
        )
        let trailingWhitespace = horizontalWhitespaceRunAfter(
            NSMaxRange(aroundCoreRange),
            in: text,
            upperBound: lineUpperBound
        )

        if scope == .inner, count == 2 {
            return makeSelection(range: aroundCoreRange, linewise: false)
        }

        let candidate = ObjectCandidate(
            innerRange: innerRange,
            aroundCoreRange: aroundCoreRange,
            leadingWhitespace: leadingWhitespace,
            trailingWhitespace: trailingWhitespace,
            cursorInLeadingWhitespace: contains(leadingWhitespace, position),
            cursorInTrailingWhitespace: contains(trailingWhitespace, position),
            linewise: false
        )

        return selectionResult(from: candidate, scope: scope)
    }

    static func tagSelectionResult(
        scope: VimTextObjectScope,
        count: Int,
        in text: NSString,
        from position: Int
    ) -> VimSelectionResult? {
        let pairs = matchedTagPairs(in: text)
        guard !pairs.isEmpty else { return nil }

        let selectedPair: TagPair?
        let containingPairs = pairs
            .filter { contains($0.outerRange, position) }
            .sorted { $0.outerRange.length < $1.outerRange.length }

        if !containingPairs.isEmpty {
            selectedPair = containingPairs[min(count - 1, containingPairs.count - 1)]
        } else {
            let leadingMatch = pairs
                .filter { contains(whitespaceRunBefore($0.outerRange.location, in: text), position) }
                .sorted { $0.outerRange.location < $1.outerRange.location }
                .first
            let trailingMatch = pairs
                .filter { contains(whitespaceRunAfter(NSMaxRange($0.outerRange), in: text), position) }
                .sorted { $0.outerRange.length < $1.outerRange.length }
                .first

            selectedPair = leadingMatch ?? trailingMatch
        }

        guard let pair = selectedPair else { return nil }

        let containingAncestors = pairs
            .filter { $0.outerRange.location <= pair.outerRange.location && NSMaxRange($0.outerRange) >= NSMaxRange(pair.outerRange) }
            .sorted { $0.outerRange.length < $1.outerRange.length }
        let resolvedPair = containingAncestors[min(count - 1, containingAncestors.count - 1)]
        let leadingWhitespace = whitespaceRunBefore(resolvedPair.outerRange.location, in: text)
        let trailingWhitespace = whitespaceRunAfter(NSMaxRange(resolvedPair.outerRange), in: text)

        if scope == .inner, resolvedPair.innerRange.length == 0 {
            return makeSelection(range: resolvedPair.openRange, linewise: false)
        }

        let candidate = ObjectCandidate(
            innerRange: resolvedPair.innerRange,
            aroundCoreRange: resolvedPair.outerRange,
            leadingWhitespace: leadingWhitespace,
            trailingWhitespace: trailingWhitespace,
            cursorInLeadingWhitespace: contains(leadingWhitespace, position),
            cursorInTrailingWhitespace: contains(trailingWhitespace, position),
            linewise: false
        )

        return selectionResult(from: candidate, scope: scope)
    }

    static func selectionResult(
        from candidate: ObjectCandidate,
        scope: VimTextObjectScope
    ) -> VimSelectionResult {
        let range: NSRange

        switch scope {
        case .inner:
            if candidate.cursorInLeadingWhitespace, let leadingWhitespace = candidate.leadingWhitespace {
                range = leadingWhitespace
            } else if candidate.cursorInTrailingWhitespace, let trailingWhitespace = candidate.trailingWhitespace {
                range = trailingWhitespace
            } else {
                range = candidate.innerRange
            }
        case .around:
            let outerWhitespace: NSRange?

            if candidate.cursorInLeadingWhitespace {
                outerWhitespace = candidate.leadingWhitespace
            } else if let trailingWhitespace = candidate.trailingWhitespace {
                outerWhitespace = trailingWhitespace
            } else {
                outerWhitespace = candidate.leadingWhitespace
            }

            range = outerWhitespace.map { union($0, candidate.aroundCoreRange) } ?? candidate.aroundCoreRange
        }

        return makeSelection(range: range, linewise: candidate.linewise)
    }

    static func sequenceCandidate(
        for sequence: TokenSequence,
        count: Int,
        from position: Int
    ) -> ObjectCandidate? {
        if let unitIndex = sequence.units.firstIndex(where: { contains($0, position) }) {
            return sequenceCandidate(
                for: sequence,
                startIndex: unitIndex,
                endIndex: min(unitIndex + count - 1, sequence.units.count - 1),
                cursorInLeadingWhitespace: false,
                cursorInTrailingWhitespace: false
            )
        }

        for separatorIndex in sequence.separators.indices {
            guard let separator = sequence.separators[separatorIndex], contains(separator, position) else {
                continue
            }

            if separatorIndex < sequence.units.count {
                let startIndex = separatorIndex
                return sequenceCandidate(
                    for: sequence,
                    startIndex: startIndex,
                    endIndex: min(startIndex + count - 1, sequence.units.count - 1),
                    cursorInLeadingWhitespace: true,
                    cursorInTrailingWhitespace: false
                )
            }

            if separatorIndex > 0 {
                let startIndex = separatorIndex - 1
                return sequenceCandidate(
                    for: sequence,
                    startIndex: startIndex,
                    endIndex: min(startIndex + count - 1, sequence.units.count - 1),
                    cursorInLeadingWhitespace: false,
                    cursorInTrailingWhitespace: true
                )
            }
        }

        return nil
    }

    static func sequenceCandidate(
        for sequence: TokenSequence,
        startIndex: Int,
        endIndex: Int,
        cursorInLeadingWhitespace: Bool,
        cursorInTrailingWhitespace: Bool
    ) -> ObjectCandidate {
        let innerRange = NSRange(
            location: sequence.units[startIndex].location,
            length: NSMaxRange(sequence.units[endIndex]) - sequence.units[startIndex].location
        )

        return ObjectCandidate(
            innerRange: innerRange,
            aroundCoreRange: innerRange,
            leadingWhitespace: separator(at: startIndex, in: sequence),
            trailingWhitespace: separator(at: endIndex + 1, in: sequence),
            cursorInLeadingWhitespace: cursorInLeadingWhitespace,
            cursorInTrailingWhitespace: cursorInTrailingWhitespace,
            linewise: sequence.linewise
        )
    }

    static func separator(at index: Int, in sequence: TokenSequence) -> NSRange? {
        guard index >= 0, index < sequence.separators.count else { return nil }
        return sequence.separators[index]
    }

    static func tokenizeWords(in text: NSString, bigWord: Bool) -> TokenSequence {
        let leadingSeparator = whitespaceRun(from: 0, in: text)
        var separators: [NSRange?] = [leadingSeparator]
        var units: [NSRange] = []
        var index = NSMaxRange(leadingSeparator ?? NSRange(location: 0, length: 0))

        while index < text.length {
            let unitStart = index

            if bigWord {
                while index < text.length, !isBlank(text.character(at: index)) {
                    index += 1
                }
            } else {
                let unitClass = wordUnitClass(text.character(at: index))
                while index < text.length, wordUnitClass(text.character(at: index)) == unitClass {
                    index += 1
                }
            }

            units.append(NSRange(location: unitStart, length: index - unitStart))

            let separator = whitespaceRun(from: index, in: text)
            separators.append(separator)
            index = NSMaxRange(separator ?? NSRange(location: index, length: 0))
        }

        if separators.count < units.count + 1 {
            separators.append(nil)
        }

        return TokenSequence(units: units, separators: separators, linewise: false)
    }

    static func tokenizeSentences(in text: NSString) -> TokenSequence {
        var units: [NSRange] = []
        var separators: [NSRange?] = []
        var index = 0

        separators.append(whitespaceRun(from: index, in: text))
        index = NSMaxRange(separators[0] ?? NSRange(location: 0, length: 0))

        while index < text.length {
            let start = index
            var scan = index
            var boundaryEnd: Int?
            var lastNonBlank = start

            while scan < text.length {
                let lineRange = text.lineRange(for: NSRange(location: scan, length: 0))
                if scan == lineRange.location, lineRange.location > start, isBlankLine(lineRange, in: text) {
                    break
                }

                if isSentenceBoundary(at: scan, in: text) {
                    boundaryEnd = sentenceBoundaryEnd(after: scan, in: text)
                    break
                }

                if !isBlank(text.character(at: scan)) {
                    lastNonBlank = scan
                }

                scan += 1
            }

            let end: Int

            if let boundaryEnd {
                end = boundaryEnd
                index = boundaryEnd
            } else {
                end = lastNonBlank + 1
                index = end
            }

            guard end > start else { break }
            units.append(NSRange(location: start, length: end - start))

            let separator = whitespaceRun(from: index, in: text)
            separators.append(separator)
            index = NSMaxRange(separator ?? NSRange(location: index, length: 0))
        }

        if separators.count < units.count + 1 {
            separators.append(nil)
        }

        return TokenSequence(units: units, separators: separators, linewise: false)
    }

    static func tokenizeParagraphs(in text: NSString) -> TokenSequence {
        var units: [NSRange] = []
        var separators: [NSRange?] = []
        var index = 0

        let leadingBlankLines = blankLineRun(from: index, in: text)
        separators.append(leadingBlankLines)
        index = NSMaxRange(leadingBlankLines ?? NSRange(location: 0, length: 0))

        while index < text.length {
            let paragraphStart = index

            while index < text.length {
                let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
                if isBlankLine(lineRange, in: text) {
                    break
                }
                index = NSMaxRange(lineRange)
            }

            if index > paragraphStart {
                units.append(NSRange(location: paragraphStart, length: index - paragraphStart))
            }

            let separator = blankLineRun(from: index, in: text)
            separators.append(separator)
            index = NSMaxRange(separator ?? NSRange(location: index, length: 0))
        }

        if separators.count < units.count + 1 {
            separators.append(nil)
        }

        return TokenSequence(units: units, separators: separators, linewise: true)
    }

    static func matchedBlockPairs(
        open: Character,
        close: Character,
        in text: NSString
    ) -> [BlockPair] {
        let openScalar = utf16Scalar(for: open)
        let closeScalar = utf16Scalar(for: close)
        var stack: [Int] = []
        var pairs: [BlockPair] = []

        for index in 0..<text.length {
            let character = text.character(at: index)

            if character == openScalar {
                stack.append(index)
            } else if character == closeScalar, let openIndex = stack.popLast() {
                pairs.append(BlockPair(openIndex: openIndex, closeIndex: index))
            }
        }

        return pairs
    }

    static func quotePairs(
        delimiter: Character,
        in text: NSString,
        lowerBound: Int,
        upperBound: Int
    ) -> [BlockPair] {
        let scalar = utf16Scalar(for: delimiter)
        var pairs: [BlockPair] = []
        var openIndex: Int?
        var index = lowerBound

        while index < upperBound {
            if text.character(at: index) == scalar, isEscaped(index, in: text) == false {
                if let currentOpenIndex = openIndex {
                    pairs.append(BlockPair(openIndex: currentOpenIndex, closeIndex: index))
                    openIndex = nil
                } else {
                    openIndex = index
                }
            }

            index += 1
        }

        return pairs
    }

    static func quotePositions(
        delimiter: Character,
        in text: NSString,
        lowerBound: Int,
        upperBound: Int
    ) -> [Int] {
        let scalar = utf16Scalar(for: delimiter)
        var positions: [Int] = []
        var index = lowerBound

        while index < upperBound {
            if text.character(at: index) == scalar, isEscaped(index, in: text) == false {
                positions.append(index)
            }
            index += 1
        }

        return positions
    }

    static func selectQuoteBounds(
        from positions: [Int],
        delimiter: Character,
        in text: NSString,
        lineRange: NSRange,
        position: Int
    ) -> QuoteBounds? {
        guard positions.count >= 2 else { return nil }

        let lineUpperBound = lineContentUpperBound(of: lineRange, in: text)
        let pairs = quotePairs(
            delimiter: delimiter,
            in: text,
            lowerBound: lineRange.location,
            upperBound: lineUpperBound
        )

        if let pair = pairs.first(where: { $0.openIndex == position || $0.closeIndex == position }) {
            return QuoteBounds(startQuoteIndex: pair.openIndex, endQuoteIndex: pair.closeIndex)
        }

        if let previousQuoteIndex = positions.last(where: { $0 < position }),
            let nextQuoteIndex = positions.first(where: { $0 > position })
        {
            return QuoteBounds(startQuoteIndex: previousQuoteIndex, endQuoteIndex: nextQuoteIndex)
        }

        if position < positions[0] {
            return QuoteBounds(startQuoteIndex: positions[0], endQuoteIndex: positions[1])
        }

        return nil
    }

    static func matchedTagPairs(in text: NSString) -> [TagPair] {
        let tokens = tagTokens(in: text)
        var stack: [TagToken] = []
        var pairs: [TagPair] = []

        for token in tokens {
            if token.isSelfClosing {
                continue
            }

            if token.isClosing == false {
                stack.append(token)
                continue
            }

            guard let matchingIndex = stack.lastIndex(where: { $0.name == token.name }) else {
                continue
            }

            let openToken = stack.remove(at: matchingIndex)
            pairs.append(
                TagPair(
                    name: openToken.name,
                    openRange: openToken.range,
                    closeRange: token.range
                )
            )
        }

        return pairs
    }

    static func tagTokens(in text: NSString) -> [TagToken] {
        let pattern = #"<\s*(/)?\s*([A-Za-z][A-Za-z0-9:-]*)\b[^>]*?(/?)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let source = text as String
        return regex.matches(
            in: source,
            range: NSRange(location: 0, length: text.length)
        ).compactMap { match in
            guard match.numberOfRanges >= 4 else { return nil }

            let range = match.range
            let isClosing = match.range(at: 1).location != NSNotFound
            let isSelfClosing = match.range(at: 3).location != NSNotFound
                && text.substring(with: match.range(at: 3)) == "/"
            let name = text.substring(with: match.range(at: 2)).lowercased()

            return TagToken(
                name: name,
                range: range,
                isClosing: isClosing,
                isSelfClosing: isSelfClosing
            )
        }
    }

    static func whitespaceRun(from start: Int, in text: NSString) -> NSRange? {
        guard start < text.length else { return nil }

        var end = start
        while end < text.length, isBlank(text.character(at: end)) {
            end += 1
        }

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    static func blankLineRun(from start: Int, in text: NSString) -> NSRange? {
        guard start < text.length else { return nil }

        var current = start
        let firstLine = text.lineRange(for: NSRange(location: current, length: 0))
        guard isBlankLine(firstLine, in: text) else { return nil }

        let runStart = firstLine.location
        current = NSMaxRange(firstLine)

        while current < text.length {
            let lineRange = text.lineRange(for: NSRange(location: current, length: 0))
            guard isBlankLine(lineRange, in: text) else { break }
            current = NSMaxRange(lineRange)
        }

        return NSRange(location: runStart, length: current - runStart)
    }

    static func whitespaceRunBefore(_ position: Int, in text: NSString) -> NSRange? {
        guard position > 0 else { return nil }

        var start = position
        while start > 0, isBlank(text.character(at: start - 1)) {
            start -= 1
        }

        guard start < position else { return nil }
        return NSRange(location: start, length: position - start)
    }

    static func whitespaceRunAfter(_ position: Int, in text: NSString) -> NSRange? {
        guard position < text.length else { return nil }

        var end = position
        while end < text.length, isBlank(text.character(at: end)) {
            end += 1
        }

        guard end > position else { return nil }
        return NSRange(location: position, length: end - position)
    }

    static func horizontalWhitespaceRunBefore(
        _ position: Int,
        in text: NSString,
        lowerBound: Int
    ) -> NSRange? {
        guard position > lowerBound else { return nil }

        var start = position
        while start > lowerBound, isHorizontalWhitespace(text.character(at: start - 1)) {
            start -= 1
        }

        guard start < position else { return nil }
        return NSRange(location: start, length: position - start)
    }

    static func horizontalWhitespaceRunAfter(
        _ position: Int,
        in text: NSString,
        upperBound: Int
    ) -> NSRange? {
        guard position < upperBound else { return nil }

        var end = position
        while end < upperBound, isHorizontalWhitespace(text.character(at: end)) {
            end += 1
        }

        guard end > position else { return nil }
        return NSRange(location: position, length: end - position)
    }

    static func isSentenceBoundary(at index: Int, in text: NSString) -> Bool {
        let character = text.character(at: index)
        guard isSentenceTerminator(character) else { return false }

        let boundaryEnd = sentenceBoundaryEnd(after: index, in: text)
        return boundaryEnd >= text.length || isBlank(text.character(at: boundaryEnd))
    }

    static func sentenceBoundaryEnd(after index: Int, in text: NSString) -> Int {
        var boundaryEnd = index + 1

        while boundaryEnd < text.length, isSentenceCloser(text.character(at: boundaryEnd)) {
            boundaryEnd += 1
        }

        return boundaryEnd
    }

    static func isSentenceTerminator(_ character: unichar) -> Bool {
        character == utf16Scalar(for: ".")
            || character == utf16Scalar(for: "!")
            || character == utf16Scalar(for: "?")
    }

    static func isSentenceCloser(_ character: unichar) -> Bool {
        let closers: Set<unichar> = [
            utf16Scalar(for: "\""),
            utf16Scalar(for: "'"),
            utf16Scalar(for: ")"),
            utf16Scalar(for: "]"),
            utf16Scalar(for: "}")
        ]
        return closers.contains(character)
    }

    static func wordUnitClass(_ character: unichar) -> Int {
        if isBlank(character) {
            return 0
        }

        guard let scalar = Unicode.Scalar(character) else { return 2 }

        if scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
            return 1
        }

        return 2
    }

    static func isEscaped(_ index: Int, in text: NSString) -> Bool {
        guard index > 0 else { return false }

        let backslash = utf16Scalar(for: "\\")
        var current = index - 1
        var count = 0

        while current >= 0, text.character(at: current) == backslash {
            count += 1
            if current == 0 {
                break
            }
            current -= 1
        }

        return count.isMultiple(of: 2) == false
    }

    static func makeSelection(range: NSRange, linewise: Bool) -> VimSelectionResult {
        VimSelectionResult(range: range, cursorAnchor: range.location, linewise: linewise)
    }

    static func lineContentUpperBound(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return lineRange.location }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(lineRange)
    }

    static func isBlankLine(_ range: NSRange, in text: NSString) -> Bool {
        text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isBlank(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return scalar.properties.isWhitespace
    }

    static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == utf16Scalar(for: " ") || character == utf16Scalar(for: "\t")
    }

    static func contains(_ range: NSRange, _ position: Int) -> Bool {
        position >= range.location && position < NSMaxRange(range)
    }

    static func contains(_ range: NSRange?, _ position: Int) -> Bool {
        guard let range else { return false }
        return contains(range, position)
    }

    static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let start = min(lhs.location, rhs.location)
        let end = max(NSMaxRange(lhs), NSMaxRange(rhs))
        return NSRange(location: start, length: end - start)
    }

    static func utf16Scalar(for character: Character) -> unichar {
        String(character).utf16.first ?? 0
    }

    static func clamp(_ position: Int, in text: NSString) -> Int {
        max(0, min(position, max(text.length - 1, 0)))
    }
}
