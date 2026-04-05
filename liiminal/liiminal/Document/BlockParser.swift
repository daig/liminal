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

// MARK: - List Item Info

private struct ListItemInfo {
    let indent: Int
    let ordered: Bool
    let number: Int
    let checked: Bool?
    let contentStart: Int
}

// MARK: - Parser State

private struct ParserState {
    var blocks: [BlockNode] = []
    var mode: ParseMode = .toplevel
    var accumulator = LineAccumulator()
    var listItems: [(line: String, info: ListItemInfo)] = []
    var blockquoteLines: [String] = []
    var isFirstBlock = true

    enum ParseMode {
        case toplevel
        case fencedCode(fence: String, language: String?)
        case frontmatter
        case displayLatex
        case htmlBlock(endCondition: HTMLBlockEndCondition)
    }

    enum HTMLBlockEndCondition {
        case tag(String)       // types 1: ends at </tag>
        case comment           // type 2: ends at -->
        case processingInstr   // type 3: ends at ?>
        case declaration       // type 4: ends at >
        case cdata             // type 5: ends at ]]>
        case blankLine         // types 6/7: ends at blank line
    }

    mutating func processLine(_ line: String) {
        switch mode {
        case .fencedCode(let fence, let language):
            processFencedCodeLine(line, fence: fence, language: language)
        case .frontmatter:
            processFrontmatterLine(line)
        case .displayLatex:
            processDisplayLatexLine(line)
        case .htmlBlock(let endCondition):
            processHTMLBlockLine(line, endCondition: endCondition)
        case .toplevel:
            processToplevelLine(line)
        }
    }

    mutating func finalize() {
        switch mode {
        case .fencedCode(let fence, let language):
            let code = accumulator.joinedContent
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength
            blocks.append(.fencedCode(FencedCodeBlock(
                language: language, code: code, fence: fence,
                sourceLength: sourceLength
            )))
            accumulator.reset()
        case .frontmatter:
            let raw = accumulator.prefixText + accumulator.joinedContent
            accumulator.reset()
            accumulator.addLine(raw)
            flushParagraph()
        case .displayLatex:
            // Unclosed display latex — emit anyway
            let latex = accumulator.joinedContent
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength
            blocks.append(.displayLatex(DisplayLatexBlock(
                latex: latex, sourceLength: sourceLength
            )))
            accumulator.reset()
        case .htmlBlock:
            // Unclosed HTML block — emit what we have
            let raw = accumulator.prefixText + accumulator.joinedContent
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength
            blocks.append(.htmlBlock(HTMLBlock(
                rawHTML: raw, sourceLength: sourceLength
            )))
            accumulator.reset()
        case .toplevel:
            flushBlockquote()
            flushList()
            flushParagraph()
        }
    }

    // MARK: - Toplevel

