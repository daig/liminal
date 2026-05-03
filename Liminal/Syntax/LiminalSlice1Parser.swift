import CambiumBuilder
import CambiumCore

struct LiminalSlice1CSTParser {
    private let source: String
    private let lines: [SourceLine]
    private var currentLineIndex = 0

    var diagnostics: [LiminalDiagnostic] = []

    init(source: String) {
        self.source = source
        self.lines = SourceLine.split(source)
    }

    mutating func parse(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.root)

        while currentLineIndex < lines.count {
            let line = lines[currentLineIndex]
            if line.isBlank {
                try emitBlankLine(line, with: &builder)
                currentLineIndex += 1
            } else if let heading = headingInfo(for: line) {
                try emitHeading(heading, line: line, with: &builder)
                currentLineIndex += 1
            } else if let embed = wikiEmbedBlockInfo(for: line) {
                try emitWikiEmbedBlock(embed, line: line, with: &builder)
                currentLineIndex += 1
            } else {
                try emitParagraph(with: &builder)
            }
        }

        try builder.finishNode()
    }

    private mutating func emitBlankLine(
        _ line: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.blankLine)
        try emitWhitespace(line.contentText, with: &builder)
        try emitNewline(line.newlineText, with: &builder)
        try builder.finishNode()
    }

    private mutating func emitHeading(
        _ heading: HeadingInfo,
        line: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.atxHeading)
        try emitWhitespace(heading.indentText, with: &builder)
        try builder.token(.hashRun, text: heading.markerText)
        try emitWhitespace(heading.markerWhitespaceText, with: &builder)
        try emitInlineContent(
            heading.bodyText,
            baseByteOffset: line.byteOffset(of: heading.bodyStart),
            with: &builder
        )

        if let closingWhitespace = heading.closingWhitespaceText,
           let closingMarker = heading.closingMarkerText
        {
            try emitWhitespace(closingWhitespace, with: &builder)
            try builder.token(.hashRun, text: closingMarker)
        }
        try emitWhitespace(heading.trailingWhitespaceText, with: &builder)
        try emitNewline(line.newlineText, with: &builder)
        try builder.finishNode()
    }

    private mutating func emitWikiEmbedBlock(
        _ embed: WikiEmbedBlockInfo,
        line: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.wikiEmbedBlock)
        try emitWhitespace(embed.indentText, with: &builder)
        try emitWikiEmbedBody(
            embed.bodyText,
            baseByteOffset: line.byteOffset(of: embed.bodyStart),
            complete: embed.isComplete,
            with: &builder
        )
        try emitWhitespace(embed.trailingWhitespaceText, with: &builder)
        try emitNewline(line.newlineText, with: &builder)
        try builder.finishNode()
    }

    private mutating func emitParagraph(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let startLineIndex = currentLineIndex
        var endLineIndex = currentLineIndex

        repeat {
            endLineIndex += 1
            guard endLineIndex < lines.count else {
                break
            }
        } while !startsDocumentItem(lines[endLineIndex])

        let firstLine = lines[startLineIndex]
        let finalLine = lines[endLineIndex - 1]
        let inlineSlice = source[firstLine.contentStart..<finalLine.contentEnd]

        builder.startNode(.paragraph)
        try emitInlineContent(
            String(inlineSlice),
            baseByteOffset: firstLine.startByteOffset,
            with: &builder
        )
        try emitNewline(finalLine.newlineText, with: &builder)
        try builder.finishNode()

        currentLineIndex = endLineIndex
    }

    private mutating func emitInlineContent(
        _ text: String,
        baseByteOffset: Int,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.inlineContent)
        try LiminalInlineCSTParser.emitChildren(
            source: text,
            baseByteOffset: baseByteOffset,
            diagnostics: &diagnostics,
            with: &builder
        )
        try builder.finishNode()
    }

    private mutating func emitWikiEmbedBody(
        _ text: String,
        baseByteOffset: Int,
        complete: Bool,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try LiminalInlineCSTParser.emitWikiEmbedBody(
            source: text,
            baseByteOffset: baseByteOffset,
            complete: complete,
            diagnostics: &diagnostics,
            with: &builder
        )
    }

    private func startsDocumentItem(_ line: SourceLine) -> Bool {
        line.isBlank || headingInfo(for: line) != nil || wikiEmbedBlockInfo(for: line) != nil
    }

    private func headingInfo(for line: SourceLine) -> HeadingInfo? {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content) else {
            return nil
        }

        var markerEnd = indentEnd
        var markerLength = 0
        while markerEnd < content.endIndex, content[markerEnd] == "#" {
            markerLength += 1
            markerEnd = content.index(after: markerEnd)
        }

        guard (1...6).contains(markerLength),
              markerEnd < content.endIndex,
              content[markerEnd].isHorizontalWhitespace
        else {
            return nil
        }

        var bodyStart = markerEnd
        while bodyStart < content.endIndex, content[bodyStart].isHorizontalWhitespace {
            bodyStart = content.index(after: bodyStart)
        }

        let bodyAndClosing = splitHeadingClosingMarker(in: content[bodyStart..<content.endIndex])

        return HeadingInfo(
            indentText: String(content[content.startIndex..<indentEnd]),
            markerText: String(content[indentEnd..<markerEnd]),
            markerWhitespaceText: String(content[markerEnd..<bodyStart]),
            bodyStart: bodyAndClosing.bodyStart,
            bodyText: String(bodyAndClosing.bodyText),
            closingWhitespaceText: bodyAndClosing.closingWhitespaceText,
            closingMarkerText: bodyAndClosing.closingMarkerText,
            trailingWhitespaceText: bodyAndClosing.trailingWhitespaceText
        )
    }

    private func splitHeadingClosingMarker(
        in body: Substring
    ) -> HeadingBodyParts {
        var trimEnd = body.endIndex
        while trimEnd > body.startIndex {
            let previous = body.index(before: trimEnd)
            guard body[previous].isHorizontalWhitespace else {
                break
            }
            trimEnd = previous
        }

        var markerStart = trimEnd
        while markerStart > body.startIndex {
            let previous = body.index(before: markerStart)
            guard body[previous] == "#" else {
                break
            }
            markerStart = previous
        }

        if markerStart < trimEnd, markerStart > body.startIndex {
            let beforeMarker = body.index(before: markerStart)
            if body[beforeMarker].isHorizontalWhitespace {
                var whitespaceStart = markerStart
                while whitespaceStart > body.startIndex {
                    let previous = body.index(before: whitespaceStart)
                    guard body[previous].isHorizontalWhitespace else {
                        break
                    }
                    whitespaceStart = previous
                }

                return HeadingBodyParts(
                    bodyStart: body.startIndex,
                    bodyText: body[body.startIndex..<whitespaceStart],
                    closingWhitespaceText: String(body[whitespaceStart..<markerStart]),
                    closingMarkerText: String(body[markerStart..<trimEnd]),
                    trailingWhitespaceText: String(body[trimEnd..<body.endIndex])
                )
            }
        }

        return HeadingBodyParts(
            bodyStart: body.startIndex,
            bodyText: body,
            closingWhitespaceText: nil,
            closingMarkerText: nil,
            trailingWhitespaceText: ""
        )
    }

    private func wikiEmbedBlockInfo(for line: SourceLine) -> WikiEmbedBlockInfo? {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content) else {
            return nil
        }
        guard content[indentEnd..<content.endIndex].hasPrefix("![[") else {
            return nil
        }

        let bodyStart = indentEnd
        guard let closeStart = findWikiClose(
            in: content,
            from: content.index(indentEnd, offsetBy: 3),
            stoppingAtNewline: false
        ) else {
            return WikiEmbedBlockInfo(
                indentText: String(content[content.startIndex..<indentEnd]),
                bodyStart: bodyStart,
                bodyText: String(content[bodyStart..<content.endIndex]),
                trailingWhitespaceText: "",
                isComplete: false
            )
        }

        let closeEnd = content.index(closeStart, offsetBy: 2)
        let trailing = content[closeEnd..<content.endIndex]
        guard trailing.allSatisfy(\.isHorizontalWhitespace) else {
            return nil
        }

        return WikiEmbedBlockInfo(
            indentText: String(content[content.startIndex..<indentEnd]),
            bodyStart: bodyStart,
            bodyText: String(content[bodyStart..<closeEnd]),
            trailingWhitespaceText: String(trailing),
            isComplete: true
        )
    }

    private func indentationEnd(in content: Substring) -> String.Index? {
        var index = content.startIndex
        var columns = 0

        while index < content.endIndex {
            switch content[index] {
            case " ":
                columns += 1
            case "\t":
                columns += 4 - (columns % 4)
            default:
                return columns <= 3 ? index : nil
            }

            guard columns <= 3 else {
                return nil
            }
            index = content.index(after: index)
        }

        return index
    }

    private func findWikiClose(
        in content: Substring,
        from start: String.Index,
        stoppingAtNewline: Bool
    ) -> String.Index? {
        var index = start
        while index < content.endIndex {
            if stoppingAtNewline, content[index].isNewlineStart {
                return nil
            }
            if content[index] == "]" {
                let next = content.index(after: index)
                if next < content.endIndex, content[next] == "]", !content.isEscaped(index) {
                    return index
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    private func emitWhitespace(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.whitespace, text: text)
    }

    private func emitNewline(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.newline, text: text)
    }
}

private struct HeadingInfo {
    var indentText: String
    var markerText: String
    var markerWhitespaceText: String
    var bodyStart: String.Index
    var bodyText: String
    var closingWhitespaceText: String?
    var closingMarkerText: String?
    var trailingWhitespaceText: String
}

private struct HeadingBodyParts {
    var bodyStart: String.Index
    var bodyText: Substring
    var closingWhitespaceText: String?
    var closingMarkerText: String?
    var trailingWhitespaceText: String
}

private struct WikiEmbedBlockInfo {
    var indentText: String
    var bodyStart: String.Index
    var bodyText: String
    var trailingWhitespaceText: String
    var isComplete: Bool
}

private struct SourceLine {
    var contentStart: String.Index
    var contentEnd: String.Index
    var newlineEnd: String.Index
    var startByteOffset: Int
    var source: String

    var content: Substring {
        source[contentStart..<contentEnd]
    }

    var contentText: String {
        String(content)
    }

    var newlineText: String {
        String(source[contentEnd..<newlineEnd])
    }

    var isBlank: Bool {
        content.allSatisfy(\.isHorizontalWhitespace)
    }

    func byteOffset(of index: String.Index) -> Int {
        startByteOffset + source[contentStart..<index].utf8.count
    }

    static func split(_ source: String) -> [SourceLine] {
        var result: [SourceLine] = []
        var index = source.startIndex
        var byteOffset = 0

        while index < source.endIndex {
            let lineStart = index
            let startByteOffset = byteOffset

            while index < source.endIndex, !source[index].isNewlineStart {
                index = source.index(after: index)
            }

            let contentEnd = index
            if index < source.endIndex {
                if source[index] == "\r" {
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "\n" {
                        index = source.index(after: next)
                    } else {
                        index = next
                    }
                } else {
                    index = source.index(after: index)
                }
            }

            result.append(SourceLine(
                contentStart: lineStart,
                contentEnd: contentEnd,
                newlineEnd: index,
                startByteOffset: startByteOffset,
                source: source
            ))
            byteOffset += source[lineStart..<index].utf8.count
        }

        return result
    }
}

private struct LiminalInlineCSTParser {
    private let source: String
    private let baseByteOffset: Int
    private var index: String.Index
    private var textStart: String.Index
    private var diagnostics: [LiminalDiagnostic] = []

    static func emitChildren(
        source: String,
        baseByteOffset: Int,
        diagnostics: inout [LiminalDiagnostic],
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        var parser = LiminalInlineCSTParser(source: source, baseByteOffset: baseByteOffset)
        try parser.parse(with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
    }

    static func emitWikiEmbedBody(
        source: String,
        baseByteOffset: Int,
        complete: Bool,
        diagnostics: inout [LiminalDiagnostic],
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        var parser = LiminalInlineCSTParser(source: source, baseByteOffset: baseByteOffset)
        try parser.emitWikiEmbedBody(complete: complete, with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
    }

    private init(source: String, baseByteOffset: Int) {
        self.source = source
        self.baseByteOffset = baseByteOffset
        self.index = source.startIndex
        self.textStart = source.startIndex
    }

    private mutating func parse(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        while index < source.endIndex {
            if let newlineEnd = newlineEnd(at: index) {
                try emitLineBreak(newlineEnd: newlineEnd, with: &builder)
                continue
            }

            if source[index] == "`" {
                try flushText(upTo: index, with: &builder)
                try emitCodeSpan(with: &builder)
            } else if source[index..<source.endIndex].hasPrefix("![[") {
                try flushText(upTo: index, with: &builder)
                try emitWikiEmbed(with: &builder)
            } else if source[index..<source.endIndex].hasPrefix("[[") {
                try flushText(upTo: index, with: &builder)
                try emitWikilink(with: &builder)
            } else if source[index..<source.endIndex].hasPrefix("!["),
                      canParseMarkdownImage()
            {
                try flushText(upTo: index, with: &builder)
                try emitMarkdownImage(with: &builder)
            } else if source[index] == "[", canParseMarkdownLink() {
                try flushText(upTo: index, with: &builder)
                try emitMarkdownLink(with: &builder)
            } else {
                index = source.index(after: index)
            }
        }

        try flushText(upTo: source.endIndex, with: &builder)
    }

    private mutating func emitCodeSpan(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let openerStart = index
        let openerText = consumeRun(of: "`")
        let contentStart = index

        if let closerStart = findCodeSpanClose(matching: openerText.count, from: contentStart) {
            let closerEnd = source.index(closerStart, offsetBy: openerText.count)
            builder.startNode(.codeSpan)
            try builder.token(.fenceRun, text: openerText)
            try emitCodeText(String(source[contentStart..<closerStart]), with: &builder)
            try builder.token(.fenceRun, text: openerText)
            try builder.finishNode()
            index = closerEnd
            textStart = index
        } else {
            builder.startNode(.codeSpan)
            try builder.token(.fenceRun, text: openerText)
            try emitCodeText(String(source[contentStart..<source.endIndex]), with: &builder)
            try builder.missingNode(.missing)
            try builder.finishNode()
            appendDiagnostic("missing closing code span delimiter", at: openerStart, length: openerText.utf8.count)
            index = source.endIndex
            textStart = index
        }
    }

    private mutating func emitMarkdownLink(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard let labelClose = findLabelClose(openBracketAt: index) else {
            try emitIncompleteMarkdownLink(kind: .mdLink, with: &builder)
            return
        }

        let destinationOpen = source.index(after: labelClose)
        guard destinationOpen < source.endIndex, source[destinationOpen] == "(" else {
            preconditionFailure("canParseMarkdownLink promised a destination opener after a closed label")
        }

        builder.startNode(.mdLink)
        try emitLinkLabel(labelClose: labelClose, with: &builder)
        try emitLinkDestination(openParenAt: destinationOpen, with: &builder)
        try builder.finishNode()
        textStart = index
    }

    private mutating func emitMarkdownImage(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let bangIndex = index
        let bracketIndex = source.index(after: bangIndex)
        guard let labelClose = findLabelClose(openBracketAt: bracketIndex) else {
            builder.startNode(.mdImage)
            try builder.staticToken(.bang)
            index = bracketIndex
            try emitIncompleteLinkLabel(message: "missing closing image label", with: &builder)
            try builder.finishNode()
            textStart = index
            return
        }

        let destinationOpen = source.index(after: labelClose)
        guard destinationOpen < source.endIndex, source[destinationOpen] == "(" else {
            preconditionFailure("canParseMarkdownImage promised a destination opener after a closed alt label")
        }

        builder.startNode(.mdImage)
        try builder.staticToken(.bang)
        index = bracketIndex
        try emitLinkLabel(labelClose: labelClose, with: &builder)
        try emitLinkDestination(openParenAt: destinationOpen, with: &builder)
        try builder.finishNode()
        textStart = index
    }

    private mutating func emitIncompleteMarkdownLink(
        kind: LiminalKind,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(kind)
        try emitIncompleteLinkLabel(message: "missing closing link label", with: &builder)
        try builder.finishNode()
        textStart = index
    }

    private mutating func emitLinkLabel(
        labelClose: String.Index,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let labelOpen = index
        let labelStart = source.index(after: labelOpen)
        builder.startNode(.linkLabel)
        try builder.staticToken(.leftBracket)
        try emitNestedInlineContent(
            String(source[labelStart..<labelClose]),
            baseByteOffset: globalByteOffset(of: labelStart),
            with: &builder
        )
        try builder.staticToken(.rightBracket)
        try builder.finishNode()
        index = source.index(after: labelClose)
    }

    private mutating func emitIncompleteLinkLabel(
        message: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let labelOpen = index
        let labelStart = source.index(after: labelOpen)
        builder.startNode(.linkLabel)
        try builder.staticToken(.leftBracket)
        try emitNestedInlineContent(
            String(source[labelStart..<source.endIndex]),
            baseByteOffset: globalByteOffset(of: labelStart),
            with: &builder
        )
        try builder.missingNode(.missing)
        try builder.finishNode()
        appendDiagnostic(message, at: labelOpen, length: 1)
        index = source.endIndex
    }

    private mutating func emitLinkDestination(
        openParenAt openParen: String.Index,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        index = openParen
        let destinationStart = source.index(after: openParen)
        builder.startNode(.linkDestination)
        try builder.staticToken(.leftParen)

        if let closeParen = findParenClose(openParenAt: openParen) {
            try emitLinkDestinationText(String(source[destinationStart..<closeParen]), with: &builder)
            try builder.staticToken(.rightParen)
            index = source.index(after: closeParen)
        } else {
            try emitLinkDestinationText(String(source[destinationStart..<source.endIndex]), with: &builder)
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing link destination", at: openParen, length: 1)
            index = source.endIndex
        }

        try builder.finishNode()
    }

    private mutating func emitWikilink(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitWikiDelimitedNode(kind: .wikilink, isEmbed: false, with: &builder)
    }

    private mutating func emitWikiEmbed(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitWikiDelimitedNode(kind: .wikiEmbed, isEmbed: true, with: &builder)
    }

    private mutating func emitWikiEmbedBody(
        complete: Bool,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitWikiDelimitedBody(
            source: source,
            baseByteOffset: baseByteOffset,
            complete: complete,
            isEmbed: true,
            with: &builder
        )
    }

    private mutating func emitWikiDelimitedNode(
        kind: LiminalKind,
        isEmbed: Bool,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let close = findWikiClose(from: isEmbed ? source.index(index, offsetBy: 3) : source.index(index, offsetBy: 2))
        let boundary = close.map { source.index($0, offsetBy: 2) } ?? inlineBoundary(from: index)
        let bodyText = String(source[index..<boundary])

        builder.startNode(kind)
        try emitWikiDelimitedBody(
            source: bodyText,
            baseByteOffset: globalByteOffset(of: index),
            complete: close != nil,
            isEmbed: isEmbed,
            with: &builder
        )
        try builder.finishNode()

        if close == nil {
            appendDiagnostic(
                isEmbed ? "missing closing wiki embed" : "missing closing wikilink",
                at: index,
                length: isEmbed ? 3 : 2
            )
        }
        index = boundary
        textStart = index
    }

    private mutating func emitWikiDelimitedBody(
        source bodySource: String,
        baseByteOffset bodyBaseByteOffset: Int,
        complete: Bool,
        isEmbed: Bool,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        var localIndex = bodySource.startIndex
        if isEmbed {
            try builder.staticToken(.bang)
            localIndex = bodySource.index(after: localIndex)
        }

        try builder.staticToken(.leftBracket)
        try builder.staticToken(.leftBracket)
        localIndex = bodySource.index(localIndex, offsetBy: 2)

        let payloadEnd = complete
            ? bodySource.index(bodySource.endIndex, offsetBy: -2)
            : bodySource.endIndex
        let payload = bodySource[localIndex..<payloadEnd]
        let split = splitWikiPayload(payload)

        builder.startNode(.wikiTarget)
        let targetText = String(payload[payload.startIndex..<split.pipeIndex])
        if !targetText.isEmpty {
            try builder.token(.wikiTargetText, text: targetText)
        }
        try builder.finishNode()

        if let pipeIndex = split.actualPipeIndex {
            try builder.staticToken(.pipe)
            let afterPipe = payload.index(after: pipeIndex)
            let aliasText = String(payload[afterPipe..<payload.endIndex])
            if isEmbed {
                if !aliasText.isEmpty {
                    try builder.largeToken(.rawPayloadText, text: aliasText)
                }
            } else {
                try emitNestedInlineContent(
                    aliasText,
                    baseByteOffset: bodyBaseByteOffset + bodySource[bodySource.startIndex..<afterPipe].utf8.count,
                    with: &builder
                )
            }
        }

        if complete {
            try builder.staticToken(.rightBracket)
            try builder.staticToken(.rightBracket)
        } else {
            try builder.missingNode(.missing)
        }
    }

    private mutating func emitNestedInlineContent(
        _ text: String,
        baseByteOffset: Int,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.inlineContent)
        var nestedDiagnostics: [LiminalDiagnostic] = []
        try LiminalInlineCSTParser.emitChildren(
            source: text,
            baseByteOffset: baseByteOffset,
            diagnostics: &nestedDiagnostics,
            with: &builder
        )
        diagnostics.append(contentsOf: nestedDiagnostics)
        try builder.finishNode()
    }

    private mutating func emitLineBreak(
        newlineEnd: String.Index,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        if textStart < index {
            let previous = source.index(before: index)
            if source[previous] == "\\" {
                try flushText(upTo: previous, with: &builder)
                builder.startNode(.hardBreak)
                try builder.staticToken(.backslash)
                try builder.token(.newline, text: String(source[index..<newlineEnd]))
                try builder.finishNode()
            } else {
                try flushText(upTo: index, with: &builder)
                builder.startNode(.softBreak)
                try builder.token(.newline, text: String(source[index..<newlineEnd]))
                try builder.finishNode()
            }
        } else {
            builder.startNode(.softBreak)
            try builder.token(.newline, text: String(source[index..<newlineEnd]))
            try builder.finishNode()
        }

        index = newlineEnd
        textStart = index
    }

    private mutating func flushText(
        upTo end: String.Index,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard textStart < end else {
            return
        }
        try builder.token(.inlineText, text: String(source[textStart..<end]))
        textStart = end
    }

    private func canParseMarkdownLink() -> Bool {
        guard let labelClose = findLabelClose(openBracketAt: index) else {
            return true
        }
        let afterLabel = source.index(after: labelClose)
        return afterLabel < source.endIndex && source[afterLabel] == "("
    }

    private func canParseMarkdownImage() -> Bool {
        let bracket = source.index(after: index)
        guard let labelClose = findLabelClose(openBracketAt: bracket) else {
            return true
        }
        let afterLabel = source.index(after: labelClose)
        return afterLabel < source.endIndex && source[afterLabel] == "("
    }

    private func findLabelClose(openBracketAt open: String.Index) -> String.Index? {
        var cursor = source.index(after: open)
        var depth = 0
        while cursor < source.endIndex {
            if source[cursor].isNewlineStart {
                return nil
            }
            if source.isEscaped(cursor) {
                cursor = source.index(after: cursor)
            } else if source[cursor] == "[" {
                depth += 1
            } else if source[cursor] == "]" {
                if depth == 0 {
                    return cursor
                }
                depth -= 1
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func findParenClose(openParenAt open: String.Index) -> String.Index? {
        var cursor = source.index(after: open)
        var depth = 0
        while cursor < source.endIndex {
            if source[cursor].isNewlineStart {
                return nil
            }
            if source.isEscaped(cursor) {
                cursor = source.index(after: cursor)
            } else if source[cursor] == "(" {
                depth += 1
            } else if source[cursor] == ")" {
                if depth == 0 {
                    return cursor
                }
                depth -= 1
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func findCodeSpanClose(
        matching delimiterLength: Int,
        from start: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "`" {
                let runStart = cursor
                let run = countRun(of: "`", at: cursor)
                if run == delimiterLength {
                    return runStart
                }
                cursor = source.index(cursor, offsetBy: run)
            } else {
                cursor = source.index(after: cursor)
            }
        }
        return nil
    }

    private func findWikiClose(from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor].isNewlineStart {
                return nil
            }
            if source[cursor] == "]" {
                let next = source.index(after: cursor)
                if next < source.endIndex, source[next] == "]", !source.isEscaped(cursor) {
                    return cursor
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func inlineBoundary(from start: String.Index) -> String.Index {
        var cursor = start
        while cursor < source.endIndex, !source[cursor].isNewlineStart {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private mutating func consumeRun(of character: Character) -> String {
        let start = index
        while index < source.endIndex, source[index] == character {
            index = source.index(after: index)
        }
        return String(source[start..<index])
    }

    private func countRun(of character: Character, at start: String.Index) -> Int {
        var cursor = start
        var count = 0
        while cursor < source.endIndex, source[cursor] == character {
            count += 1
            cursor = source.index(after: cursor)
        }
        return count
    }

    private func newlineEnd(at start: String.Index) -> String.Index? {
        guard start < source.endIndex, source[start].isNewlineStart else {
            return nil
        }
        if source[start] == "\r" {
            let next = source.index(after: start)
            if next < source.endIndex, source[next] == "\n" {
                return source.index(after: next)
            }
            return next
        }
        return source.index(after: start)
    }

    private mutating func emitCodeText(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.codeText, text: text)
    }

    private mutating func emitLinkDestinationText(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.linkDestinationText, text: text)
    }

    private func splitWikiPayload(_ payload: Substring) -> WikiPayloadSplit {
        var cursor = payload.startIndex
        while cursor < payload.endIndex {
            if payload[cursor] == "|", !payload.isEscaped(cursor) {
                return WikiPayloadSplit(pipeIndex: cursor, actualPipeIndex: cursor)
            }
            cursor = payload.index(after: cursor)
        }
        return WikiPayloadSplit(pipeIndex: payload.endIndex, actualPipeIndex: nil)
    }

    private func globalByteOffset(of localIndex: String.Index) -> Int {
        baseByteOffset + source[source.startIndex..<localIndex].utf8.count
    }

    private mutating func appendDiagnostic(
        _ message: String,
        at localIndex: String.Index,
        length: Int
    ) {
        diagnostics.append(LiminalDiagnostic(
            severity: .error,
            message: message,
            range: TextRange(
                start: TextSize(UInt32(globalByteOffset(of: localIndex))),
                length: TextSize(UInt32(length))
            )
        ))
    }
}

private struct WikiPayloadSplit {
    var pipeIndex: String.Index
    var actualPipeIndex: String.Index?
}

private extension Character {
    var isHorizontalWhitespace: Bool {
        self == " " || self == "\t"
    }

    var isNewlineStart: Bool {
        self == "\n" || self == "\r"
    }
}

private extension StringProtocol {
    func isEscaped(_ index: Index) -> Bool {
        var cursor = index
        var backslashCount = 0
        while cursor > startIndex {
            let previous = self.index(before: cursor)
            guard self[previous] == "\\" else {
                break
            }
            backslashCount += 1
            cursor = previous
        }
        return backslashCount % 2 == 1
    }
}
