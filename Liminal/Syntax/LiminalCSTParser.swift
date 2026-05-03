import CambiumBuilder
import CambiumCore

// MARK: - Parser reuse boundaries
//
// Reusable (atomic, self-bounded by source delimiters):
//   paragraph, atxHeading, codeSpan, mdLink, mdImage, wikilink,
//   wikiEmbed, typedInline, structuredEmbed, wikiEmbedBlock,
//   structuredEmbedBlock, valueDeclaration, typedBlock, mathBlock,
//   and htmlBlock.
//
// Not reusable: inlineContent — the same kind is emitted under headings,
// paragraphs, link labels, and wikilink aliases with diverging stop rules,
// so a reused subtree could silently apply the wrong ones.
//
// Sub-nodes (linkLabel, linkDestination, fields, value, wikiTarget) and trivial
// atoms (softBreak, hardBreak, escapedPunctuation, blankLine) are not worth
// their own reuse boundary.

struct LiminalCSTParser {
    private let source: String
    private let baseByteOffset: Int
    private let lines: [SourceLine]
    private var currentLineIndex = 0

    var diagnostics: [LiminalDiagnostic] = []

    init(source: String, baseByteOffset: Int = 0) {
        self.source = source
        self.baseByteOffset = baseByteOffset
        self.lines = SourceLine.split(source, baseByteOffset: baseByteOffset)
    }