    private mutating func processToplevelLine(_ line: String) {
        let trimmed = line.trimmingTrailingNewline

        // Blank line — ends all pending blocks
        if trimmed.allSatisfy(\.isWhitespace) || trimmed.isEmpty {
            flushBlockquote()
            flushList()
            flushParagraph()
            blocks.append(.blankLine(BlankLineBlock(sourceLength: line.count)))
            return
        }

        // Blockquote continuation
        if trimmed.hasPrefix(">") {
            flushList()
            flushParagraph()
            blockquoteLines.append(line)
            return
        }

        // If we had blockquote lines and this isn't one, flush them
        if !blockquoteLines.isEmpty {
            flushBlockquote()
        }

        // List item
        if let info = Self.tryParseListItem(line) {
            flushParagraph()
            listItems.append((line, info))
            return
        }

        // If we had list items and this isn't one, flush them
        if !listItems.isEmpty {
            flushList()
        }

        // ATX heading
        if let heading = tryParseHeading(line) {
            flushParagraph()
            blocks.append(heading)
            return
        }

        // Fenced code block opening
        if let (fence, language) = tryParseFenceOpening(trimmed) {
            flushParagraph()
            mode = .fencedCode(fence: fence, language: language)
            accumulator.reset()
            accumulator.prefixText = line
            accumulator.prefixLength = line.count
            return
        }

        // Display LaTeX opening: $$ on its own line
        if trimmed == "$$" {
            flushParagraph()
            mode = .displayLatex
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

        // Thematic break
        if Self.isThematicBreak(trimmed) {
            flushParagraph()
            blocks.append(.thematicBreak(ThematicBreakBlock(sourceText: line)))
            return
        }

        // HTML block
        if let endCondition = Self.tryParseHTMLBlockOpening(trimmed) {
            flushParagraph()
            // Check if this single line also contains the end condition
            if Self.htmlBlockLineContainsEnd(trimmed, endCondition: endCondition) {
                blocks.append(.htmlBlock(HTMLBlock(
                    rawHTML: line, sourceLength: line.count
                )))
                isFirstBlock = false
            } else {
                mode = .htmlBlock(endCondition: endCondition)
                accumulator.reset()
                accumulator.prefixText = line
                accumulator.prefixLength = line.count
            }
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

        if trimmed.count >= fenceCount && trimmed.allSatisfy({ $0 == fenceChar }) {
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
            let sourceLength =
                accumulator.prefixLength + accumulator.sourceLength + line.count
            blocks.append(.frontmatter(FrontmatterBlock(
                yaml: yaml, sourceLength: sourceLength
            )))
            accumulator.reset()
            mode = .toplevel
        } else {
            accumulator.addLine(line)
        }
    }

    // MARK: - Display LaTeX

    private mutating func processDisplayLatexLine(_ line: String) {
        let trimmed = line.trimmingTrailingNewline
        if trimmed == "$$" {
            let latex = accumulator.joinedContent
            let sourceLength =
                accumulator.prefixLength + accumulator.sourceLength + line.count
            blocks.append(.displayLatex(DisplayLatexBlock(
                latex: latex, sourceLength: sourceLength
            )))
            accumulator.reset()
            mode = .toplevel
        } else {
            accumulator.addLine(line)
        }
    }

    // MARK: - HTML Block

    private mutating func processHTMLBlockLine(
        _ line: String, endCondition: HTMLBlockEndCondition
    ) {
        accumulator.addLine(line)
        let trimmed = line.trimmingTrailingNewline

        let isEnd: Bool
        switch endCondition {
        case .blankLine:
            isEnd = trimmed.allSatisfy(\.isWhitespace) || trimmed.isEmpty
        default:
            isEnd = Self.htmlBlockLineContainsEnd(trimmed, endCondition: endCondition)
        }

        if isEnd {
            let raw: String
            if case .blankLine = endCondition {
                // Don't include the blank line in the HTML content
                let htmlLines = accumulator.lines.dropLast()
                raw = accumulator.prefixText + htmlLines.joined()
            } else {
                raw = accumulator.prefixText + accumulator.joinedContent
            }
            let sourceLength = accumulator.prefixLength + accumulator.sourceLength
            blocks.append(.htmlBlock(HTMLBlock(
                rawHTML: raw, sourceLength: sourceLength
            )))
            accumulator.reset()
            mode = .toplevel
            isFirstBlock = false
        }
    }

    // MARK: - HTML Block Detection

    /// CommonMark HTML block types 1-7.
    private static let type1Tags: Set<String> = [
        "script", "pre", "style", "textarea",
    ]

    /// Block-level HTML tags (type 6).
    private static let type6Tags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html",
        "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "ol",
        "optgroup", "option", "p", "param", "search", "section", "summary",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    static func tryParseHTMLBlockOpening(_ trimmed: String) -> HTMLBlockEndCondition? {
        guard trimmed.hasPrefix("<") else { return nil }
        let lower = trimmed.lowercased()

        // Type 2: <!-- comment
        if lower.hasPrefix("<!--") { return .comment }

        // Type 3: <? processing instruction
        if lower.hasPrefix("<?") { return .processingInstr }

        // Type 5: <![CDATA[
        if lower.hasPrefix("<![cdata[") { return .cdata }

        // Type 4: <! declaration (must come after CDATA check)
        if lower.hasPrefix("<!") && lower.count > 2 && lower[lower.index(lower.startIndex, offsetBy: 2)].isLetter {
            return .declaration
        }

        // Extract tag name from opening or closing tag
        let tagStart = lower.hasPrefix("</") ? 2 : 1
        var i = tagStart
        let chars = Array(lower)
        while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "-") {
            i += 1
        }
        guard i > tagStart else { return nil }
        let tagName = String(chars[tagStart..<i])

        // After tag name must be whitespace, >, />, or end of line
        if i < chars.count {
            let next = chars[i]
            guard next == " " || next == "\t" || next == ">" || next == "/" else { return nil }
        }

        // Type 1: script, pre, style, textarea
        if type1Tags.contains(tagName) { return .tag(tagName) }

        // Type 6: block-level tags
        if type6Tags.contains(tagName) { return .blankLine }

        // Type 7: any other complete tag on its own line (opening or self-closing)
        // Must not be an inline-level element
        if !lower.hasPrefix("</") {
            return .blankLine
        }

        return nil
    }

    static func htmlBlockLineContainsEnd(
        _ line: String, endCondition: HTMLBlockEndCondition
    ) -> Bool {
        let lower = line.lowercased()
        switch endCondition {
        case .tag(let tag): return lower.contains("</\(tag)>")
        case .comment:      return lower.contains("-->")
        case .processingInstr: return lower.contains("?>")
        case .declaration:  return lower.contains(">")
        case .cdata:        return lower.contains("]]>")
        case .blankLine:    return false  // blank line checked separately
        }
    }

    // MARK: - Flush Helpers

    private mutating func flushParagraph() {
        guard !accumulator.isEmpty else { return }
        let lines = accumulator.lines
        let totalSourceLength = accumulator.sourceLength

        // Check if this is actually a table
        if let (table, consumed) = Self.tryParseTable(from: lines) {
            blocks.append(.table(table))
            let remaining = Array(lines.dropFirst(consumed))
            accumulator.reset()
            if !remaining.isEmpty {
                for l in remaining { accumulator.addLine(l) }
                flushParagraph()
            }
            isFirstBlock = false
            return
        }

        let raw = accumulator.joinedContent
        let trailingNewlines = raw.reversed().prefix(while: { $0 == "\n" }).count
        let contentText = String(raw.dropLast(trailingNewlines))
        let blockIDParse = Self.extractTrailingBlockID(from: contentText)
        let inlines = InlineParser.parse(blockIDParse.content)

        blocks.append(.paragraph(ParagraphBlock(
            content: inlines, sourceLength: totalSourceLength,
            trailingNewlineCount: trailingNewlines,
            contentSourceLength: blockIDParse.content.count,
            blockID: blockIDParse.blockID,
            blockIDSourceLength: blockIDParse.syntaxLength
        )))
        accumulator.reset()
        isFirstBlock = false
    }

    private mutating func flushList() {
        guard !listItems.isEmpty else { return }

        let isOrdered = listItems[0].info.ordered
        let startNumber = listItems[0].info.number
        var totalSourceLength = 0
        var items: [ListItem] = []

        for (line, info) in listItems {
            let contentText =
                String(line.dropFirst(info.contentStart)).trimmingTrailingNewline
            let blockIDParse = Self.extractTrailingBlockID(from: contentText)
            let inlines = InlineParser.parse(blockIDParse.content)
            let indentLevel = info.indent / 2
            items.append(ListItem(
                content: inlines, checked: info.checked,
                indent: indentLevel, number: info.number,
                sourceLength: line.count,
                markerLength: info.contentStart,
                contentSourceLength: blockIDParse.content.count,
                blockID: blockIDParse.blockID,
                blockIDSourceLength: blockIDParse.syntaxLength
            ))
            totalSourceLength += line.count
        }

        blocks.append(.list(ListBlock(
            ordered: isOrdered, startNumber: startNumber,
            items: items, sourceLength: totalSourceLength
        )))
        listItems.removeAll()
        isFirstBlock = false
    }

    private mutating func flushBlockquote() {
        guard !blockquoteLines.isEmpty else { return }

        let sourceLength = blockquoteLines.reduce(0) { $0 + $1.count }

        // Strip "> " or ">" prefix from each line, then recursively parse
        var strippedLines: [String] = []
        for line in blockquoteLines {
            let trimmed = line.trimmingTrailingNewline
            if trimmed.hasPrefix("> ") {
                strippedLines.append(String(trimmed.dropFirst(2)) + "\n")
            } else if trimmed.hasPrefix(">") {
                strippedLines.append(String(trimmed.dropFirst(1)) + "\n")
            } else {
                strippedLines.append(line)
            }
        }

        let innerSource = strippedLines.joined()
        let children = BlockParser.parse(innerSource)

        blocks.append(.blockquote(BlockquoteBlock(
            children: children, sourceLength: sourceLength
        )))
        blockquoteLines.removeAll()
        isFirstBlock = false
    }

    // MARK: - Line Detectors

    private mutating func tryParseHeading(_ line: String) -> BlockNode? {
        let chars = Array(line)
        var i = 0
        while i < chars.count && chars[i] == "#" && i < 6 { i += 1 }
        let level = i
        guard level >= 1 && level <= 6 else { return nil }
        guard i < chars.count && chars[i] == " " else { return nil }
        i += 1

        let contentStart = i
        var contentEnd = chars.count
        if contentEnd > 0 && chars[contentEnd - 1] == "\n" { contentEnd -= 1 }

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
        let blockIDParse = Self.extractTrailingBlockID(from: contentText)
        let inlines = InlineParser.parse(blockIDParse.content)
        isFirstBlock = false
        return .heading(HeadingBlock(
            level: level,
            content: inlines,
            sourceLength: line.count,
            contentSourceLength: blockIDParse.content.count,
            blockID: blockIDParse.blockID,
            blockIDSourceLength: blockIDParse.syntaxLength
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

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let chars = Array(trimmed.filter { !$0.isWhitespace })
        guard chars.count >= 3 else { return false }
        guard let first = chars.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        return chars.allSatisfy { $0 == first }
    }

    static func tryParseListItem(_ line: String) -> ListItemInfo? {
        let chars = Array(line)
        var i = 0

        // Leading whitespace (indent)
        while i < chars.count && chars[i] == " " { i += 1 }
        let indent = i
        guard i < chars.count else { return nil }

        var ordered = false
        var number = 0

        if chars[i] == "-" || chars[i] == "*" || chars[i] == "+" {
            // Unordered — but make sure it's not a thematic break
            let marker = chars[i]
            i += 1
            // Must be followed by space
            guard i < chars.count && chars[i] == " " else { return nil }
            // Quick check: if the rest is only the same marker char + spaces, skip (thematic break)
            let rest = String(chars[i...]).trimmingCharacters(in: .whitespaces)
            if rest.allSatisfy({ $0 == marker }) && rest.count >= 2 { return nil }
            i += 1
        } else if chars[i].isNumber {
            let numStart = i
            while i < chars.count && chars[i].isNumber { i += 1 }
            guard i < chars.count && chars[i] == "." else { return nil }
            number = Int(String(chars[numStart..<i])) ?? 0
            i += 1
            guard i < chars.count && chars[i] == " " else { return nil }
            i += 1
            ordered = true
        } else {
            return nil
        }

        // Task list checkbox: [ ] or [x] or [X]
        var checked: Bool? = nil
        if i + 3 <= chars.count && chars[i] == "[" && chars[i + 2] == "]" {
            let mark = chars[i + 1]
            if mark == " " {
                checked = false
                i += 3
                if i < chars.count && chars[i] == " " { i += 1 }
            } else if mark == "x" || mark == "X" {
                checked = true
                i += 3
                if i < chars.count && chars[i] == " " { i += 1 }
            }
        }

        return ListItemInfo(
            indent: indent, ordered: ordered, number: number,
            checked: checked, contentStart: i
        )
    }

    // MARK: - Table Detection

    static func tryParseTable(from lines: [String]) -> (table: TableBlock, consumed: Int)? {
        guard lines.count >= 2 else { return nil }

        let headerLine = lines[0].trimmingTrailingNewline
        let separatorLine = lines[1].trimmingTrailingNewline

        guard headerLine.contains("|") else { return nil }
        guard isTableSeparator(separatorLine) else { return nil }

        var rowOffset = 0
        let headerCells = parseTableRowCells(headerLine, rowOffset: rowOffset)
        rowOffset += lines[0].count

        let separatorOffset = rowOffset
        let separatorLength = lines[1].count
        let alignments = parseTableAlignments(separatorLine)
        rowOffset += separatorLength

        var consumed = 2
        var bodyRows: [[TableCell]] = []

        for i in 2..<lines.count {
            let row = lines[i].trimmingTrailingNewline
            guard row.contains("|") else { break }
            bodyRows.append(parseTableRowCells(row, rowOffset: rowOffset))
            rowOffset += lines[i].count
            consumed += 1
        }

        let sourceLength = lines.prefix(consumed).reduce(0) { $0 + $1.count }
        let table = TableBlock(
            headerCells: headerCells, alignments: alignments,
            bodyRows: bodyRows, sourceLength: sourceLength,
            separatorOffset: separatorOffset, separatorLength: separatorLength
        )
        return (table, consumed)
    }

    static func extractTrailingBlockID(from content: String) -> (
        content: String, blockID: String?, syntaxLength: Int
    ) {
        let chars = Array(content)
        guard !chars.isEmpty else {
            return (content, nil, 0)
        }

        func isBlockIDCharacter(_ char: Character) -> Bool {
            char.isLetter || char.isNumber || char == "-" || char == "_"
        }

        var end = chars.count
        while end > 0 && chars[end - 1].isWhitespace {
            end -= 1
        }

        guard end > 0 else {
            return (content, nil, 0)
        }

        var idStart = end
        while idStart > 0 && isBlockIDCharacter(chars[idStart - 1]) {
            idStart -= 1
        }

        guard idStart < end else {
            return (content, nil, 0)
        }

        let caretIndex = idStart - 1
        guard caretIndex >= 0, chars[caretIndex] == "^" else {
            return (content, nil, 0)
        }

        guard caretIndex > 0, chars[caretIndex - 1].isWhitespace else {
            return (content, nil, 0)
        }

        var contentEnd = caretIndex - 1
        while contentEnd > 0 && chars[contentEnd - 1].isWhitespace {
            contentEnd -= 1
        }

        let blockID = String(chars[idStart..<end])
        guard !blockID.isEmpty else {
            return (content, nil, 0)
        }

        return (
            String(chars[0..<contentEnd]),
            blockID,
            chars.count - contentEnd
        )
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") && trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func parseTableRowCells(
        _ line: String, rowOffset: Int
    ) -> [TableCell] {
        let chars = Array(line)
        var pipePositions: [Int] = []
        for (i, ch) in chars.enumerated() {
            if ch == "|" { pipePositions.append(i) }
        }
        guard pipePositions.count >= 2 else { return [] }

        var cells: [TableCell] = []
        for i in 0..<(pipePositions.count - 1) {
            let cellStart = pipePositions[i] + 1
            let cellEnd = pipePositions[i + 1]

            // Skip leading/trailing whitespace to find content bounds
            var contentStart = cellStart
            while contentStart < cellEnd && chars[contentStart] == " " {
                contentStart += 1
            }
            var contentEnd = cellEnd
            while contentEnd > contentStart && chars[contentEnd - 1] == " " {
                contentEnd -= 1
            }

            let cellText = String(chars[contentStart..<contentEnd])
            let content = InlineParser.parse(cellText)
            cells.append(TableCell(
                content: content,
                sourceOffset: rowOffset + contentStart
            ))
        }
        return cells
    }

    private static func parseTableAlignments(_ line: String) -> [TableAlignment?] {
        var cells = line.split(
            separator: "|", omittingEmptySubsequences: false
        ).map { String($0).trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }

        return cells.map { cell in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            if left { return .left }
            return nil
        }
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
