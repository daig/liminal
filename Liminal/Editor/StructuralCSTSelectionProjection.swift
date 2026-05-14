import CambiumBuilder
import CambiumCore
import CambiumSelection
import Foundation

struct StructuralCSTSelectionCapture {
    let fragment: StructuralCSTFragment
    let projection: StructuralCSTSourceProjection

    var logicalText: String {
        projection.logicalText(from: fragment.sourceText)
    }

    var relativeHighlightRanges: [CambiumCore.TextRange] {
        projection.relativeHighlightRanges(sourceByteCount: fragment.sourceText.utf8.count)
    }

    var clipboardPayload: StructuralCSTClipboardPayload {
        StructuralCSTClipboardPayload(fragment: fragment, projection: projection)
    }

    static func capture(
        forest: LiminalForest,
        source: String
    ) throws -> StructuralCSTSelectionCapture {
        let fragment = try StructuralCSTFragment.capture(forest)
        return StructuralCSTSelectionCapture(
            fragment: fragment,
            projection: StructuralCSTSourceProjection(
                forest: forest,
                fragment: fragment,
                source: source
            )
        )
    }
}

struct StructuralCSTClipboardPayload {
    let fragment: StructuralCSTFragment
    let projection: StructuralCSTSourceProjection

    var logicalText: String {
        projection.logicalText(from: fragment.sourceText)
    }

    func serializedData() throws -> Data {
        let wire = WirePayload(
            version: Self.currentVersion,
            fragmentData: try fragment.serializedData(),
            projection: projection.wireProjection
        )
        return try JSONEncoder().encode(wire)
    }

    static func decode(data: Data) throws -> StructuralCSTClipboardPayload {
        let wire = try JSONDecoder().decode(WirePayload.self, from: data)
        guard wire.version == currentVersion else {
            throw DecodeError.unsupportedVersion(wire.version)
        }
        return StructuralCSTClipboardPayload(
            fragment: try StructuralCSTFragment.decode(data: wire.fragmentData),
            projection: try StructuralCSTSourceProjection(wire: wire.projection)
        )
    }

    private static let currentVersion = 1

    private struct WirePayload: Codable {
        var version: Int
        var fragmentData: Data
        var projection: StructuralCSTSourceProjection.WireProjection
    }

    enum DecodeError: Error, Equatable {
        case unsupportedVersion(Int)
    }
}

struct StructuralCSTSourceProjection: Equatable {
    enum Kind: String, Codable, Equatable {
        case identity
        case listItems
        case listItemContent
        case blockQuoteContent
    }

    struct WireProjection: Codable, Equatable {
        var kind: Kind
        var removals: [WireRange]
    }

    struct WireRange: Codable, Equatable {
        var start: UInt32
        var length: UInt32
    }

    let kind: Kind
    let removalRanges: [CambiumCore.TextRange]

    init(fragment: StructuralCSTFragment) {
        if let listItems = Self.listItems(for: fragment) {
            self = listItems
        } else if let blockQuote = Self.blockQuoteContent(for: fragment) {
            self = blockQuote
        } else {
            self = Self.identity()
        }
    }

    init(
        forest: LiminalForest,
        fragment: StructuralCSTFragment,
        source: String
    ) {
        if let listItemContent = Self.listItemContent(
            for: forest,
            fragment: fragment,
            source: source
        ) {
            self = listItemContent
        } else {
            self.init(fragment: fragment)
        }
    }

    init(wire: WireProjection) throws {
        self = StructuralCSTSourceProjection(
            kind: wire.kind,
            removalRanges: wire.removals.map {
                CambiumCore.TextRange(
                    start: TextSize($0.start),
                    length: TextSize($0.length)
                )
            }
        )
    }

    var wireProjection: WireProjection {
        WireProjection(
            kind: kind,
            removals: removalRanges.map {
                WireRange(
                    start: $0.start.rawValue,
                    length: $0.length.rawValue
                )
            }
        )
    }

