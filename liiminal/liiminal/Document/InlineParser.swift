import Foundation

struct InlineParser {
    static func parse(_ source: String) -> [InlineNode] {
        guard !source.isEmpty else { return [] }
        var scanner = InlineScanner(source: source)
        return scanner.parseTopLevel()
    }
}

// MARK: - Scanner

private struct InlineScanner {
    let chars: [Character]
    var position: Int = 0

    init(source: String) {
        self.chars = Array(source)
    }

    var isAtEnd: Bool { position >= chars.count }
    var current: Character? { isAtEnd ? nil : chars[position] }

    func peek(at offset: Int = 1) -> Character? {
        let i = position + offset
        return i < chars.count ? chars[i] : nil
    }

    // MARK: - Top-Level Parse

    mutating func parseTopLevel() -> [InlineNode] {
        var nodes: [InlineNode] = []
        var textStart = position

        while !isAtEnd {
            let savedPos = position
            if let node = tryParseSpecial() {
                // Flush accumulated plain text before this node
                if textStart < savedPos {
                    nodes.append(.text(String(chars[textStart..<savedPos])))
                }
                nodes.append(node)
                textStart = position
            } else {
                position += 1
            }
        }

        // Flush remaining text
        if textStart < position {
            nodes.append(.text(String(chars[textStart..<position])))
        }

        return coalesceText(nodes)
    }

    // MARK: - Special Construct Dispatch

    private mutating func tryParseSpecial() -> InlineNode? {
        guard let ch = current else { return nil }

        // Escaped character
        if ch == "\\" && peek() != nil && position + 1 < chars.count {
            let next = chars[position + 1]
            if next.isASCII && next.isPunctuation {
                // Consume backslash, leave the character for text accumulation
                position += 1
                return nil
            }
        }

        switch ch {
        // Code span (highest priority — content is literal)
        case "`":
            return tryParseCodeSpan()

        // Comment %%...%%
        case "%" where peek() == "%":
            return tryParseComment()

        // Inline LaTeX $...$
        case "$":
            return tryParseInlineLatex()

        // Embed ![[...]] (must check before image ![)
        case "!" where peek() == "[" && peek(at: 2) == "[":
            return tryParseEmbed()

        // Image ![alt](url)
        case "!" where peek() == "[":
            return tryParseImage()

        // Wikilink [[...]]
        case "[" where peek() == "[":
            return tryParseWikilink()

        // Standard link [text](url)
        case "[":
            return tryParseLink()

        // Strong/Emphasis
        case "*", "_":
            return tryParseEmphasisOrStrong()

        // Strikethrough ~~...~~
        case "~" where peek() == "~":
            return tryParseStrikethrough()

        // Highlight ==...==
        case "=" where peek() == "=":
            return tryParseHighlight()

        // Inline footnote ^[...]
        case "^" where peek() == "[":
            return tryParseInlineFootnote()

        default:
            return nil
        }
    }

    // MARK: - Code Span

    private mutating func tryParseCodeSpan() -> InlineNode? {
        let start = position
        let backtickCount = countRun(of: "`")
        position += backtickCount

        var searchPos = position
        while searchPos < chars.count {
            if chars[searchPos] == "`" {
                let closeCount = countRunAt(searchPos, of: "`")
                if closeCount == backtickCount {
                    let code = String(chars[position..<searchPos])
                    position = searchPos + closeCount
                    return .codeSpan(code: code, backtickCount: backtickCount)
                }
                searchPos += closeCount
            } else {
                searchPos += 1
            }
        }
        position = start
        return nil
    }

    // MARK: - Comment

    private mutating func tryParseComment() -> InlineNode? {
        let start = position
        position += 2  // skip %%

        var searchPos = position
        while searchPos + 1 < chars.count {
            if chars[searchPos] == "%" && chars[searchPos + 1] == "%" {
                let content = String(chars[position..<searchPos])
                position = searchPos + 2
                return .comment(content)
            }
            searchPos += 1
        }
        position = start
        return nil
    }

    // MARK: - Inline LaTeX

    private mutating func tryParseInlineLatex() -> InlineNode? {
        let start = position
        position += 1  // skip $

        // Don't start if followed by whitespace or at end
        guard !isAtEnd, let first = current, !first.isWhitespace else {
            position = start
            return nil
        }

        var searchPos = position
        while searchPos < chars.count {
            if chars[searchPos] == "$" {
                // Don't close if preceded by whitespace
                if searchPos > position && !chars[searchPos - 1].isWhitespace {
                    let content = String(chars[position..<searchPos])
                    position = searchPos + 1
                    return .inlineLatex(content)
                }
            }
            if chars[searchPos] == "\n" { break }
            searchPos += 1
        }
        position = start
        return nil
    }

