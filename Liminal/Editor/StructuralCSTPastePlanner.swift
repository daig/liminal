import CambiumBuilder
import CambiumCore
import CambiumIncremental
import CambiumSelection
import Foundation

struct StructuralCSTPastePlan {
    let target: SyntaxNodeHandle<LiminalLanguage>
    let replacement: GreenTreeSnapshot<LiminalLanguage>
    let edit: TextEdit
    let cursorByteOffset: TextSize

    var insertedRange: CambiumCore.TextRange {
        CambiumCore.TextRange(start: edit.range.start, length: edit.replacementLength)
    }
}

enum StructuralCSTPastePlanner {
    static func plan(
        fragment: StructuralCSTFragment,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard !fragment.snapshot.root.containsSentinels,
              !fragment.hasTokenChildren
        else { return nil }

        switch fragment.wrapperKind {
        case .root:
            return try planRootFragment(
                fragment,
                in: tree,
                cursorByteOffset: cursorByteOffset,
                after: after
            )
        case .list:
            return try planListFragment(
                fragment,
                in: tree,
                cursorByteOffset: cursorByteOffset,
                after: after
            )
        default:
            return nil
        }
    }

    // MARK: - Root / document-item adapter

    private static func planRootFragment(
        _ fragment: StructuralCSTFragment,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard !fragment.childKinds.isEmpty,
              fragment.childKinds.allSatisfy(isDocumentItemKind)
        else { return nil }

        let payloadText = fragment.sourceText
        guard !payloadText.isEmpty,
              let firstPayloadKind = fragment.childKinds.first,
              let lastPayloadKind = fragment.childKinds.last
        else { return nil }

        return try planRootInsertion(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after,
            payloadText: payloadText,
            firstPayloadKind: firstPayloadKind,
            lastPayloadKind: lastPayloadKind,
            appendPayload: { builder in
                try appendChildren(of: fragment.snapshot, to: &builder)
            },
            appendPayloadWithTrailingNewline: { builder in
                let terminated = try rootPayloadSnapshot(
                    from: payloadText + "\n",
                    expectedChildKinds: fragment.childKinds
                )
                try appendChildren(of: terminated, to: &builder)
            }
        )
    }

    private static func planRootInsertion(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool,
        payloadText: String,
        firstPayloadKind: LiminalKind,
        lastPayloadKind: LiminalKind,
        appendPayload: (inout GreenTreeBuilder<LiminalLanguage>) throws -> Void,
        appendPayloadWithTrailingNewline: ((inout GreenTreeBuilder<LiminalLanguage>) throws -> Void)? = nil
    ) throws -> StructuralCSTPastePlan? {
        let target = rootInsertionTarget(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after
        )

        let prefixNewlineCount = rootBoundaryNewlineCount(
            left: target.leftKind,
            right: firstPayloadKind,
            leftTrailingLineBreaks: target.leftTrailingLineBreaks,
            rightLeadingLineBreaks: leadingLineBreakCount(in: payloadText)
        )
        let suffixNewlineCount = rootBoundaryNewlineCount(
            left: lastPayloadKind,
            right: target.rightKind,
            leftTrailingLineBreaks: trailingLineBreakCount(in: payloadText),
            rightLeadingLineBreaks: target.rightLeadingLineBreaks
        )
        let leftTerminatorCount = target.leftKind != nil
            && target.leftTrailingLineBreaks == 0
            && prefixNewlineCount > 0
            ? 1
            : 0
        let payloadTerminatorCount = trailingLineBreakCount(in: payloadText) == 0
            && suffixNewlineCount > 0
            && appendPayloadWithTrailingNewline != nil
            ? 1
            : 0
        let prefixBlankLineCount = prefixNewlineCount - leftTerminatorCount
        let suffixBlankLineCount = suffixNewlineCount - payloadTerminatorCount
        let terminatedLeft = try normalizedLeftItem(
            target: target,
            addingTerminator: leftTerminatorCount == 1
        )

        var insertedText = ""
        insertedText += String(repeating: "\n", count: prefixNewlineCount)
        insertedText += payloadText
        insertedText += String(repeating: "\n", count: suffixNewlineCount)
        guard !insertedText.isEmpty else { return nil }

        var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
        builder.startNode(.root)
        try tree.withRoot { root in
            for oldIndex in 0..<target.childIndex {
                if oldIndex == target.childIndex - 1,
                   let terminatedLeft
                {
                    try appendRootNode(of: terminatedLeft, to: &builder)
                    continue
                }
                try root.withChildNode(atRawIndex: oldIndex) { child in
                    _ = try builder.reuseSubtree(child)
                }
            }
            for _ in 0..<prefixBlankLineCount {
                try appendBlankLine(to: &builder)
            }
            if payloadTerminatorCount == 1,
               let appendPayloadWithTrailingNewline
            {
                try appendPayloadWithTrailingNewline(&builder)
            } else {
                try appendPayload(&builder)
            }
            for _ in 0..<suffixBlankLineCount {
                try appendBlankLine(to: &builder)
            }
            for oldIndex in target.childIndex..<root.childOrTokenCount {
                try root.withChildNode(atRawIndex: oldIndex) { child in
                    _ = try builder.reuseSubtree(child)
                }
            }
        }
        try builder.finishNode()
        let build = try builder.finish()
        let insertionRange = CambiumCore.TextRange(start: target.byteOffset, length: .zero)
        return StructuralCSTPastePlan(
            target: target.parent,
            replacement: build.snapshot,
            edit: TextEdit(range: insertionRange, replacement: insertedText),
            cursorByteOffset: cursorOffset(
                insertionStart: target.byteOffset,
                insertedText: insertedText
            )
        )
    }

