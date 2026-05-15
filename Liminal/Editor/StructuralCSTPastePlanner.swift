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
    private struct ListPayloadSource {
        let marker: StructuralCSTListSource.Marker
        let baseIndent: Int
    }

    static func plan(
        payload: StructuralCSTClipboardPayload,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        let fragment = payload.fragment
        guard !fragment.snapshot.root.containsSentinels else { return nil }

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
        case .listItem where payload.projection.kind == .listItemContent:
            return try planProjectedRootPayload(
                payload.logicalText,
                in: tree,
                cursorByteOffset: cursorByteOffset,
                after: after
            )
        case .blockQuote where payload.projection.kind == .blockQuoteContent:
            return try planProjectedRootPayload(
                payload.logicalText,
                in: tree,
                cursorByteOffset: cursorByteOffset,
                after: after
            )
        default:
            return nil
        }
    }

    static func planListItems(
        payload: StructuralCSTClipboardPayload,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard let fragment = try listItemSequenceFragment(from: payload),
              let source = listPayloadSource(for: fragment),
              let target = explicitListInsertionTarget(
                  in: tree,
                  cursorByteOffset: cursorByteOffset,
                  after: after
              )
        else { return nil }

        return try planListFragment(
            fragment,
            source: source,
            target: target
        )
    }

    static func planNestedListItem(
        payload: StructuralCSTClipboardPayload,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard let target = nestedListItemTarget(
            in: tree,
            cursorByteOffset: cursorByteOffset
        ) else { return nil }

        let placement = nestedInsertionPlacement(in: target, after: after)
        guard var payloadText = try nestedListItemPayloadText(
            from: payload,
            target: target,
            placement: placement
        ) else { return nil }

        let relativeInsertion = Int(
            placement.byteOffset.rawValue - target.byteRange.start.rawValue
        )
        if needsLeadingLineBreak(
            in: target.sourceText,
            atRelativeByteOffset: relativeInsertion
        ) {
            payloadText = "\n" + payloadText
        }

        let newItemText = inserting(
            payloadText,
            into: target.sourceText,
            atRelativeByteOffset: relativeInsertion
        )
        let replacement = try listItemSnapshot(from: newItemText)
        let insertionRange = CambiumCore.TextRange(
            start: placement.byteOffset,
            length: .zero
        )
        return StructuralCSTPastePlan(
            target: target.handle,
            replacement: replacement,
            edit: TextEdit(range: insertionRange, replacement: payloadText),
            cursorByteOffset: cursorOffset(
                insertionStart: placement.byteOffset,
                insertedText: payloadText
            )
        )
    }

    static func plan(
        fragment: StructuralCSTFragment,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        try plan(
            payload: StructuralCSTClipboardPayload(
                fragment: fragment,
                projection: StructuralCSTSourceProjection(fragment: fragment)
            ),
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after
        )
    }

    // MARK: - Root / document-item adapter

    private static func planRootFragment(
        _ fragment: StructuralCSTFragment,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard !fragment.hasTokenChildren,
              !fragment.childKinds.isEmpty,
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
        guard let source = listPayloadSource(for: fragment)
        else { return nil }

        if let target = listInsertionTarget(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after
        ) {
            return try planListFragment(
                fragment,
                source: source,
                target: target
            )
        }

        let payload = try listPayloadSnapshot(
            from: fragment,
            sourceBaseIndent: source.baseIndent,
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
                    sourceBaseIndent: source.baseIndent,
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

    private static func planListFragment(
        _ fragment: StructuralCSTFragment,
        source: ListPayloadSource,
        target: ListInsertionTarget
    ) throws -> StructuralCSTPastePlan? {
        guard let targetMarker = target.marker,
              StructuralCSTListSource.markersAreCompatible(source.marker, targetMarker)
        else { return nil }

        let payload = try listPayloadSnapshot(
            from: fragment,
            sourceBaseIndent: source.baseIndent,
            targetBaseIndent: target.baseIndent,
            topLevelMarker: StructuralCSTListSource.normalizedMarker(
                sourceMarker: source.marker,
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

    private static func listPayloadSource(
        for fragment: StructuralCSTFragment
    ) -> ListPayloadSource? {
        guard !fragment.hasTokenChildren,
              !fragment.childKinds.isEmpty,
              fragment.childKinds.allSatisfy({ $0 == .listItem }),
              let marker = StructuralCSTListSource.marker(in: fragment.sourceText),
              let baseIndent = StructuralCSTListSource.firstLineIndentColumn(
                  in: fragment.sourceText
              )
        else { return nil }

        return ListPayloadSource(marker: marker, baseIndent: baseIndent)
    }

    private static func listItemSequenceFragment(
        from payload: StructuralCSTClipboardPayload
    ) throws -> StructuralCSTFragment? {
        if payload.fragment.wrapperKind == .list,
           payload.projection.kind == .listItems,
           listPayloadSource(for: payload.fragment) != nil
        {
            return payload.fragment
        }

        return try projectedListFragment(from: payload)
    }

    private static func projectedListFragment(
        from payload: StructuralCSTClipboardPayload
    ) throws -> StructuralCSTFragment? {
        guard payload.fragment.wrapperKind == .listItem,
              payload.fragment.childKinds == [.list],
              payload.projection.kind == .listItemContent
        else { return nil }

        let parsed = try LiminalParser().parse(payload.logicalText)
        return parsed.tree.withRoot { root -> StructuralCSTFragment? in
            guard root.childOrTokenCount == 1,
                  root.green({ $0.child(at: 0) }).kind == .list
            else { return nil }

            return root.withChildNode(atRawIndex: 0) { list in
                StructuralCSTFragment(
                    snapshot: GreenTreeSnapshot(
                        root: list.green { $0 },
                        resolver: list.resolver
                    )
                )
            }!
        }
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
        let shifted = StructuralCSTListSource.rebase(
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
                return root.withChildNode(atRawIndex: index) { list in
                    let green = list.green { $0 }
                    return GreenTreeSnapshot(root: green, resolver: list.resolver)
                }!
            }
            throw StructuralCSTPasteError.invalidListPayload
        }
    }

    // MARK: - Nested list-item adapter

    private enum NestedPayload {
        case list(StructuralCSTFragment, ListPayloadSource)
        case text(String)
    }

    private struct NestedListItemTarget {
        let handle: SyntaxNodeHandle<LiminalLanguage>
        let byteRange: CambiumCore.TextRange
        let sourceText: String
        let contentColumn: Int
        let marker: StructuralCSTListSource.Marker
        let childList: NestedChildList?
    }

    private struct NestedChildList {
        let byteRange: CambiumCore.TextRange
        let baseIndent: Int
        let marker: StructuralCSTListSource.Marker
    }

    private struct NestedInsertionPlacement {
        let byteOffset: TextSize
        let baseIndent: Int
        let marker: StructuralCSTListSource.Marker
    }

    private static func nestedListItemPayloadText(
        from payload: StructuralCSTClipboardPayload,
        target: NestedListItemTarget,
        placement: NestedInsertionPlacement
    ) throws -> String? {
        guard let nestedPayload = try nestedPayload(from: payload) else {
            return nil
        }

        switch nestedPayload {
        case .list(let fragment, let source):
            guard target.childList == nil
                    || StructuralCSTListSource.markersAreCompatible(
                        source.marker,
                        placement.marker
                    )
            else { return nil }

            let payload = try listPayloadSnapshot(
                from: fragment,
                sourceBaseIndent: source.baseIndent,
                targetBaseIndent: placement.baseIndent,
                topLevelMarker: target.childList == nil
                    ? nil
                    : StructuralCSTListSource.normalizedMarker(
                        sourceMarker: source.marker,
                        targetMarker: placement.marker
                    ),
                ensureTrailingNewline: true
            )
            let text = payload.root.makeString(using: payload.resolver)
            return text.isEmpty ? nil : text

        case .text(let source):
            return wrappedListItemText(
                source,
                baseIndent: placement.baseIndent,
                marker: placement.marker
            )
        }
    }

    private static func nestedPayload(
        from payload: StructuralCSTClipboardPayload
    ) throws -> NestedPayload? {
        let source = payload.logicalText
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        if let fragment = try singleListFragment(from: source),
           let listSource = listPayloadSource(for: fragment)
        {
            return .list(fragment, listSource)
        }

        let parsed = try parsedRootPayload(from: source)
        guard parsed.childKinds.allSatisfy({
            $0 == .paragraph || $0 == .blankLine
        }) else { return nil }
        return .text(source)
    }

    private static func singleListFragment(
        from source: String
    ) throws -> StructuralCSTFragment? {
        let parsed = try LiminalParser().parse(source)
        return parsed.tree.withRoot { root -> StructuralCSTFragment? in
            guard root.childOrTokenCount == 1,
                  root.green({ $0.child(at: 0) }).kind == .list
            else { return nil }

            return root.withChildNode(atRawIndex: 0) { list in
                StructuralCSTFragment(
                    snapshot: GreenTreeSnapshot(
                        root: list.green { $0 },
                        resolver: list.resolver
                    )
                )
            }!
        }
    }

    private static func wrappedListItemText(
        _ source: String,
        baseIndent: Int,
        marker: StructuralCSTListSource.Marker
    ) -> String? {
        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalizedSource.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        if normalizedSource.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return nil }

        let markerText = listMarkerText(for: marker)
        let firstPrefix = String(repeating: " ", count: baseIndent)
            + markerText
            + " "
        let continuationPrefix = String(
            repeating: " ",
            count: baseIndent + markerText.utf8.count + 1
        )

        var outputLines: [String] = []
        outputLines.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            outputLines.append((index == 0 ? firstPrefix : continuationPrefix) + line)
        }
        return outputLines.joined(separator: "\n") + "\n"
    }

    private static func nestedListItemTarget(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize
    ) -> NestedListItemTarget? {
        let searchOffset = tree.withRoot { root -> TextSize in
            if root.textRange.length.rawValue == 0 {
                return .zero
            }
            return TextSize(min(
                cursorByteOffset.rawValue,
                root.textRange.end.rawValue - 1
            ))
        }
        guard let forest = LiminalForest.containing(
            searchOffset,
            in: tree,
            affinity: .downstream
        ) else {
            return nil
        }

        var current: LiminalForest? = forest
        while let candidate = current {
            let parentKind = candidate.parent.withCursor { $0.kind }
            let childKind = candidate.parent.withCursor {
                $0.green { green in green.child(at: candidate.anchorChildIndex) }.kind
            }

            if parentKind == .listItem {
                return nestedListItemTarget(for: candidate.parent)
            }
            if parentKind == .list, childKind == .listItem {
                return candidate.parent.withCursor { list in
                    list.withChildNode(atRawIndex: candidate.anchorChildIndex) { item in
                        nestedListItemTarget(for: item.makeHandle())
                    } ?? nil
                }
            }

            current = candidate.parentForest()
        }
        return nil
    }

    private static func nestedListItemTarget(
        for handle: SyntaxNodeHandle<LiminalLanguage>
    ) -> NestedListItemTarget? {
        handle.withCursor { item in
            let sourceText = item.makeString()
            guard let contentColumn = StructuralCSTListSource.listItemContentColumn(
                in: sourceText
            ),
                  let marker = StructuralCSTListSource.marker(in: sourceText)
            else { return nil }

            var childLists: [NestedChildList] = []
            for childIndex in 0..<item.childOrTokenCount {
                let child = item.green { $0.child(at: childIndex) }
                guard child.kind == .list else { continue }

                let childList: NestedChildList? = item.withChildNode(
                    atRawIndex: childIndex
                ) { list in
                    guard list.childOrTokenCount > 0 else { return nil }
                    let firstItemText = list.withChildNode(atRawIndex: 0) {
                        $0.makeString()
                    } ?? ""
                    guard let baseIndent = StructuralCSTListSource.firstLineIndentColumn(
                        in: firstItemText
                    ),
                          let marker = StructuralCSTListSource.marker(in: firstItemText)
                    else { return nil }
                    return NestedChildList(
                        byteRange: list.textRange,
                        baseIndent: baseIndent,
                        marker: marker
                    )
                } ?? nil
                if let childList {
                    childLists.append(childList)
                }
            }
            guard childLists.count <= 1 else { return nil }

            return NestedListItemTarget(
                handle: handle,
                byteRange: item.textRange,
                sourceText: sourceText,
                contentColumn: contentColumn,
                marker: marker,
                childList: childLists.first
            )
        }
    }

    private static func nestedInsertionPlacement(
        in target: NestedListItemTarget,
        after: Bool
    ) -> NestedInsertionPlacement {
        if let childList = target.childList {
            return NestedInsertionPlacement(
                byteOffset: after ? childList.byteRange.end : childList.byteRange.start,
                baseIndent: childList.baseIndent,
                marker: childList.marker
            )
        }
        return NestedInsertionPlacement(
            byteOffset: target.byteRange.end,
            baseIndent: target.contentColumn,
            marker: target.marker
        )
    }

    private static func listItemSnapshot(
        from source: String
    ) throws -> GreenTreeSnapshot<LiminalLanguage> {
        let parsed = try LiminalParser().parse(source)
        return try parsed.tree.withRoot { root -> GreenTreeSnapshot<LiminalLanguage> in
            guard root.childOrTokenCount == 1,
                  root.green({ $0.child(at: 0) }).kind == .list
            else {
                throw StructuralCSTPasteError.invalidListItemPayload
            }
            return try root.withChildNode(atRawIndex: 0) { list in
                guard list.childOrTokenCount == 1,
                      list.green({ $0.child(at: 0) }).kind == .listItem
                else {
                    throw StructuralCSTPasteError.invalidListItemPayload
                }
                return list.withChildNode(atRawIndex: 0) { item in
                    GreenTreeSnapshot(
                        root: item.green { $0 },
                        resolver: item.resolver
                    )
                }!
            }!
        }
    }

    private static func inserting(
        _ insertion: String,
        into source: String,
        atRelativeByteOffset relativeByteOffset: Int
    ) -> String {
        let index = source.utf8.index(
            source.startIndex,
            offsetBy: relativeByteOffset
        )
        return String(source[..<index]) + insertion + String(source[index...])
    }

    private static func needsLeadingLineBreak(
        in source: String,
        atRelativeByteOffset relativeByteOffset: Int
    ) -> Bool {
        guard relativeByteOffset > 0 else { return false }
        let index = source.utf8.index(
            source.startIndex,
            offsetBy: relativeByteOffset
        )
        return !endsWithLineBreak(String(source[..<index]))
    }

    private static func listMarkerText(
        for marker: StructuralCSTListSource.Marker
    ) -> String {
        switch marker {
        case .unordered(let marker):
            String(marker)
        case .ordered:
            "1."
        }
    }

    // MARK: - Block quote content adapter

    private struct ParsedRootPayload {
        let snapshot: GreenTreeSnapshot<LiminalLanguage>
        let childKinds: [LiminalKind]
    }

    private static func planProjectedRootPayload(
        _ liftedText: String,
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) throws -> StructuralCSTPastePlan? {
        guard !liftedText.isEmpty else { return nil }

        let payload = try parsedRootPayload(from: liftedText)
        guard let firstPayloadKind = payload.childKinds.first,
              let lastPayloadKind = payload.childKinds.last
        else { return nil }

        return try planRootInsertion(
            in: tree,
            cursorByteOffset: cursorByteOffset,
            after: after,
            payloadText: liftedText,
            firstPayloadKind: firstPayloadKind,
            lastPayloadKind: lastPayloadKind,
            appendPayload: { builder in
                try appendChildren(of: payload.snapshot, to: &builder)
            },
            appendPayloadWithTrailingNewline: { builder in
                let terminated = try rootPayloadSnapshot(
                    from: liftedText + "\n",
                    expectedChildKinds: payload.childKinds
                )
                try appendChildren(of: terminated, to: &builder)
            }
        )
    }

    private static func parsedRootPayload(
        from source: String
    ) throws -> ParsedRootPayload {
        let parsed = try LiminalParser().parse(source)
        let childKinds = parsed.tree.withRoot { root in
            (0..<root.childOrTokenCount).map { index in
                root.green { $0.child(at: index) }.kind
            }
        }
        guard !childKinds.isEmpty,
              childKinds.allSatisfy(isDocumentItemKind)
        else {
            throw StructuralCSTPasteError.invalidBlockQuotePayload
        }
        let snapshot = parsed.tree.withRoot { root in
            GreenTreeSnapshot(root: root.green { $0 }, resolver: root.resolver)
        }
        return ParsedRootPayload(snapshot: snapshot, childKinds: childKinds)
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
        let marker: StructuralCSTListSource.Marker?
        let hasRightSibling: Bool
    }

    private enum ExplicitListTargetSearchResult {
        case found(ListInsertionTarget)
        case rejected
        case noCandidate
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
        guard let forest = LiminalForest.containing(
            searchOffset,
            in: tree,
            affinity: .downstream
        ) else {
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
                        baseIndent: StructuralCSTListSource.firstLineIndentColumn(
                            in: itemText
                        ) ?? 0,
                        marker: StructuralCSTListSource.marker(in: itemText),
                        hasRightSibling: childIndex < count
                    )
                }
            }
            current = candidate.parentForest()
        }
        return nil
    }

    private static func explicitListInsertionTarget(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        cursorByteOffset: TextSize,
        after: Bool
    ) -> ListInsertionTarget? {
        guard let forest = LiminalForest.cursorTarget(
            at: cursorByteOffset,
            in: tree
        ) else {
            return nil
        }
        switch explicitListInsertionTarget(
            from: forest,
            cursorByteOffset: cursorByteOffset,
            after: after
        ) {
        case .found(let target):
            return target
        case .rejected, .noCandidate:
            return nil
        }
    }

    private static func explicitListInsertionTarget(
        from forest: LiminalForest,
        cursorByteOffset: TextSize,
        after: Bool
    ) -> ExplicitListTargetSearchResult {
        var current: LiminalForest? = forest
        while let candidate = current {
            let parentKind = candidate.parent.withCursor { $0.kind }
            let childKind = candidate.parent.withCursor {
                $0.green { green in green.child(at: candidate.anchorChildIndex) }.kind
            }
            if parentKind == .list, childKind == .listItem {
                guard cursorByteOffsetIsOnListItemMarker(
                    cursorByteOffset,
                    candidate: candidate
                ) else { return .rejected }
                guard let target = listInsertionTarget(
                    forListItem: candidate,
                    after: after
                ) else { return .rejected }
                return .found(target)
            }
            current = candidate.parentForest()
        }
        return .noCandidate
    }

    private static func listInsertionTarget(
        forListItem candidate: LiminalForest,
        after: Bool
    ) -> ListInsertionTarget? {
        let parentKind = candidate.parent.withCursor { $0.kind }
        let childKind = candidate.parent.withCursor {
            $0.green { green in green.child(at: candidate.anchorChildIndex) }.kind
        }
        guard parentKind == .list, childKind == .listItem else { return nil }

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
                baseIndent: StructuralCSTListSource.firstLineIndentColumn(
                    in: itemText
                ) ?? 0,
                marker: StructuralCSTListSource.marker(in: itemText),
                hasRightSibling: childIndex < count
            )
        }
    }

    private static func cursorByteOffsetIsOnListItemMarker(
        _ cursorByteOffset: TextSize,
        candidate: LiminalForest
    ) -> Bool {
        candidate.parent.withCursor { list in
            list.withChildNode(atRawIndex: candidate.anchorChildIndex) { item in
                guard let markerRange = listItemMarkerByteRange(in: item) else {
                    return false
                }
                return cursorByteOffset.rawValue >= markerRange.start.rawValue
                    && cursorByteOffset.rawValue <= markerRange.end.rawValue
            } ?? false
        }
    }

    private static func listItemMarkerByteRange(
        in item: borrowing SyntaxNodeCursor<LiminalLanguage>
    ) -> CambiumCore.TextRange? {
        var markerRange: CambiumCore.TextRange?
        item.forEachChildOrToken { element in
            guard markerRange == nil else { return }
            switch element {
            case .token(let token):
                let kind = LiminalLanguage.kind(for: token.rawKind)
                guard kind == .listMarker || kind == .orderedListMarker else {
                    return
                }
                markerRange = token.textRange
            case .node:
                return
            }
        }
        return markerRange
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
            return root.withChildNode(atRawIndex: 0) { item in
                GreenTreeSnapshot(
                    root: item.green { $0 },
                    resolver: item.resolver
                )
            }!
        }
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
    case invalidListItemPayload
    case invalidBlockQuotePayload
}