    // MARK: - Wikilink

    private mutating func tryParseWikilink() -> InlineNode? {
        let start = position
        position += 2  // skip [[

        var searchPos = position
        while searchPos < chars.count {
            if chars[searchPos] == "]" && searchPos + 1 < chars.count
                && chars[searchPos + 1] == "]"
            {
                let inner = String(chars[position..<searchPos])
                position = searchPos + 2
                if let pipeIdx = inner.firstIndex(of: "|") {
                    let target = String(inner[inner.startIndex..<pipeIdx])
                    let alias = String(inner[inner.index(after: pipeIdx)...])
                    return .wikilink(target: target, alias: alias)
                }
                return .wikilink(target: inner, alias: nil)
            }
            if chars[searchPos] == "\n" { break }
            searchPos += 1
        }
        position = start
        return nil
    }

    // MARK: - Embed

    private mutating func tryParseEmbed() -> InlineNode? {
        let start = position
        position += 3  // skip ![[

        var searchPos = position
        while searchPos < chars.count {
            if chars[searchPos] == "]" && searchPos + 1 < chars.count
                && chars[searchPos + 1] == "]"
            {
                let inner = String(chars[position..<searchPos])
                position = searchPos + 2
                if let pipeIdx = inner.firstIndex(of: "|") {
                    let target = String(inner[inner.startIndex..<pipeIdx])
                    let params = String(inner[inner.index(after: pipeIdx)...])
                    return .embed(target: target, params: params)
                }
                return .embed(target: inner, params: nil)
            }
            if chars[searchPos] == "\n" { break }
            searchPos += 1
        }
        position = start
        return nil
    }

    // MARK: - Standard Link

    private mutating func tryParseLink() -> InlineNode? {
        let start = position
        position += 1  // skip [

        // Find closing ]
        guard let closeBracket = findUnescaped("]", from: position) else {
            position = start
            return nil
        }

        let textContent = String(chars[position..<closeBracket])
        let afterBracket = closeBracket + 1

        // Must be immediately followed by (
        guard afterBracket < chars.count && chars[afterBracket] == "(" else {
            position = start
            return nil
        }

        let parenStart = afterBracket + 1
        guard let closeParen = findUnescaped(")", from: parenStart) else {
            position = start
            return nil
        }

        let urlAndTitle = String(chars[parenStart..<closeParen])
        position = closeParen + 1

        let (url, title) = parseURLAndTitle(urlAndTitle)
        let children = InlineParser.parse(textContent)
        return .link(children: children, url: url, title: title)
    }

    // MARK: - Image

    private mutating func tryParseImage() -> InlineNode? {
        let start = position
        position += 2  // skip ![

        guard let closeBracket = findUnescaped("]", from: position) else {
            position = start
            return nil
        }

        let altText = String(chars[position..<closeBracket])
        let afterBracket = closeBracket + 1

        guard afterBracket < chars.count && chars[afterBracket] == "(" else {
            position = start
            return nil
        }

        let parenStart = afterBracket + 1
        guard let closeParen = findUnescaped(")", from: parenStart) else {
            position = start
            return nil
        }

        let urlAndTitle = String(chars[parenStart..<closeParen])
        position = closeParen + 1

        let (url, title) = parseURLAndTitle(urlAndTitle)
        return .image(alt: altText, url: url, title: title)
    }

    // MARK: - Emphasis / Strong

    private mutating func tryParseEmphasisOrStrong() -> InlineNode? {
        let delim = chars[position]
        let start = position

        // Count delimiter run
        let runLength = countRun(of: delim)

        // Try strong first (**) if we have at least 2
        if runLength >= 2 {
            position = start + 2
            // Opening delimiter must not be followed by whitespace
            if !isAtEnd, let next = current, !next.isWhitespace {
                if let closePos = findClosingDelimiter(
                    String(repeating: delim, count: 2), from: position)
                {
                    // Closing must not be preceded by whitespace
                    if closePos > position && !chars[closePos - 1].isWhitespace {
                        let inner = String(chars[position..<closePos])
                        position = closePos + 2
                        let children = InlineParser.parse(inner)
                        return .strong(children: children, delimiter: delim)
                    }
                }
            }
        }

        // Try emphasis (*)
        position = start + 1
        if !isAtEnd, let next = current, !next.isWhitespace {
            if let closePos = findClosingDelimiter(String(delim), from: position) {
                if closePos > position && !chars[closePos - 1].isWhitespace {
                    let inner = String(chars[position..<closePos])
                    position = closePos + 1
                    let children = InlineParser.parse(inner)
                    return .emphasis(children: children, delimiter: delim)
                }
            }
        }

        position = start
        return nil
    }

