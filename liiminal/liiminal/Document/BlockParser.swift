import Foundation

struct BlockParser {
    static func parse(_ source: String) -> [BlockNode] {
        guard !source.isEmpty else { return [] }
        var state = ParserState()
        let lines = source.splitLinesPreservingTerminators()
        for line in lines {
            state.processLine(line)
        }
        state.finalize()
        return state.blocks
    }
}

// MARK: - Parser State

private struct ParserState {
    var blocks: [BlockNode] = []
    var mode: ParseMode = .toplevel
    var accumulator = LineAccumulator()
    var isFirstBlock = true

    enum ParseMode {
        case toplevel
        case fencedCode(fence: String, language: String?)
        case frontmatter
    }

    mutating func processLine(_ line: String) {
        switch mode {
        case .fencedCode(let fence, let language):
            processFencedCodeLine(line, fence: fence, language: language)
        case .frontmatter:
            processFrontmatterLine(line)
        case .toplevel:
            processToplevelLine(line)
        }
    }

    mutating func finalize() {
        switch mode {
        case .fencedCode(let fence, let language):
            // Unclosed code fence — emit as code block anyway
            let code = accumulator.joinedContent
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength
            blocks.append(.fencedCode(FencedCodeBlock(
                language: language, code: code, fence: fence,
                sourceLength: sourceLength
            )))
            accumulator.reset()
        case .frontmatter:
            // Unclosed frontmatter — treat accumulated lines as a paragraph
            let raw = accumulator.prefixText + accumulator.joinedContent
            accumulator.reset()
            accumulator.addLine(raw)
            flushParagraph()
        case .toplevel:
            flushParagraph()
        }
    }

    // MARK: - Toplevel

    private mutating func processToplevelLine(_ line: String) {
        let trimmed = line.trimmingTrailingNewline

        // Blank line
        if trimmed.allSatisfy(\.isWhitespace) || trimmed.isEmpty {
            flushParagraph()
            blocks.append(.blankLine(BlankLineBlock(sourceLength: line.count)))
            return
        }

        // ATX heading: # ... ######
        if let heading = tryParseHeading(line) {
            flushParagraph()
            blocks.append(heading)
            return
        }

        // Fenced code block opening: ``` or ~~~
        if let (fence, language) = tryParseFenceOpening(trimmed) {
            flushParagraph()
            mode = .fencedCode(fence: fence, language: language)
            accumulator.reset()
            accumulator.prefixText = line
            accumulator.prefixLength = line.count
            return
        }

        // Frontmatter: --- at document start
        if isFirstBlock && blocks.isEmpty && accumulator.isEmpty && trimmed == "---" {
            mode = .frontmatter
            accumulator.reset()
            accumulator.prefixText = line
            accumulator.prefixLength = line.count
            return
        }

        // Thematic break: ---, ***, ___
        if tryParseThematicBreak(trimmed) != nil {
            flushParagraph()
            blocks.append(.thematicBreak(ThematicBreakBlock(sourceText: line)))
            return
        }

        // Default: paragraph continuation
        accumulator.addLine(line)
    }

    // MARK: - Fenced Code

    private mutating func processFencedCodeLine(
        _ line: String, fence: String, language: String?
    ) {
        let trimmed = line.trimmingTrailingNewline.trimmingCharacters(in: .whitespaces)
        let fenceChar = fence.first!
        let fenceCount = fence.count

        // Check for closing fence: same or more of the same character, nothing else
        if trimmed.count >= fenceCount
            && trimmed.allSatisfy({ $0 == fenceChar })
        {
            let code = accumulator.joinedContent
            let sourceLength =
                accumulator.prefixLength + accumulator.sourceLength + line.count
            blocks.append(.fencedCode(FencedCodeBlock(
                language: language, code: code, fence: fence,
                sourceLength: sourceLength
            )))
            accumulator.reset()
            mode = .toplevel
        } else {
            accumulator.addLine(line)
        }
    }

    // MARK: - Frontmatter