    // MARK: - List-item adapters

    private static func planListFragment(
        _ fragment: StructuralCSTFragment,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard !fragment.childKinds.isEmpty,
              fragment.childKinds.allSatisfy({ $0 == .listItem }),
              let sourceMarker = listMarker(in: fragment.sourceText),
              let sourceBaseIndent = firstLineIndentColumn(in: fragment.sourceText)
        else { return nil }

        if let target = listInsertionTarget(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after
        ) {
            guard let targetMarker = target.marker,
                  markersAreCompatible(sourceMarker, targetMarker)
            else { return nil }

            let payload = try listPayloadSnapshot(
                from: fragment,
                sourceBaseIndent: sourceBaseIndent,
                targetBaseIndent: target.baseIndent,
                topLevelMarker: normalizedMarker(
                    sourceMarker: sourceMarker,
                    targetMarker: targetMarker
                ),
                ensureTrailingNewline: target.hasRightSibling
            )
            let payloadText = payload.root.makeString(using: payload.resolver)
            guard !payloadText.isEmpty else { return nil }

            var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
            builder.startNode(.list)
            try target.parent.withCursor { list in
                for oldIndex in 0..<target.childIndex {
                    try list.withChildNode(atRawIndex: oldIndex) { child in
                        _ = try builder.reuseSubtree(child)
                    }
                }
                try appendChildren(of: payload, to: &builder)
                for oldIndex in target.childIndex..<list.childOrTokenCount {
                    try list.withChildNode(atRawIndex: oldIndex) { child in
                        _ = try builder.reuseSubtree(child)
                    }
                }
            }
            try builder.finishNode()
            let build = try builder.finish()
            let insertionRange = CambiumCore.TextRange(start: target.byteOffset, length: .zero)
            return StructuralCSTPastePlan(
                target: target.parent,
                replacement: build.snapshot,
                edit: TextEdit(range: insertionRange, replacement: payloadText),
                cursorByteOffset: cursorOffset(
                    insertionStart: target.byteOffset,
                    insertedText: payloadText
                )
            )
        }

        let payload = try listPayloadSnapshot(
            from: fragment,
            sourceBaseIndent: sourceBaseIndent,
            targetBaseIndent: 0,
            topLevelMarker: nil,
            ensureTrailingNewline: false
        )
        let payloadText = payload.root.makeString(using: payload.resolver)
        guard !payloadText.isEmpty else { return nil }

        return try planRootInsertion(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after,
            payloadText: payloadText,
            firstPayloadKind: .list,
            lastPayloadKind: .list,
            appendPayload: { builder in
                try payload.makeSyntaxTree().withRoot { list in
                    _ = try builder.reuseSubtree(list)
                }
            },
            appendPayloadWithTrailingNewline: { builder in
                let terminated = try listPayloadSnapshot(
                    from: fragment,
                    sourceBaseIndent: sourceBaseIndent,
                    targetBaseIndent: 0,
                    topLevelMarker: nil,
                    ensureTrailingNewline: true
                )
                try terminated.makeSyntaxTree().withRoot { list in
                    _ = try builder.reuseSubtree(list)
                }
            }
        )
    }