    func logicalText(from source: String) -> String {
        guard !source.isEmpty, !removalRanges.isEmpty else { return source }

        var output = ""
        var cursorByte = 0
        for removal in removalRanges {
            let startByte = Int(removal.start.rawValue)
            let endByte = Int(removal.end.rawValue)
            precondition(cursorByte <= startByte)
            Self.appendBytes(
                source,
                startByte: cursorByte,
                endByte: startByte,
                to: &output
            )
            cursorByte = endByte
        }
        Self.appendBytes(
            source,
            startByte: cursorByte,
            endByte: source.utf8.count,
            to: &output
        )
        return output
    }

    func relativeHighlightRanges(
        sourceByteCount: Int
    ) -> [CambiumCore.TextRange] {
        StructuralCSTListSource.highlightRanges(
            sourceByteCount: sourceByteCount,
            removing: removalRanges
        )
    }

    static func listItems(
        for fragment: StructuralCSTFragment
    ) -> StructuralCSTSourceProjection? {
        guard fragment.wrapperKind == .list,
              !fragment.hasTokenChildren,
              !fragment.childKinds.isEmpty,
              fragment.childKinds.allSatisfy({ $0 == .listItem }),
              StructuralCSTListSource.marker(in: fragment.sourceText) != nil,
              let sourceBaseIndent = StructuralCSTListSource.firstLineIndentColumn(
                  in: fragment.sourceText
              )
        else { return nil }

        return StructuralCSTSourceProjection(
            kind: .listItems,
            removalRanges: StructuralCSTListSource.baseIndentRemovalRanges(
                in: fragment.sourceText,
                sourceBaseIndent: sourceBaseIndent
            )
        )
    }

    static func blockQuoteContent(
        for fragment: StructuralCSTFragment
    ) -> StructuralCSTSourceProjection? {
        guard fragment.wrapperKind == .blockQuote,
              isLiftableBlockQuoteFragment(fragment)
        else { return nil }

        return StructuralCSTSourceProjection(
            kind: .blockQuoteContent,
            removalRanges: blockQuotePrefixRemovalRanges(in: fragment.sourceText)
        )
    }

    private static func listItemContent(
        for forest: LiminalForest,
        fragment: StructuralCSTFragment,
        source: String
    ) -> StructuralCSTSourceProjection? {
        guard forest.parent.withCursor({ $0.kind }) == .listItem else {
            return nil
        }
        let contentColumn = forest.parent.withCursor {
            StructuralCSTListSource.listItemContentColumn(in: $0.makeString())
        }
        guard let contentColumn else { return nil }

        return StructuralCSTSourceProjection(
            kind: .listItemContent,
            removalRanges: StructuralCSTListSource.listItemContentRemovalRanges(
                in: source,
                selectedByteRange: forest.byteRange,
                contentColumn: contentColumn
            )
        )
    }

    private static func identity() -> StructuralCSTSourceProjection {
        StructuralCSTSourceProjection(kind: .identity, removalRanges: [])
    }

    private init(
        kind: Kind,
        removalRanges: [CambiumCore.TextRange]
    ) {
        self.kind = kind
        self.removalRanges = Self.normalizedRemovalRanges(removalRanges)
    }