    // MARK: - Strikethrough

    private mutating func tryParseStrikethrough() -> InlineNode? {
        let start = position
        position += 2  // skip ~~

        if let closePos = findClosingDelimiter("~~", from: position) {
            let inner = String(chars[position..<closePos])
            position = closePos + 2
            let children = InlineParser.parse(inner)
            return .strikethrough(children: children)
        }
        position = start
        return nil
    }

    // MARK: - Highlight

    private mutating func tryParseHighlight() -> InlineNode? {
        let start = position
        position += 2  // skip ==

        if let closePos = findClosingDelimiter("==", from: position) {
            let inner = String(chars[position..<closePos])
            position = closePos + 2
            let children = InlineParser.parse(inner)
            return .highlight(children: children)
        }
        position = start
        return nil
    }

    // MARK: - Inline Footnote

    private mutating func tryParseInlineFootnote() -> InlineNode? {
        let start = position
        position += 2  // skip ^[

        var depth = 1
        var searchPos = position
        while searchPos < chars.count && depth > 0 {
            if chars[searchPos] == "[" { depth += 1 }
            if chars[searchPos] == "]" { depth -= 1 }
            if depth > 0 { searchPos += 1 }
        }

        if depth == 0 {
            let inner = String(chars[position..<searchPos])
            position = searchPos + 1
            let children = InlineParser.parse(inner)
            return .inlineFootnote(children: children)
        }
        position = start
        return nil
    }

    // MARK: - Scanning Helpers

    private func countRun(of char: Character) -> Int {
        countRunAt(position, of: char)
    }

    private func countRunAt(_ pos: Int, of char: Character) -> Int {
        var count = 0
        var i = pos
        while i < chars.count && chars[i] == char {
            count += 1
            i += 1
        }
        return count
    }

    /// Find closing delimiter, skipping escaped characters and code spans.
    private func findClosingDelimiter(_ delimiter: String, from start: Int) -> Int? {
        let delimChars = Array(delimiter)
        let delimLen = delimChars.count
        var i = start

        while i + delimLen <= chars.count {
            // Skip escaped characters
            if chars[i] == "\\" && i + 1 < chars.count {
                i += 2
                continue
            }
            // Skip code spans
            if chars[i] == "`" {
                let n = countRunAt(i, of: "`")
                i += n
                while i < chars.count {
                    if countRunAt(i, of: "`") == n {
                        i += n
                        break
                    }
                    i += 1
                }
                continue
            }
            // Check for delimiter match
            if Array(chars[i..<(i + delimLen)]) == delimChars {
                return i
            }
            i += 1
        }
        return nil
    }

    /// Find an unescaped single character.
    private func findUnescaped(_ char: Character, from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count {
                i += 2
                continue
            }
            if chars[i] == char { return i }
            i += 1
        }
        return nil
    }

    /// Parse "url" or "url \"title\"" from inside parentheses.
    private func parseURLAndTitle(_ raw: String) -> (url: String, title: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Check for trailing "title"
        if trimmed.hasSuffix("\"") {
            let withoutClose = trimmed.dropLast()
            if let openQuote = withoutClose.lastIndex(of: "\"") {
                let title = String(withoutClose[withoutClose.index(after: openQuote)...])
                let url = String(
                    withoutClose[withoutClose.startIndex..<openQuote]
                        .trimmingCharacters(in: .whitespaces))
                return (url, title)
            }
        }
        return (trimmed, nil)
    }

    /// Merge adjacent .text nodes into single nodes.
    private func coalesceText(_ nodes: [InlineNode]) -> [InlineNode] {
        var result: [InlineNode] = []
        for node in nodes {
            if case .text(let s) = node, case .text(let prev) = result.last {
                result[result.count - 1] = .text(prev + s)
            } else {
                result.append(node)
            }
        }
        return result
    }
}