    private static func listPayloadSnapshot(
        from fragment: StructuralCSTFragment,
        sourceBaseIndent: Int,
        targetBaseIndent: Int,
        topLevelMarker: Character?,
        ensureTrailingNewline: Bool
    ) throws -> GreenTreeSnapshot<LiminalLanguage> {
        let needsTrailingNewline = ensureTrailingNewline
            && !endsWithLineBreak(fragment.sourceText)
        if sourceBaseIndent == targetBaseIndent,
           topLevelMarker == nil,
           !needsTrailingNewline
        {
            return fragment.snapshot
        }

        var source = fragment.sourceText
        if needsTrailingNewline {
            source += "\n"
        }
        let shifted = rebaseListSource(
            source,
            sourceBaseIndent: sourceBaseIndent,
            targetBaseIndent: targetBaseIndent,
            topLevelMarker: topLevelMarker
        )
        let parsed = try LiminalParser().parse(shifted)
        return try parsed.tree.withRoot { root -> GreenTreeSnapshot<LiminalLanguage> in
            for index in 0..<root.childOrTokenCount {
                let kind = root.green { $0.child(at: index) }.kind
                guard kind == .list else { continue }
                return try root.withChildNode(atRawIndex: index) { list in
                    let green = list.green { $0 }
                    return GreenTreeSnapshot(root: green, resolver: list.resolver)
                }!
            }
            throw StructuralCSTPasteError.invalidListPayload
        }
    }

    // MARK: - Targets

    private struct RootInsertionTarget {
        let parent: SyntaxNodeHandle<LiminalLanguage>
        let childIndex: Int
        let byteOffset: TextSize
        let leftKind: LiminalKind?
        let rightKind: LiminalKind?
        let leftTrailingLineBreaks: Int
        let rightLeadingLineBreaks: Int
        let leftText: String?
    }

    private static func rootInsertionTarget(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) -> RootInsertionTarget {
        tree.withRoot { root in
            let count = root.childOrTokenCount
            guard count > 0 else {
                return RootInsertionTarget(
                    parent: root.makeHandle(),
                    childIndex: 0,
                    byteOffset: .zero,
                    leftKind: nil,
                    rightKind: nil,
                    leftTrailingLineBreaks: 0,
                    rightLeadingLineBreaks: 0,
                    leftText: nil
                )
            }

            let cursor = min(cursorByteOffset.rawValue, root.textRange.end.rawValue)
            var containingIndex = count - 1
            for index in 0..<count {
                let range = root.childTextRange(at: index)
                if cursor <= range.start.rawValue || cursor < range.end.rawValue {
                    containingIndex = index
                    break
                }
            }

            let childIndex = after ? containingIndex + 1 : containingIndex
            let byteOffset = childIndex < count
                ? root.childTextRange(at: childIndex).start
                : root.textRange.end
            let leftText = childIndex > 0
                ? root.withChildNode(atRawIndex: childIndex - 1) { $0.makeString() }
                : nil
            let rightText = childIndex < count
                ? root.withChildNode(atRawIndex: childIndex) { $0.makeString() }
                : nil
            return RootInsertionTarget(
                parent: root.makeHandle(),
                childIndex: childIndex,
                byteOffset: byteOffset,
                leftKind: childIndex > 0 ? root.green { $0.child(at: childIndex - 1) }.kind : nil,
                rightKind: childIndex < count ? root.green { $0.child(at: childIndex) }.kind : nil,
                leftTrailingLineBreaks: trailingLineBreakCount(in: leftText ?? ""),
                rightLeadingLineBreaks: leadingLineBreakCount(in: rightText ?? ""),
                leftText: leftText
            )
        }
    }

    private struct ListInsertionTarget {
        let parent: SyntaxNodeHandle<LiminalLanguage>
        let childIndex: Int
        let byteOffset: TextSize
        let baseIndent: Int
        let marker: ListMarker?
        let hasRightSibling: Bool
    }

    private static func listInsertionTarget(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) -> ListInsertionTarget? {
        let searchOffset = tree.withRoot { root -> TextSize in
            if root.textRange.length.rawValue == 0 {
                return .zero
            }
            return TextSize(min(
                cursorByteOffset.rawValue,
                root.textRange.end.rawValue - 1
            ))
        }
        guard let forest = LiminalForest.containing(searchOffset, in: tree) else {
            return nil
        }

        var current: LiminalForest? = forest
        while let candidate = current {
            let parentKind = candidate.parent.withCursor { $0.kind }
            let childKind = candidate.parent.withCursor {
                $0.green { green in green.child(at: candidate.anchorChildIndex) }.kind
            }
            if parentKind == .list, childKind == .listItem {
                return candidate.parent.withCursor { list in
                    let count = list.childOrTokenCount
                    let itemIndex = candidate.anchorChildIndex
                    let childIndex = after ? itemIndex + 1 : itemIndex
                    let byteOffset = childIndex < count
                        ? list.childTextRange(at: childIndex).start
                        : list.textRange.end
                    let referenceIndex = max(0, min(itemIndex, count - 1))
                    let itemText = list.withChildNode(atRawIndex: referenceIndex) {
                        $0.makeString()
                    } ?? ""
                    return ListInsertionTarget(
                        parent: list.makeHandle(),
                        childIndex: childIndex,
                        byteOffset: byteOffset,
                        baseIndent: firstLineIndentColumn(in: itemText) ?? 0,
                        marker: listMarker(in: itemText),
                        hasRightSibling: childIndex < count
                    )
                }
            }
            current = candidate.parentForest()
        }
        return nil
    }