    private mutating func processFrontmatterLine(_ line: String) {
        let trimmed = line.trimmingTrailingNewline
        if trimmed == "---" {
            let yaml = accumulator.joinedContent
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength + line.count
            blocks.append(.frontmatter(FrontmatterBlock(
                yaml: yaml, sourceLength: sourceLength
            )))
            accumulator.reset()
            mode = .toplevel
        } else {
            accumulator.addLine(line)
        }
    }

    // MARK: - Helpers

    private mutating func flushParagraph() {
        guard !accumulator.isEmpty else { return }
        let raw = accumulator.joinedContent
        let sourceLength = accumulator.sourceLength

        // Strip trailing newline(s) for inline parsing
        let trailingNewlines = raw.reversed().prefix(while: { $0 == "\n" }).count
        let contentText = String(raw.dropLast(trailingNewlines))
        let inlines = InlineParser.parse(contentText)

        blocks.append(.paragraph(ParagraphBlock(
            content: inlines, sourceLength: sourceLength,
            trailingNewlineCount: trailingNewlines
        )))
        accumulator.reset()
        isFirstBlock = false
    }

    private mutating func tryParseHeading(_ line: String) -> BlockNode? {
        let chars = Array(line)
        var i = 0

        // Count leading #
        while i < chars.count && chars[i] == "#" && i < 6 { i += 1 }
        let level = i
        guard level >= 1 && level <= 6 else { return nil }

        // Must be followed by space or end of line
        guard i < chars.count && chars[i] == " " else { return nil }
        i += 1  // skip the space

        // Extract content (everything after "## " up to newline)
        let contentStart = i
        var contentEnd = chars.count
        if contentEnd > 0 && chars[contentEnd - 1] == "\n" {
            contentEnd -= 1
        }

        // Strip optional trailing # sequence
        var trailingEnd = contentEnd
        while trailingEnd > contentStart && chars[trailingEnd - 1] == "#" {
            trailingEnd -= 1
        }
        if trailingEnd > contentStart && trailingEnd < contentEnd
            && chars[trailingEnd - 1] == " "
        {
            contentEnd = trailingEnd - 1
        }

        let contentText = String(chars[contentStart..<contentEnd])
        let inlines = InlineParser.parse(contentText)

        isFirstBlock = false
        return .heading(HeadingBlock(
            level: level, content: inlines, sourceLength: line.count
        ))
    }

    private func tryParseFenceOpening(_ trimmed: String) -> (String, String?)? {
        let chars = Array(trimmed)
        guard !chars.isEmpty else { return nil }
        let fenceChar = chars[0]
        guard fenceChar == "`" || fenceChar == "~" else { return nil }

        var count = 0
        while count < chars.count && chars[count] == fenceChar { count += 1 }
        guard count >= 3 else { return nil }

        let fence = String(repeating: fenceChar, count: count)
        let rest = String(chars[count...]).trimmingCharacters(in: .whitespaces)
        let language = rest.isEmpty ? nil : rest
        return (fence, language)
    }

    private func tryParseThematicBreak(_ trimmed: String) -> Bool? {
        let chars = Array(trimmed.filter { !$0.isWhitespace })
        guard chars.count >= 3 else { return nil }
        guard let first = chars.first, first == "-" || first == "*" || first == "_" else {
            return nil
        }
        guard chars.allSatisfy({ $0 == first }) else { return nil }
        return true
    }
}

// MARK: - Line Accumulator

private struct LineAccumulator {
    var lines: [String] = []
    var sourceLength: Int = 0
    var prefixText: String = ""
    var prefixLength: Int = 0

    mutating func addLine(_ line: String) {
        lines.append(line)
        sourceLength += line.count
    }

    mutating func reset() {
        lines.removeAll()
        sourceLength = 0
        prefixText = ""
        prefixLength = 0
    }

    var isEmpty: Bool { lines.isEmpty }
    var joinedContent: String { lines.joined() }
}

// MARK: - String Helpers

extension String {
    func splitLinesPreservingTerminators() -> [String] {
        guard !isEmpty else { return [] }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let lineEnd =
                self[start...].firstIndex(of: "\n")
                .map { self.index(after: $0) } ?? endIndex
            result.append(String(self[start..<lineEnd]))
            start = lineEnd
        }
        return result
    }

    var trimmingTrailingNewline: String {
        if hasSuffix("\n") { return String(dropLast()) }
        return self
    }
}