    mutating func parse(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.root)
        try parseDocumentItems(with: &builder)
        try builder.finishNode()
    }

    mutating func parseDocumentItems(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        while currentLineIndex < lines.count {
            let line = lines[currentLineIndex]
            if line.isBlank {
                try emitBlankLine(line, with: &builder)
                currentLineIndex += 1
            } else if let heading = headingInfo(for: line) {
                try emitHeading(heading, line: line, with: &builder)
                currentLineIndex += 1
            } else if let rawBlock = rawReservedBlockInfo(for: line) {
                try emitRawReservedBlock(rawBlock, openerLine: line, with: &builder)
            } else if let typedBlock = typedBlockInfo(for: line) {
                try emitTypedBlock(typedBlock, openerLine: line, with: &builder)
            } else if let embed = structuredEmbedBlockInfo(for: line) {
                try emitStructuredEmbedBlock(embed, line: line, with: &builder)
            } else if let embed = wikiEmbedBlockInfo(for: line) {
                try emitWikiEmbedBlock(embed, line: line, with: &builder)
                currentLineIndex += 1
            } else if let declaration = valueDeclarationInfo(for: line) {
                try emitValueDeclaration(declaration, line: line, with: &builder)
            } else {
                try emitParagraph(with: &builder)
            }
        }
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
        let blockID = splitTrailingBlockID(in: heading.bodyText)

        builder.startNode(.atxHeading)
        try emitWhitespace(heading.indentText, with: &builder)
        try builder.token(.hashRun, text: heading.markerText)
        try emitWhitespace(heading.markerWhitespaceText, with: &builder)
        try emitInlineContent(
            blockID?.contentText ?? heading.bodyText,
            baseByteOffset: line.byteOffset(of: heading.bodyStart),
            with: &builder
        )
        if let blockID {
            try emitBlockIDSuffix(blockID, with: &builder)
        }

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
        let inlineText = String(inlineSlice)
        let blockID = splitTrailingBlockID(in: inlineText)

        builder.startNode(.paragraph)
        try emitInlineContent(
            blockID?.contentText ?? inlineText,
            baseByteOffset: firstLine.startByteOffset,
            with: &builder
        )
        if let blockID {
            try emitBlockIDSuffix(blockID, with: &builder)
        }
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

    private mutating func emitStructuredEmbedBlock(
        _ embed: StructuredEmbedBlockInfo,
        line: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.structuredEmbedBlock)
        try emitWhitespace(embed.indentText, with: &builder)
        var parser = LiminalStructuredCSTParser(
            source: embed.bodyText,
            baseByteOffset: line.byteOffset(of: embed.bodyStart)
        )
        try parser.emitStructuredEmbedBody(with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
        try emitWhitespace(embed.trailingWhitespaceText, with: &builder)
        try emitNewline(line.newlineText, with: &builder)
        try builder.finishNode()
        currentLineIndex += 1
    }

    private mutating func emitValueDeclaration(
        _ declaration: ValueDeclarationInfo,
        line: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.valueDeclaration)
        try emitWhitespace(declaration.indentText, with: &builder)
        var parser = LiminalStructuredCSTParser(
            source: declaration.constructorText,
            baseByteOffset: line.byteOffset(of: declaration.constructorStart)
        )
        try parser.emitTypedConstructor(with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
        try emitWhitespace(declaration.trailingWhitespaceText, with: &builder)
        try emitNewline(declaration.newlineText, with: &builder)
        try builder.finishNode()
        currentLineIndex = declaration.endLineIndex + 1
    }

    private mutating func emitTypedBlock(
        _ block: TypedBlockInfo,
        openerLine: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.typedBlock)
        try emitTypedBlockHeader(block, openerLine: openerLine, with: &builder)

        let bodyText: String
        let bodyBaseByteOffset: Int
        if let closeLineIndex = block.closeLineIndex {
            let closeLine = lines[closeLineIndex]
            bodyText = String(source[openerLine.newlineEnd..<closeLine.contentStart])
            bodyBaseByteOffset = openerLine.startByteOffset + source[openerLine.contentStart..<openerLine.newlineEnd].utf8.count
            try emitNestedDocumentItems(bodyText, baseByteOffset: bodyBaseByteOffset, with: &builder)
            try emitTypedBlockClosingFence(
                closeLine,
                colonRunText: block.colonRunText,
                with: &builder
            )
            currentLineIndex = closeLineIndex + 1
        } else {
            bodyText = String(source[openerLine.newlineEnd..<source.endIndex])
            bodyBaseByteOffset = openerLine.startByteOffset + source[openerLine.contentStart..<openerLine.newlineEnd].utf8.count
            try emitNestedDocumentItems(bodyText, baseByteOffset: bodyBaseByteOffset, with: &builder)
            try builder.missingNode(.missing)
            appendDiagnostic(
                "missing closing typed block fence",
                at: openerLine.contentStart,
                length: block.colonRunText.utf8.count
            )
            currentLineIndex = lines.count
        }

        try builder.finishNode()
    }

    private mutating func emitRawReservedBlock(
        _ block: RawReservedBlockInfo,
        openerLine: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(block.kind)
        try emitTypedBlockHeader(block.header, openerLine: openerLine, with: &builder)

        if let closeLineIndex = block.header.closeLineIndex {
            let closeLine = lines[closeLineIndex]
            let payload = String(source[openerLine.newlineEnd..<closeLine.contentStart])
            if !payload.isEmpty {
                try builder.largeToken(.rawPayloadText, text: payload)
            }
            try emitTypedBlockClosingFence(
                closeLine,
                colonRunText: block.header.colonRunText,
                with: &builder
            )
            currentLineIndex = closeLineIndex + 1
        } else {
            let payload = String(source[openerLine.newlineEnd..<source.endIndex])
            if !payload.isEmpty {
                try builder.largeToken(.rawPayloadText, text: payload)
            }
            try builder.missingNode(.missing)
            appendDiagnostic(
                "missing closing \(block.header.qnameText) fence",
                at: openerLine.contentStart,
                length: block.header.colonRunText.utf8.count
            )
            currentLineIndex = lines.count
        }

        try builder.finishNode()
    }

    private mutating func emitTypedBlockHeader(
        _ block: TypedBlockInfo,
        openerLine: SourceLine,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitWhitespace(block.indentText, with: &builder)
        try builder.token(.colonRun, text: block.colonRunText)
        try builder.token(.qname, text: block.qnameText)

        if !block.suffixText.isEmpty {
            var parser = LiminalStructuredCSTParser(
                source: block.suffixText,
                baseByteOffset: openerLine.byteOffset(of: block.suffixStart)
            )
            try parser.emitConstructorSuffix(with: &builder)
            diagnostics.append(contentsOf: parser.diagnostics)
        }

        try emitWhitespace(block.trailingWhitespaceText, with: &builder)
        try emitNewline(openerLine.newlineText, with: &builder)
    }

    private mutating func emitTypedBlockClosingFence(
        _ line: SourceLine,
        colonRunText: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content) else {
            preconditionFailure("closing fence was identified with valid indentation")
        }
        let colonEnd = content.index(indentEnd, offsetBy: colonRunText.count)
        try emitWhitespace(String(content[content.startIndex..<indentEnd]), with: &builder)
        try builder.token(.colonRun, text: colonRunText)
        try emitWhitespace(String(content[colonEnd..<content.endIndex]), with: &builder)
        try emitNewline(line.newlineText, with: &builder)
    }

    private mutating func emitNestedDocumentItems(
        _ bodyText: String,
        baseByteOffset: Int,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !bodyText.isEmpty else {
            return
        }
        var nestedParser = LiminalCSTParser(
            source: bodyText,
            baseByteOffset: baseByteOffset
        )
        try nestedParser.parseDocumentItems(with: &builder)
        diagnostics.append(contentsOf: nestedParser.diagnostics)
    }

    private func startsDocumentItem(_ line: SourceLine) -> Bool {
        line.isBlank
            || headingInfo(for: line) != nil
            || rawReservedBlockInfo(for: line) != nil
            || typedBlockInfo(for: line) != nil
            || structuredEmbedBlockInfo(for: line) != nil
            || wikiEmbedBlockInfo(for: line) != nil
            || valueDeclarationInfo(for: line) != nil
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

    private func structuredEmbedBlockInfo(for line: SourceLine) -> StructuredEmbedBlockInfo? {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content),
              content[indentEnd..<content.endIndex].hasPrefix("!{")
        else {
            return nil
        }

        let scanner = LiminalStructuredScanner(source: source)
        guard let embedEnd = scanner.structuredEmbedEnd(from: indentEnd) else {
            return nil
        }
        guard embedEnd <= content.endIndex else {
            return nil
        }
        let trailing = content[embedEnd..<content.endIndex]
        guard trailing.allSatisfy(\.isHorizontalWhitespace) else {
            return nil
        }

        return StructuredEmbedBlockInfo(
            indentText: String(content[content.startIndex..<indentEnd]),
            bodyStart: indentEnd,
            bodyText: String(content[indentEnd..<embedEnd]),
            trailingWhitespaceText: String(trailing)
        )
    }

    private func valueDeclarationInfo(for line: SourceLine) -> ValueDeclarationInfo? {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content),
              indentEnd < content.endIndex,
              content[indentEnd] == "@"
        else {
            return nil
        }

        let scanner = LiminalStructuredScanner(source: source)
        guard let constructorEnd = scanner.typedConstructorEnd(from: indentEnd) else {
            return nil
        }
        guard let endLineIndex = lineIndex(containingOrEndingAt: constructorEnd, startingAt: currentLineIndex) else {
            return nil
        }

        let endLine = lines[endLineIndex]
        guard constructorEnd <= endLine.contentEnd else {
            return nil
        }
        let trailing = source[constructorEnd..<endLine.contentEnd]
        guard trailing.allSatisfy(\.isHorizontalWhitespace) else {
            return nil
        }

        return ValueDeclarationInfo(
            indentText: String(content[content.startIndex..<indentEnd]),
            constructorStart: indentEnd,
            constructorText: String(source[indentEnd..<constructorEnd]),
            trailingWhitespaceText: String(trailing),
            newlineText: endLine.newlineText,
            endLineIndex: endLineIndex
        )
    }

    private func rawReservedBlockInfo(for line: SourceLine) -> RawReservedBlockInfo? {
        guard let block = typedBlockInfo(for: line) else {
            return nil
        }
        switch block.qnameText {
        case "MathBlock":
            return RawReservedBlockInfo(kind: .mathBlock, header: block)
        case "HtmlBlock":
            return RawReservedBlockInfo(kind: .htmlBlock, header: block)
        default:
            return nil
        }
    }

    private func typedBlockInfo(for line: SourceLine) -> TypedBlockInfo? {
        let content = line.content
        guard let indentEnd = indentationEnd(in: content) else {
            return nil
        }

        var colonEnd = indentEnd
        var colonCount = 0
        while colonEnd < content.endIndex, content[colonEnd] == ":" {
            colonCount += 1
            colonEnd = content.index(after: colonEnd)
        }
        guard colonCount >= 3 else {
            return nil
        }

        let qnameStart = colonEnd
        guard let qnameEnd = LiminalStructuredScanner(source: source).qnameEnd(from: qnameStart) else {
            return nil
        }

        var headerEnd = content.endIndex
        while headerEnd > qnameEnd {
            let previous = content.index(before: headerEnd)
            guard content[previous].isHorizontalWhitespace else {
                break
            }
            headerEnd = previous
        }

        let colonRunText = String(content[indentEnd..<colonEnd])
        return TypedBlockInfo(
            indentText: String(content[content.startIndex..<indentEnd]),
            colonRunText: colonRunText,
            qnameText: String(content[qnameStart..<qnameEnd]),
            suffixStart: qnameEnd,
            suffixText: String(content[qnameEnd..<headerEnd]),
            trailingWhitespaceText: String(content[headerEnd..<content.endIndex]),
            closeLineIndex: closingFenceLineIndex(
                after: currentLineIndex,
                colonRunText: colonRunText
            )
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

    private func closingFenceLineIndex(
        after openerLineIndex: Int,
        colonRunText: String
    ) -> Int? {
        var lineIndex = openerLineIndex + 1
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let content = line.content
            if let indentEnd = indentationEnd(in: content),
               content[indentEnd..<content.endIndex].hasPrefix(colonRunText)
            {
                let colonEnd = content.index(indentEnd, offsetBy: colonRunText.count)
                if colonEnd <= content.endIndex,
                   content[colonEnd..<content.endIndex].allSatisfy(\.isHorizontalWhitespace)
                {
                    return lineIndex
                }
            }
            lineIndex += 1
        }
        return nil
    }

    private func lineIndex(
        containingOrEndingAt index: String.Index,
        startingAt startLineIndex: Int
    ) -> Int? {
        var lineIndex = startLineIndex
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if line.contentStart <= index, index <= line.contentEnd {
                return lineIndex
            }
            lineIndex += 1
        }
        return nil
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

    private func splitTrailingBlockID(in text: String) -> BlockIDSuffixInfo? {
        var suffixEnd = text.endIndex
        while suffixEnd > text.startIndex {
            let previous = text.index(before: suffixEnd)
            guard text[previous].isHorizontalWhitespace else {
                break
            }
            suffixEnd = previous
        }

        guard suffixEnd > text.startIndex else {
            return nil
        }

        var idStart = suffixEnd
        while idStart > text.startIndex {
            let previous = text.index(before: idStart)
            guard text[previous].isAnchorCharacter else {
                break
            }
            idStart = previous
        }

        guard idStart < suffixEnd,
              text[idStart].isAnchorStartCharacter,
              idStart > text.startIndex
        else {
            return nil
        }

        let caretIndex = text.index(before: idStart)
        guard text[caretIndex] == "^", caretIndex > text.startIndex else {
            return nil
        }

        var separatorStart = caretIndex
        while separatorStart > text.startIndex {
            let previous = text.index(before: separatorStart)
            guard text[previous].isHorizontalWhitespace else {
                break
            }
            separatorStart = previous
        }

        guard separatorStart < caretIndex else {
            return nil
        }

        return BlockIDSuffixInfo(
            contentText: String(text[text.startIndex..<separatorStart]),
            separatorText: String(text[separatorStart..<caretIndex]),
            idText: String(text[idStart..<suffixEnd]),
            trailingWhitespaceText: String(text[suffixEnd..<text.endIndex])
        )
    }

    private func emitBlockIDSuffix(
        _ blockID: BlockIDSuffixInfo,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitWhitespace(blockID.separatorText, with: &builder)
        builder.startNode(.blockIdSuffix)
        try builder.staticToken(.caret)
        try builder.token(.anchor, text: blockID.idText)
        try builder.finishNode()
        try emitWhitespace(blockID.trailingWhitespaceText, with: &builder)
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

    private mutating func appendDiagnostic(
        _ message: String,
        at index: String.Index,
        length: Int
    ) {
        diagnostics.append(LiminalDiagnostic(
            severity: .error,
            message: message,
            range: TextRange(
                start: TextSize(UInt32(baseByteOffset + source[source.startIndex..<index].utf8.count)),
                length: TextSize(UInt32(length))
            )
        ))
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

private struct BlockIDSuffixInfo {
    var contentText: String
    var separatorText: String
    var idText: String
    var trailingWhitespaceText: String
}

private struct WikiEmbedBlockInfo {
    var indentText: String
    var bodyStart: String.Index
    var bodyText: String
    var trailingWhitespaceText: String
    var isComplete: Bool
}

private struct StructuredEmbedBlockInfo {
    var indentText: String
    var bodyStart: String.Index
    var bodyText: String
    var trailingWhitespaceText: String
}

private struct ValueDeclarationInfo {
    var indentText: String
    var constructorStart: String.Index
    var constructorText: String
    var trailingWhitespaceText: String
    var newlineText: String
    var endLineIndex: Int
}

private struct TypedBlockInfo {
    var indentText: String
    var colonRunText: String
    var qnameText: String
    var suffixStart: String.Index
    var suffixText: String
    var trailingWhitespaceText: String
    var closeLineIndex: Int?
}

private struct RawReservedBlockInfo {
    var kind: LiminalKind
    var header: TypedBlockInfo
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

    static func split(_ source: String, baseByteOffset: Int = 0) -> [SourceLine] {
        var result: [SourceLine] = []
        var index = source.startIndex
        var byteOffset = baseByteOffset

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

private struct LiminalStructuredScanner {
    let source: String

    func qnameEnd(from start: String.Index) -> String.Index? {
        var cursor = start
        guard parseIdentEnd(from: cursor).map({ cursor = $0 }) != nil else {
            return nil
        }

        while cursor < source.endIndex, source[cursor] == "." {
            let afterDot = source.index(after: cursor)
            guard let partEnd = parseIdentEnd(from: afterDot) else {
                break
            }
            cursor = partEnd
        }

        return cursor
    }

    func typedConstructorEnd(from start: String.Index) -> String.Index? {
        guard start < source.endIndex, source[start] == "@" else {
            return nil
        }
        var cursor = source.index(after: start)
        guard let nameEnd = qnameEnd(from: cursor) else {
            return nil
        }
        cursor = nameEnd

        if cursor < source.endIndex, source[cursor] == "#" {
            guard let anchorEnd = anchorEnd(from: source.index(after: cursor)) else {
                return nil
            }
            cursor = anchorEnd
        }

        if cursor < source.endIndex, source[cursor] == "{" {
            guard let fieldsEnd = balancedEnd(open: "{", close: "}", from: cursor) else {
                return source.endIndex
            }
            cursor = fieldsEnd
        }

        if cursor < source.endIndex, source[cursor] == "[" {
            guard let inlineEnd = balancedEnd(open: "[", close: "]", from: cursor) else {
                return source.endIndex
            }
            cursor = inlineEnd
        }

        return cursor
    }

    func structuredEmbedEnd(from start: String.Index) -> String.Index? {
        guard source[start..<source.endIndex].hasPrefix("!{") else {
            return nil
        }

        var cursor = source.index(start, offsetBy: 2)
        guard let nameEnd = qnameEnd(from: cursor) else {
            return nil
        }
        cursor = nameEnd
        guard cursor < source.endIndex, source[cursor] == "}" else {
            return nil
        }
        cursor = source.index(after: cursor)

        if cursor < source.endIndex, source[cursor] == "[" {
            guard let fallbackEnd = balancedEnd(open: "[", close: "]", from: cursor) else {
                return source.endIndex
            }
            cursor = fallbackEnd
        }

        guard cursor < source.endIndex, source[cursor] == "(" else {
            return nil
        }
        return balancedEnd(open: "(", close: ")", from: cursor) ?? source.endIndex
    }

    private func parseIdentEnd(from start: String.Index) -> String.Index? {
        guard start < source.endIndex, source[start].isIdentifierStart else {
            return nil
        }

        var cursor = source.index(after: start)
        while cursor < source.endIndex, source[cursor].isIdentifierContinue {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private func anchorEnd(from start: String.Index) -> String.Index? {
        guard start < source.endIndex, source[start].isAnchorCharacter else {
            return nil
        }

        var cursor = source.index(after: start)
        while cursor < source.endIndex, source[cursor].isAnchorCharacter {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private func balancedEnd(
        open: Character,
        close: Character,
        from openIndex: String.Index
    ) -> String.Index? {
        var cursor = openIndex
        var depth = 0
        var inString = false

        while cursor < source.endIndex {
            let character = source[cursor]
            if inString {
                if character == "\\", source.index(after: cursor) < source.endIndex {
                    cursor = source.index(after: source.index(after: cursor))
                    continue
                }
                if character == "\"" {
                    inString = false
                }
                cursor = source.index(after: cursor)
                continue
            }

            if character == "\"" {
                inString = true
            } else if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return source.index(after: cursor)
                }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }
}

private struct LiminalStructuredCSTParser {
    private let source: String
    private let baseByteOffset: Int
    private var index: String.Index

    var diagnostics: [LiminalDiagnostic] = []

    init(source: String, baseByteOffset: Int) {
        self.source = source
        self.baseByteOffset = baseByteOffset
        self.index = source.startIndex
    }

    mutating func emitTypedConstructor(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.typedConstructor)
        try emitStatic(.atSign, expected: "@", with: &builder)
        try emitQName(with: &builder)
        try emitConstructorSuffix(with: &builder)
        if index < source.endIndex, source[index] == "[" {
            try emitInlineBody(with: &builder)
        }
        try emitUnexpectedRemainder(with: &builder)
        try builder.finishNode()
    }

    mutating func emitConstructorSuffix(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        if index < source.endIndex, source[index] == "#" {
            try emitStatic(.hash, expected: "#", with: &builder)
            try emitAnchor(with: &builder)
        }
        if index < source.endIndex, source[index] == "{" {
            try emitFields(with: &builder)
        }
    }

    mutating func emitStructuredEmbed(
        kind: LiminalKind,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(kind)
        try emitStructuredEmbedBody(with: &builder)
        try builder.finishNode()
    }

    mutating func emitStructuredEmbedBody(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitStatic(.bang, expected: "!", with: &builder)
        try emitStatic(.leftBrace, expected: "{", with: &builder)
        try emitQName(with: &builder)
        if index < source.endIndex, source[index] == "}" {
            try emitStatic(.rightBrace, expected: "}", with: &builder)
        } else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing structured embed type delimiter", at: index, length: 0)
        }

        if index < source.endIndex, source[index] == "[" {
            try emitInlineLabelNode(kind: .linkLabel, with: &builder)
        }

        builder.startNode(.embedTarget)
        if index < source.endIndex, source[index] == "(" {
            let targetStart = source.index(after: index)
            try emitStatic(.leftParen, expected: "(", with: &builder)
            if let close = findBalancedClose(open: "(", close: ")", from: source.index(before: targetStart)) {
                let targetText = String(source[targetStart..<close])
                if !targetText.isEmpty {
                    try builder.token(.embedTargetText, text: targetText)
                }
                index = close
                try emitStatic(.rightParen, expected: ")", with: &builder)
            } else {
                let targetText = String(source[targetStart..<source.endIndex])
                if !targetText.isEmpty {
                    try builder.token(.embedTargetText, text: targetText)
                }
                try builder.missingNode(.missing)
                appendDiagnostic("missing closing structured embed target", at: index, length: 1)
                index = source.endIndex
            }
        } else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing structured embed target", at: index, length: 0)
        }
        try builder.finishNode()
        try emitUnexpectedRemainder(with: &builder)
    }

    mutating func emitValue(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.value)
        try emitValuePayload(with: &builder)
        try builder.finishNode()
    }

    private mutating func emitValuePayload(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard index < source.endIndex else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing value", at: index, length: 0)
            return
        }

        if source[index..<source.endIndex].hasPrefix("@[") {
            try emitInlineLiteral(with: &builder)
        } else if source[index..<source.endIndex].hasPrefix("@{") {
            try emitBlockLiteral(with: &builder)
        } else if source[index] == "@" {
            try emitTypedConstructor(with: &builder)
        } else if source[index] == "&" {
            try emitReference(with: &builder)
        } else if source[index..<source.endIndex].hasPrefix("!{") {
            try emitStructuredEmbed(kind: .structuredEmbedValue, with: &builder)
        } else if source[index] == "[" {
            try emitListValue(with: &builder)
        } else if source[index] == "{" {
            try emitRecordValue(with: &builder)
        } else {
            try emitScalarValue(with: &builder)
        }
    }

    private mutating func emitFields(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.fields)
        try emitStatic(.leftBrace, expected: "{", with: &builder)

        while index < source.endIndex {
            try emitTrivia(with: &builder)
            guard index < source.endIndex else {
                break
            }

            if source[index] == "}" {
                try emitStatic(.rightBrace, expected: "}", with: &builder)
                try builder.finishNode()
                return
            }
            if source[index] == "," {
                try emitStatic(.comma, expected: ",", with: &builder)
                continue
            }

            if source[index].isIdentifierStart {
                try emitField(with: &builder)
            } else {
                try emitErrorRun(message: "expected field", with: &builder)
            }
        }

        try builder.missingNode(.missing)
        appendDiagnostic("missing closing fields delimiter", at: index, length: 0)
        try builder.finishNode()
    }

    private mutating func emitField(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.field)
        try emitFieldName(with: &builder)
        try emitTrivia(with: &builder)
        if index < source.endIndex, source[index] == ":" {
            try emitStatic(.colon, expected: ":", with: &builder)
        } else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing field colon", at: index, length: 0)
        }
        try emitTrivia(with: &builder)
        if isValueStart(at: index) {
            try emitValue(with: &builder)
        } else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing field value", at: index, length: 0)
        }
        try builder.finishNode()
    }

    private mutating func emitListValue(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.listValue)
        try emitStatic(.leftBracket, expected: "[", with: &builder)

        while index < source.endIndex {
            try emitTrivia(with: &builder)
            guard index < source.endIndex else {
                break
            }

            if source[index] == "]" {
                try emitStatic(.rightBracket, expected: "]", with: &builder)
                try builder.finishNode()
                return
            }
            if source[index] == "," {
                try emitStatic(.comma, expected: ",", with: &builder)
                continue
            }

            if isValueStart(at: index) {
                try emitValue(with: &builder)
            } else {
                try emitErrorRun(message: "expected list value", with: &builder)
            }
        }

        try builder.missingNode(.missing)
        appendDiagnostic("missing closing list delimiter", at: index, length: 0)
        try builder.finishNode()
    }

    private mutating func emitRecordValue(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.recordValue)
        try emitFields(with: &builder)
        try builder.finishNode()
    }

    private mutating func emitInlineLiteral(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.inlineLiteral)
        try emitStatic(.atSign, expected: "@", with: &builder)
        try emitInlineLabelBody(with: &builder)
        try builder.finishNode()
    }

    private mutating func emitBlockLiteral(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.blockLiteral)
        let openerIndex = index
        let openerIndentText = lineIndentationText(before: openerIndex)
        try emitStatic(.atSign, expected: "@", with: &builder)
        try emitStatic(.leftBrace, expected: "{", with: &builder)

        if let newlineEnd = newlineEnd(at: index) {
            try builder.token(.newline, text: String(source[index..<newlineEnd]))
            index = newlineEnd
            let bodyStart = index
            if let closeLine = blockLiteralCloseLine(
                startingAt: bodyStart,
                openerIndentText: openerIndentText
            ) {
                let bodyText = String(source[bodyStart..<closeLine.contentStart])
                try emitNestedDocumentItems(bodyText, baseByteOffset: globalByteOffset(of: bodyStart), with: &builder)
                try emitWhitespace(String(source[closeLine.contentStart..<closeLine.rightBraceIndex]), with: &builder)
                index = closeLine.rightBraceIndex
                try emitStatic(.rightBrace, expected: "}", with: &builder)
                try emitWhitespace(String(source[index..<closeLine.contentEnd]), with: &builder)
                index = closeLine.contentEnd
            } else {
                let bodyText = String(source[bodyStart..<source.endIndex])
                try emitNestedDocumentItems(bodyText, baseByteOffset: globalByteOffset(of: bodyStart), with: &builder)
                try builder.missingNode(.missing)
                appendDiagnostic("missing closing block literal delimiter", at: index, length: 0)
                index = source.endIndex
            }
        } else if let close = findUnescaped("}", from: index) {
            let bodyText = String(source[index..<close])
            try emitNestedDocumentItems(bodyText, baseByteOffset: globalByteOffset(of: index), with: &builder)
            index = close
            try emitStatic(.rightBrace, expected: "}", with: &builder)
        } else {
            let bodyText = String(source[index..<source.endIndex])
            try emitNestedDocumentItems(bodyText, baseByteOffset: globalByteOffset(of: index), with: &builder)
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing block literal delimiter", at: index, length: 0)
            index = source.endIndex
        }

        try builder.finishNode()
    }

    private mutating func emitReference(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.reference)
        try emitStatic(.ampersand, expected: "&", with: &builder)
        if index < source.endIndex, source[index] == "<" {
            try emitStatic(.lessThan, expected: "<", with: &builder)
            let targetStart = index
            if let close = findUnescaped(">", from: index) {
                if targetStart < close {
                    try builder.token(.externalReferenceText, text: String(source[targetStart..<close]))
                }
                try emitStatic(.greaterThan, expected: ">", with: &builder)
            } else {
                if targetStart < source.endIndex {
                    try builder.token(.externalReferenceText, text: String(source[targetStart..<source.endIndex]))
                }
                try builder.missingNode(.missing)
                appendDiagnostic("missing closing external reference delimiter", at: index, length: 0)
                index = source.endIndex
            }
        } else {
            try emitQName(with: &builder)
        }
        try builder.finishNode()
    }

    private mutating func emitScalarValue(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.scalarValue)
        if source[index] == "\"" {
            let start = index
            index = source.index(after: index)
            while index < source.endIndex {
                if source[index] == "\\", source.index(after: index) < source.endIndex {
                    index = source.index(after: source.index(after: index))
                } else if source[index] == "\"" {
                    index = source.index(after: index)
                    try builder.token(.quotedStringLiteral, text: String(source[start..<index]))
                    try builder.finishNode()
                    return
                } else if source[index].isNewlineStart {
                    break
                } else {
                    index = source.index(after: index)
                }
            }
            try builder.token(.quotedStringLiteral, text: String(source[start..<index]))
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing string delimiter", at: start, length: 1)
        } else {
            let start = index
            while index < source.endIndex, !source[index].isScalarTerminator {
                index = source.index(after: index)
            }
            let text = String(source[start..<index])
            try builder.token(scalarTokenKind(for: text), text: text)
        }
        try builder.finishNode()
    }

    private mutating func emitInlineBody(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try emitInlineLabelBody(with: &builder)
    }

    private mutating func emitInlineLabelNode(
        kind: LiminalKind,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(kind)
        try emitInlineLabelBody(with: &builder)
        try builder.finishNode()
    }

    private mutating func emitInlineLabelBody(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let open = index
        try emitStatic(.leftBracket, expected: "[", with: &builder)
        let contentStart = index
        if let close = findBalancedClose(open: "[", close: "]", from: open) {
            try emitNestedInlineContent(
                String(source[contentStart..<close]),
                baseByteOffset: globalByteOffset(of: contentStart),
                with: &builder
            )
            index = close
            try emitStatic(.rightBracket, expected: "]", with: &builder)
        } else {
            try emitNestedInlineContent(
                String(source[contentStart..<source.endIndex]),
                baseByteOffset: globalByteOffset(of: contentStart),
                with: &builder
            )
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing inline content delimiter", at: open, length: 1)
            index = source.endIndex
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

    private mutating func emitNestedDocumentItems(
        _ bodyText: String,
        baseByteOffset: Int,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !bodyText.isEmpty else {
            return
        }
        var nestedParser = LiminalCSTParser(
            source: bodyText,
            baseByteOffset: baseByteOffset
        )
        try nestedParser.parseDocumentItems(with: &builder)
        diagnostics.append(contentsOf: nestedParser.diagnostics)
    }

    private mutating func emitQName(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard let end = LiminalStructuredScanner(source: source).qnameEnd(from: index) else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing qualified name", at: index, length: 0)
            return
        }
        try builder.token(.qname, text: String(source[index..<end]))
        index = end
    }

    private mutating func emitFieldName(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let start = index
        guard start < source.endIndex, source[start].isIdentifierStart else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing field name", at: index, length: 0)
            return
        }
        index = source.index(after: index)
        while index < source.endIndex, source[index].isIdentifierContinue {
            index = source.index(after: index)
        }
        try builder.token(.fieldName, text: String(source[start..<index]))
    }

    private mutating func emitAnchor(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let start = index
        guard start < source.endIndex, source[start].isAnchorCharacter else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing anchor", at: index, length: 0)
            return
        }
        index = source.index(after: index)
        while index < source.endIndex, source[index].isAnchorCharacter {
            index = source.index(after: index)
        }
        try builder.token(.anchor, text: String(source[start..<index]))
    }

    private mutating func emitTrivia(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        while index < source.endIndex {
            if source[index].isHorizontalWhitespace {
                let start = index
                repeat {
                    index = source.index(after: index)
                } while index < source.endIndex && source[index].isHorizontalWhitespace
                try builder.token(.whitespace, text: String(source[start..<index]))
            } else if let newlineEnd = newlineEnd(at: index) {
                try builder.token(.newline, text: String(source[index..<newlineEnd]))
                index = newlineEnd
            } else {
                return
            }
        }
    }

    private mutating func emitWhitespace(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.whitespace, text: text)
    }

    private mutating func emitStatic(
        _ kind: LiminalKind,
        expected: Character,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard index < source.endIndex, source[index] == expected else {
            try builder.missingNode(.missing)
            appendDiagnostic("missing '\(expected)'", at: index, length: 0)
            return
        }
        try builder.staticToken(kind)
        index = source.index(after: index)
    }

    private mutating func emitErrorRun(
        message: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let start = index
        while index < source.endIndex,
              source[index] != ",",
              source[index] != "}",
              source[index] != "]",
              !source[index].isNewlineStart
        {
            index = source.index(after: index)
        }

        builder.startNode(.error)
        if start < index {
            try builder.largeToken(.errorText, text: String(source[start..<index]))
        }
        try builder.finishNode()
        appendDiagnostic(message, at: start, length: source[start..<index].utf8.count)
    }

    private mutating func emitUnexpectedRemainder(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard index < source.endIndex else {
            return
        }
        try emitErrorRun(message: "unexpected structured syntax", with: &builder)
    }

    private func isValueStart(at cursor: String.Index) -> Bool {
        guard cursor < source.endIndex else {
            return false
        }
        return source[cursor] == "\""
            || source[cursor] == "@"
            || source[cursor] == "&"
            || source[cursor] == "!"
            || source[cursor] == "["
            || source[cursor] == "{"
            || !source[cursor].isScalarTerminator
    }

    private func scalarTokenKind(for text: String) -> LiminalKind {
        if text == "true" || text == "false" {
            return .booleanLiteral
        }
        if text == "null" {
            return .nullLiteral
        }
        if text.isIntegerLiteralText {
            return .integerLiteral
        }
        if text.isNumberLiteralText {
            return .numberLiteral
        }
        return .bareScalarLiteral
    }

    private func findBalancedClose(
        open: Character,
        close: Character,
        from openIndex: String.Index
    ) -> String.Index? {
        var cursor = openIndex
        var depth = 0
        while cursor < source.endIndex {
            if source.isEscaped(cursor) {
                cursor = source.index(after: cursor)
            } else if source[cursor] == open {
                depth += 1
            } else if source[cursor] == close {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func findUnescaped(
        _ character: Character,
        from start: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == character, !source.isEscaped(cursor) {
                return cursor
            }
            if source[cursor].isNewlineStart {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func blockLiteralCloseLine(
        startingAt bodyStart: String.Index,
        openerIndentText: String
    ) -> BlockLiteralCloseLine? {
        let bodyLines = SourceLine.split(source, baseByteOffset: baseByteOffset)
        for line in bodyLines where line.contentStart >= bodyStart {
            let content = line.content
            var cursor = content.startIndex
            while cursor < content.endIndex, content[cursor].isHorizontalWhitespace {
                cursor = content.index(after: cursor)
            }
            guard cursor < content.endIndex, content[cursor] == "}" else {
                continue
            }
            guard String(content[content.startIndex..<cursor]) == openerIndentText else {
                continue
            }
            let afterBrace = content.index(after: cursor)
            if content[afterBrace..<content.endIndex].allSatisfy(\.isHorizontalWhitespace) {
                return BlockLiteralCloseLine(
                    contentStart: content.startIndex,
                    contentEnd: content.endIndex,
                    rightBraceIndex: cursor
                )
            }
        }
        return nil
    }

    private func lineIndentationText(before target: String.Index) -> String {
        var lineStart = target
        while lineStart > source.startIndex {
            let previous = source.index(before: lineStart)
            if source[previous].isNewlineStart {
                break
            }
            lineStart = previous
        }

        var cursor = lineStart
        while cursor < target, source[cursor].isHorizontalWhitespace {
            cursor = source.index(after: cursor)
        }
        return String(source[lineStart..<cursor])
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

private struct BlockLiteralCloseLine {
    var contentStart: String.Index
    var contentEnd: String.Index
    var rightBraceIndex: String.Index
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
            } else if source[index] == "\\", canParseEscapedPunctuation() {
                try flushText(upTo: index, with: &builder)
                try emitEscapedPunctuation(with: &builder)
            } else if source[index..<source.endIndex].hasPrefix("!{"),
                      canParseStructuredEmbed()
            {
                try flushText(upTo: index, with: &builder)
                try emitStructuredEmbed(with: &builder)
            } else if source[index] == "@", canParseTypedInline() {
                try flushText(upTo: index, with: &builder)
                try emitTypedInline(with: &builder)
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

    private mutating func emitEscapedPunctuation(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let punctuationIndex = source.index(after: index)
        let punctuation = source[punctuationIndex]

        builder.startNode(.escapedPunctuation)
        try builder.staticToken(.backslash)
        if let kind = staticPunctuationKind(for: punctuation) {
            try builder.staticToken(kind)
        } else {
            try builder.token(.inlineText, text: String(punctuation))
        }
        try builder.finishNode()

        index = source.index(after: punctuationIndex)
        textStart = index
    }

    private mutating func emitTypedInline(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let start = index
        let end = LiminalStructuredScanner(source: source).typedConstructorEnd(from: start)
            ?? inlineBoundary(from: start)
        builder.startNode(.typedInline)
        var parser = LiminalStructuredCSTParser(
            source: String(source[start..<end]),
            baseByteOffset: globalByteOffset(of: start)
        )
        try parser.emitTypedConstructor(with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
        try builder.finishNode()
        index = end
        textStart = index
    }

    private mutating func emitStructuredEmbed(
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let start = index
        let end = LiminalStructuredScanner(source: source).structuredEmbedEnd(from: start)
            ?? inlineBoundary(from: start)
        var parser = LiminalStructuredCSTParser(
            source: String(source[start..<end]),
            baseByteOffset: globalByteOffset(of: start)
        )
        try parser.emitStructuredEmbed(kind: .structuredEmbed, with: &builder)
        diagnostics.append(contentsOf: parser.diagnostics)
        index = end
        textStart = index
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
            try emitLinkDestinationContent(source[destinationStart..<closeParen], with: &builder)
            try builder.staticToken(.rightParen)
            index = source.index(after: closeParen)
        } else {
            try emitLinkDestinationContent(source[destinationStart..<source.endIndex], with: &builder)
            try builder.missingNode(.missing)
            appendDiagnostic("missing closing link destination", at: openParen, length: 1)
            index = source.endIndex
        }

        try builder.finishNode()
    }

    private mutating func emitLinkDestinationContent(
        _ content: Substring,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        let split = splitLinkDestinationContent(content)

        try emitWhitespace(String(content[content.startIndex..<split.destinationStart]), with: &builder)
        try emitLinkDestinationText(String(content[split.destinationStart..<split.destinationEnd]), with: &builder)

        if let title = split.title {
            try emitWhitespace(String(content[split.destinationEnd..<title.openQuote]), with: &builder)
            builder.startNode(.linkTitle)
            try builder.staticToken(title.quote == "\"" ? .doubleQuote : .singleQuote)
            if title.textStart < title.textEnd {
                try builder.token(.linkTitleText, text: String(content[title.textStart..<title.textEnd]))
            }
            try builder.staticToken(title.quote == "\"" ? .doubleQuote : .singleQuote)
            try builder.finishNode()
            try emitWhitespace(String(content[title.closeQuoteEnd..<content.endIndex]), with: &builder)
        } else {
            try emitWhitespace(String(content[split.destinationEnd..<content.endIndex]), with: &builder)
        }
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

    private func canParseEscapedPunctuation() -> Bool {
        let next = source.index(after: index)
        guard next < source.endIndex else {
            return false
        }
        return staticPunctuationKind(for: source[next]) != nil
    }

    private func canParseTypedInline() -> Bool {
        guard !source[index..<source.endIndex].hasPrefix("@["),
              !source[index..<source.endIndex].hasPrefix("@{")
        else {
            return false
        }
        return LiminalStructuredScanner(source: source).typedConstructorEnd(from: index) != nil
    }

    private func canParseStructuredEmbed() -> Bool {
        let typeStart = source.index(index, offsetBy: 2)
        return LiminalStructuredScanner(source: source).qnameEnd(from: typeStart) != nil
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

    private mutating func emitWhitespace(
        _ text: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        guard !text.isEmpty else { return }
        try builder.token(.whitespace, text: text)
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

    private func splitLinkDestinationContent(_ content: Substring) -> LinkDestinationSplit {
        var destinationStart = content.startIndex
        while destinationStart < content.endIndex, content[destinationStart].isHorizontalWhitespace {
            destinationStart = content.index(after: destinationStart)
        }

        var destinationEnd = content.endIndex
        while destinationEnd > destinationStart {
            let previous = content.index(before: destinationEnd)
            guard content[previous].isHorizontalWhitespace else {
                break
            }
            destinationEnd = previous
        }

        guard destinationStart < destinationEnd else {
            return LinkDestinationSplit(
                destinationStart: destinationStart,
                destinationEnd: destinationEnd,
                title: nil
            )
        }

        let closeQuote = content.index(before: destinationEnd)
        let quote = content[closeQuote]
        guard quote == "\"" || quote == "'" else {
            return LinkDestinationSplit(
                destinationStart: destinationStart,
                destinationEnd: destinationEnd,
                title: nil
            )
        }

        var openQuote = closeQuote
        while openQuote > destinationStart {
            openQuote = content.index(before: openQuote)
            if content[openQuote] == quote, !content.isEscaped(openQuote) {
                break
            }
        }

        guard openQuote < closeQuote,
              content[openQuote] == quote,
              openQuote > destinationStart
        else {
            return LinkDestinationSplit(
                destinationStart: destinationStart,
                destinationEnd: destinationEnd,
                title: nil
            )
        }

        let beforeOpenQuote = content.index(before: openQuote)
        guard content[beforeOpenQuote].isHorizontalWhitespace else {
            return LinkDestinationSplit(
                destinationStart: destinationStart,
                destinationEnd: destinationEnd,
                title: nil
            )
        }

        var titleSeparatorStart = openQuote
        while titleSeparatorStart > destinationStart {
            let previous = content.index(before: titleSeparatorStart)
            guard content[previous].isHorizontalWhitespace else {
                break
            }
            titleSeparatorStart = previous
        }

        guard destinationStart < titleSeparatorStart else {
            return LinkDestinationSplit(
                destinationStart: destinationStart,
                destinationEnd: destinationEnd,
                title: nil
            )
        }

        return LinkDestinationSplit(
            destinationStart: destinationStart,
            destinationEnd: titleSeparatorStart,
            title: LinkTitleSplit(
                quote: quote,
                openQuote: openQuote,
                textStart: content.index(after: openQuote),
                textEnd: closeQuote,
                closeQuoteEnd: content.index(after: closeQuote)
            )
        )
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

private struct LinkDestinationSplit {
    var destinationStart: String.Index
    var destinationEnd: String.Index
    var title: LinkTitleSplit?
}

private struct LinkTitleSplit {
    var quote: Character
    var openQuote: String.Index
    var textStart: String.Index
    var textEnd: String.Index
    var closeQuoteEnd: String.Index
}

private func staticPunctuationKind(for character: Character) -> LiminalKind? {
    switch character {
    case "@": .atSign
    case "!": .bang
    case "&": .ampersand
    case "#": .hash
    case "^": .caret
    case "$": .dollar
    case "[": .leftBracket
    case "]": .rightBracket
    case "(": .leftParen
    case ")": .rightParen
    case "{": .leftBrace
    case "}": .rightBrace
    case "<": .lessThan
    case ">": .greaterThan
    case ",": .comma
    case ":": .colon
    case "|": .pipe
    case "`": .backtick
    case "~": .tilde
    case "*": .star
    case "_": .underscore
    case "-": .dash
    case "+": .plus
    case ".": .dot
    case "/": .slash
    case "\\": .backslash
    case "%": .percent
    case "=": .equals
    case "?": .questionMark
    case "'": .singleQuote
    case "\"": .doubleQuote
    case ";": .semicolon
    default: nil
    }
}

private extension Character {
    var isHorizontalWhitespace: Bool {
        self == " " || self == "\t"
    }

    var isNewlineStart: Bool {
        self == "\n" || self == "\r"
    }

    var isIdentifierStart: Bool {
        self == "_" || isASCIILetter
    }

    var isIdentifierContinue: Bool {
        isIdentifierStart || isASCIIDigit || self == "-"
    }

    var isAnchorCharacter: Bool {
        isASCIILetter || isASCIIDigit || self == "_" || self == "-"
    }

    var isAnchorStartCharacter: Bool {
        isASCIILetter || isASCIIDigit
    }

    var isScalarTerminator: Bool {
        isHorizontalWhitespace
            || isNewlineStart
            || self == ","
            || self == "]"
            || self == "}"
            || self == ")"
    }

    private var isASCIILetter: Bool {
        guard let value = asciiValue else {
            return false
        }
        return (65...90).contains(Int(value)) || (97...122).contains(Int(value))
    }

    private var isASCIIDigit: Bool {
        guard let value = asciiValue else {
            return false
        }
        return (48...57).contains(Int(value))
    }

    private var asciiValue: UInt32? {
        let scalars = String(self).unicodeScalars
        guard scalars.count == 1, let value = scalars.first?.value, value < 128 else {
            return nil
        }
        return value
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

private extension String {
    var isIntegerLiteralText: Bool {
        var cursor = startIndex
        if cursor < endIndex, self[cursor] == "-" {
            cursor = index(after: cursor)
        }
        guard cursor < endIndex else {
            return false
        }
        while cursor < endIndex {
            guard self[cursor].isDigitForLiteral else {
                return false
            }
            cursor = index(after: cursor)
        }
        return true
    }

    var isNumberLiteralText: Bool {
        var cursor = startIndex
        if cursor < endIndex, self[cursor] == "-" {
            cursor = index(after: cursor)
        }

        var sawIntegerDigit = false
        while cursor < endIndex, self[cursor].isDigitForLiteral {
            sawIntegerDigit = true
            cursor = index(after: cursor)
        }

        guard sawIntegerDigit, cursor < endIndex, self[cursor] == "." else {
            return false
        }
        cursor = index(after: cursor)

        var sawFractionDigit = false
        while cursor < endIndex, self[cursor].isDigitForLiteral {
            sawFractionDigit = true
            cursor = index(after: cursor)
        }

        return sawFractionDigit && cursor == endIndex
    }
}

private extension Character {
    var isDigitForLiteral: Bool {
        let scalars = String(self).unicodeScalars
        guard scalars.count == 1, let value = scalars.first?.value else {
            return false
        }
        return (48...57).contains(Int(value))
    }
}