    private static func normalizedRemovalRanges(
        _ ranges: [CambiumCore.TextRange]
    ) -> [CambiumCore.TextRange] {
        let sorted = ranges
            .filter { $0.length.rawValue > 0 }
            .sorted {
                if $0.start == $1.start {
                    return $0.end.rawValue < $1.end.rawValue
                }
                return $0.start.rawValue < $1.start.rawValue
            }
        guard var current = sorted.first else { return [] }
        var merged: [CambiumCore.TextRange] = []
        for range in sorted.dropFirst() {
            if range.start.rawValue <= current.end.rawValue {
                current = CambiumCore.TextRange(
                    start: current.start,
                    end: TextSize(max(current.end.rawValue, range.end.rawValue))
                )
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    private static func appendBytes(
        _ source: String,
        startByte: Int,
        endByte: Int,
        to output: inout String
    ) {
        guard endByte > startByte else { return }
        precondition(startByte >= 0)
        precondition(endByte <= source.utf8.count)
        let start = source.utf8.index(source.startIndex, offsetBy: startByte)
        let end = source.utf8.index(source.startIndex, offsetBy: endByte)
        output += String(source[start..<end])
    }

    private static func blockQuotePrefixRemovalRanges(
        in source: String
    ) -> [CambiumCore.TextRange] {
        guard !source.isEmpty else { return [] }

        var removals: [CambiumCore.TextRange] = []
        var lineStart = source.startIndex
        var lineStartByte = 0
        var isFirstLine = true

        while lineStart < source.endIndex {
            var lineEnd = lineStart
            while lineEnd < source.endIndex,
                  source[lineEnd] != "\n",
                  source[lineEnd] != "\r"
            {
                lineEnd = source.index(after: lineEnd)
            }

            let contentStart = isFirstLine
                ? lineStart
                : contentStartAfterOneBlockQuotePrefix(
                    in: source,
                    lineStart: lineStart,
                    lineEnd: lineEnd
                )
            if contentStart > lineStart {
                let removalEnd = lineStartByte
                    + source.utf8.distance(from: lineStart, to: contentStart)
                removals.append(CambiumCore.TextRange(
                    start: TextSize(UInt32(lineStartByte)),
                    end: TextSize(UInt32(removalEnd))
                ))
            }
            isFirstLine = false

            var nextLineStart = lineEnd
            if lineEnd < source.endIndex {
                if source[lineEnd] == "\r" {
                    let afterCR = source.index(after: lineEnd)
                    if afterCR < source.endIndex, source[afterCR] == "\n" {
                        nextLineStart = source.index(after: afterCR)
                    } else {
                        nextLineStart = afterCR
                    }
                } else {
                    nextLineStart = source.index(after: lineEnd)
                }
            }

            lineStartByte += source.utf8.distance(
                from: lineStart,
                to: nextLineStart
            )
            lineStart = nextLineStart
        }

        return removals
    }

    private static func isLiftableBlockQuoteFragment(
        _ fragment: StructuralCSTFragment
    ) -> Bool {
        var hasDocumentItem = false
        for index in 0..<fragment.snapshot.root.childCount {
            let kind = fragment.snapshot.root.child(at: index).kind
            if isDocumentItemKind(kind) {
                hasDocumentItem = true
                continue
            }
            guard isBlockQuotePrefixTokenKind(kind) else { return false }
        }
        return hasDocumentItem
    }

    private static func contentStartAfterOneBlockQuotePrefix(
        in source: String,
        lineStart: String.Index,
        lineEnd: String.Index
    ) -> String.Index {
        var cursor = lineStart
        while cursor < lineEnd, isHorizontalWhitespace(source[cursor]) {
            cursor = source.index(after: cursor)
        }
        guard cursor < lineEnd, source[cursor] == ">" else {
            return lineStart
        }

        cursor = source.index(after: cursor)
        if cursor < lineEnd, isHorizontalWhitespace(source[cursor]) {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private static func isBlockQuotePrefixTokenKind(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .whitespace, .greaterThan:
            true
        default:
            false
        }
    }

    private static func isDocumentItemKind(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .blankLine, .frontmatter, .directive, .schemaBlock,
             .templateBlock, .paragraph, .atxHeading, .thematicBreak,
             .valueDeclaration, .typedBlock, .fencedCodeBlock, .mathBlock,
             .htmlBlock, .commentBlock, .list, .blockQuote, .pipeTable,
             .structuredEmbedBlock, .wikiEmbedBlock:
            return true
        default:
            return false
        }
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}