    // MARK: - Builder helpers

    private static func appendChildren(
        of snapshot: GreenTreeSnapshot<LiminalLanguage>,
        to builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try snapshot.makeSyntaxTree().withRoot { root in
            for index in 0..<root.childOrTokenCount {
                try root.withChildNode(atRawIndex: index) { child in
                    _ = try builder.reuseSubtree(child)
                }
            }
        }
    }

    private static func appendBlankLine(
        to builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.blankLine)
        try builder.token(.newline, text: "\n")
        try builder.finishNode()
    }

    private static func appendRootNode(
        of snapshot: GreenTreeSnapshot<LiminalLanguage>,
        to builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        try snapshot.makeSyntaxTree().withRoot { node in
            _ = try builder.reuseSubtree(node)
        }
    }

    private static func normalizedLeftItem(
        target: RootInsertionTarget,
        addingTerminator: Bool
    ) throws -> GreenTreeSnapshot<LiminalLanguage>? {
        guard addingTerminator,
              let leftKind = target.leftKind,
              let leftText = target.leftText
        else { return nil }
        return try documentItemSnapshot(
            from: leftText + "\n",
            expectedKind: leftKind
        )
    }

    private static func rootPayloadSnapshot(
        from source: String,
        expectedChildKinds: [LiminalKind]
    ) throws -> GreenTreeSnapshot<LiminalLanguage> {
        let parsed = try LiminalParser().parse(source)
        let childKinds = parsed.tree.withRoot { root in
            (0..<root.childOrTokenCount).map { index in
                root.green { $0.child(at: index) }.kind
            }
        }
        guard childKinds == expectedChildKinds else {
            throw StructuralCSTPasteError.invalidRootPayload
        }
        return parsed.tree.withRoot { root in
            GreenTreeSnapshot(root: root.green { $0 }, resolver: root.resolver)
        }
    }

    private static func documentItemSnapshot(
        from source: String,
        expectedKind: LiminalKind
    ) throws -> GreenTreeSnapshot<LiminalLanguage> {
        let parsed = try LiminalParser().parse(source)
        return try parsed.tree.withRoot { root -> GreenTreeSnapshot<LiminalLanguage> in
            guard root.childOrTokenCount == 1,
                  root.green({ $0.child(at: 0) }).kind == expectedKind
            else {
                throw StructuralCSTPasteError.invalidRootPayload
            }
            return try root.withChildNode(atRawIndex: 0) { item in
                GreenTreeSnapshot(
                    root: item.green { $0 },
                    resolver: item.resolver
                )
            }!
        }
    }

    // MARK: - List source transforms

    private enum ListMarker: Equatable {
        case unordered(Character)
        case ordered
    }

    private static func listMarker(in text: String) -> ListMarker? {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return nil }
        let line = String(firstLine)
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let next = trimmed.index(after: trimmed.startIndex)
            guard next < trimmed.endIndex, isHorizontalWhitespace(trimmed[next]) else {
                return nil
            }
            return .unordered(first)
        }
        if first.isNumber {
            var cursor = trimmed.startIndex
            while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
                cursor = trimmed.index(after: cursor)
            }
            guard cursor < trimmed.endIndex, trimmed[cursor] == "." else {
                return nil
            }
            let afterDot = trimmed.index(after: cursor)
            guard afterDot < trimmed.endIndex, isHorizontalWhitespace(trimmed[afterDot]) else {
                return nil
            }
            return .ordered
        }
        return nil
    }

    private static func markersAreCompatible(_ lhs: ListMarker, _ rhs: ListMarker) -> Bool {
        switch (lhs, rhs) {
        case (.unordered, .unordered), (.ordered, .ordered):
            true
        default:
            false
        }
    }

    private static func normalizedMarker(
        sourceMarker: ListMarker,
        targetMarker: ListMarker
    ) -> Character? {
        switch (sourceMarker, targetMarker) {
        case (.unordered, .unordered(let marker)):
            marker
        default:
            nil
        }
    }

    private static func rebaseListSource(
        _ source: String,
        sourceBaseIndent: Int,
        targetBaseIndent: Int,
        topLevelMarker: Character?
    ) -> String {
        let delta = targetBaseIndent - sourceBaseIndent
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        return lines.enumerated().map { offset, lineSub in
            var line = String(lineSub)
            if offset == lines.count - 1, line.isEmpty, source.hasSuffix("\n") {
                return line
            }
            let prefix = leadingHorizontalWhitespace(in: line)
            let oldColumn = indentationColumn(prefix)
            let newColumn = max(0, oldColumn + delta)
            line.removeFirst(prefix.count)
            if oldColumn == sourceBaseIndent, let topLevelMarker {
                line = replacingUnorderedMarker(in: line, with: topLevelMarker)
            }
            return String(repeating: " ", count: newColumn) + line
        }.joined(separator: "\n")
    }

    private static func replacingUnorderedMarker(
        in line: String,
        with marker: Character
    ) -> String {
        guard let first = line.first,
              first == "-" || first == "*" || first == "+"
        else { return line }
        var copy = line
        copy.replaceSubrange(copy.startIndex...copy.startIndex, with: String(marker))
        return copy
    }

    private static func leadingHorizontalWhitespace(in line: String) -> String {
        String(line.prefix { isHorizontalWhitespace($0) })
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private static func firstLineIndentColumn(in text: String) -> Int? {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return nil }
        return indentationColumn(leadingHorizontalWhitespace(in: String(firstLine)))
    }

    private static func indentationColumn(_ whitespace: String) -> Int {
        var column = 0
        for character in whitespace {
            column += character == "\t" ? 4 - (column % 4) : 1
        }
        return column
    }

    // MARK: - Misc

    private static func cursorOffset(
        insertionStart: TextSize,
        insertedText: String
    ) -> TextSize {
        var bytesToCursor = 0
        for byte in insertedText.utf8 {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                bytesToCursor += 1
            } else {
                break
            }
        }
        return insertionStart + TextSize(UInt32(bytesToCursor))
    }

    private static func needsRootSeparator(
        left: LiminalKind?,
        right: LiminalKind?
    ) -> Bool {
        guard let left, let right, left != .blankLine, right != .blankLine else {
            return false
        }
        guard left == right else { return false }
        switch left {
        case .paragraph, .list, .blockQuote, .pipeTable:
            return true
        default:
            return false
        }
    }

    private static func rootBoundaryNewlineCount(
        left: LiminalKind?,
        right: LiminalKind?,
        leftTrailingLineBreaks: Int,
        rightLeadingLineBreaks: Int
    ) -> Int {
        guard let left, let right else { return 0 }
        let required = requiredRootBoundaryLineBreaks(left: left, right: right)
        return max(0, required - leftTrailingLineBreaks - rightLeadingLineBreaks)
    }

    private static func requiredRootBoundaryLineBreaks(
        left: LiminalKind,
        right: LiminalKind
    ) -> Int {
        if right == .blankLine || needsRootSeparator(left: left, right: right) {
            return 2
        }
        return 1
    }

    private static func endsWithLineBreak(_ text: String) -> Bool {
        trailingLineBreakCount(in: text) > 0
    }

    private static func leadingLineBreakCount(in text: String) -> Int {
        var cursor = text.startIndex
        var count = 0
        while cursor < text.endIndex, count < 2 {
            switch text[cursor] {
            case "\n":
                cursor = text.index(after: cursor)
                count += 1
            case "\r":
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "\n" {
                    cursor = text.index(after: next)
                } else {
                    cursor = next
                }
                count += 1
            default:
                return count
            }
        }
        return count
    }

    private static func trailingLineBreakCount(in text: String) -> Int {
        var cursor = text.endIndex
        var count = 0
        while cursor > text.startIndex, count < 2 {
            let previous = text.index(before: cursor)
            switch text[previous] {
            case "\n":
                let beforePrevious = previous > text.startIndex
                    ? text.index(before: previous)
                    : text.startIndex
                cursor = previous > text.startIndex && text[beforePrevious] == "\r"
                    ? beforePrevious
                    : previous
                count += 1
            case "\r":
                cursor = previous
                count += 1
            default:
                return count
            }
        }
        return count
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
}

private enum StructuralCSTPasteError: Error {
    case invalidRootPayload
    case invalidListPayload
}
