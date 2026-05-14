import CambiumCore
import Testing
@testable import Liminal

@Suite("Structural CST selection projection")
struct StructuralCSTSelectionProjectionTests {
    @Test("block quote paragraph projection strips continuation quote markers")
    func blockQuoteParagraphProjection() throws {
        let fragment = try blockQuoteFragment(
            source: "> foo\n> bar\n> baz\n",
            childKind: .paragraph
        )

        let projection = try #require(
            StructuralCSTSourceProjection.blockQuoteContent(for: fragment)
        )
        #expect(projection.kind == .blockQuoteContent)
        #expect(projection.logicalText(from: fragment.sourceText) == "foo\nbar\nbaz\n")
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == [
            "0..<4",
            "6..<10",
            "12..<16"
        ])
    }

    @Test("block quote multi-child projection strips direct quote prefix tokens")
    func blockQuoteMultiChildProjection() throws {
        let source = "> foo\n> - item\n"
        let parsed = try LiminalParser().parse(source)
        let paragraph = try #require(
            firstBlockQuoteChildForest(in: parsed.tree, childKind: .paragraph)
        )
        let forest = try #require(paragraph.extendedForward())
        let fragment = try StructuralCSTFragment.capture(forest)

        let projection = try #require(
            StructuralCSTSourceProjection.blockQuoteContent(for: fragment)
        )
        #expect(projection.logicalText(from: fragment.sourceText) == "foo\n- item\n")
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == [
            "0..<4",
            "6..<13"
        ])
    }

    @Test("block quote projection preserves nested quote marker on first line")
    func blockQuoteProjectionPreservesNestedFirstLineMarker() throws {
        let fragment = try blockQuoteFragment(
            source: "> > nested\n> after\n",
            childKind: .blockQuote
        )

        let projection = try #require(
            StructuralCSTSourceProjection.blockQuoteContent(for: fragment)
        )
        #expect(projection.logicalText(from: fragment.sourceText) == "> nested\n")
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == ["0..<9"])
    }

    @Test("nested list item projection rebases base indent")
    func nestedListItemProjectionRebasesBaseIndent() throws {
        let fragment = try listItemFragment(
            source: """
            - foo
              - bar
                - bax
              - qux
            """,
            needle: "bar"
        )

        let projection = try #require(
            StructuralCSTSourceProjection.listItems(for: fragment)
        )
        #expect(projection.kind == .listItems)
        #expect(projection.logicalText(from: fragment.sourceText) == "- bar\n  - bax\n")
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == [
            "2..<8",
            "10..<18"
        ])
    }

    @Test("multi-item list projection rebases each selected sibling")
    func multiItemListProjectionRebasesEachSelectedSibling() throws {
        let source = """
        - foo
          - bar
            - bax
          - qux
        """
        let parsed = try LiminalParser().parse(source)
        let offset = try byteOffset(of: "bar", in: source)
        let forest = try #require(
            listItemForest(containing: offset, in: parsed.tree)
        )
        let extended = try #require(forest.extendedForward())
        let fragment = try StructuralCSTFragment.capture(extended)

        let projection = try #require(
            StructuralCSTSourceProjection.listItems(for: fragment)
        )
        #expect(projection.logicalText(from: fragment.sourceText) == "- bar\n  - bax\n- qux")
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == [
            "2..<8",
            "10..<18",
            "20..<25"
        ])
    }

    @Test("root paragraph projection is identity")
    func rootParagraphProjectionIsIdentity() throws {
        let source = "One.\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsed.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let projection = StructuralCSTSourceProjection(fragment: fragment)
        #expect(projection.kind == .identity)
        #expect(projection.logicalText(from: fragment.sourceText) == source)
        #expect(rangeLabels(projection.relativeHighlightRanges(
            sourceByteCount: fragment.sourceText.utf8.count
        )) == ["0..<5"])
    }

    @Test("list item opening paragraph projection strips continuation prefix")
    func listItemOpeningParagraphProjection() throws {
        let source = "- foo\n  bar\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstParagraphForestInFirstListItem(in: parsed.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )

        #expect(capture.fragment.wrapperKind == .listItem)
        #expect(capture.projection.kind == .listItemContent)
        #expect(capture.logicalText == "foo\nbar")
        #expect(rangeLabels(capture.relativeHighlightRanges) == [
            "0..<4",
            "6..<9"
        ])
    }

    @Test("list item projection preserves indentation beyond content column")
    func listItemProjectionPreservesExtraContinuationIndent() throws {
        let source = "- foo\n    bar\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstParagraphForestInFirstListItem(in: parsed.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )

        #expect(capture.projection.kind == .listItemContent)
        #expect(capture.logicalText == "foo\n  bar")
    }

    @Test("list item child list projection strips parent content column")
    func listItemChildListProjection() throws {
        let source = "- foo\n  - bar\n    - bax\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstChildListForestInFirstListItem(in: parsed.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )

        #expect(capture.fragment.wrapperKind == .listItem)
        #expect(capture.fragment.childKinds == [.list])
        #expect(capture.projection.kind == .listItemContent)
        #expect(capture.logicalText == "- bar\n  - bax\n")
    }

    @Test("clipboard payload round-trips raw fragment and source projection")
    func clipboardPayloadRoundTrip() throws {
        let source = "- foo\n  - bar\n    - bax\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstChildListForestInFirstListItem(in: parsed.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )

        let decoded = try StructuralCSTClipboardPayload.decode(
            data: try capture.clipboardPayload.serializedData()
        )

        #expect(decoded.fragment.wrapperKind == capture.fragment.wrapperKind)
        #expect(decoded.fragment.childKinds == capture.fragment.childKinds)
        #expect(decoded.fragment.sourceText == capture.fragment.sourceText)
        #expect(decoded.projection == capture.projection)
        #expect(decoded.logicalText == capture.logicalText)
    }

    private func blockQuoteFragment(
        source: String,
        childKind: LiminalKind
    ) throws -> StructuralCSTFragment {
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstBlockQuoteChildForest(in: parsed.tree, childKind: childKind)
        )
        return try StructuralCSTFragment.capture(forest)
    }

    private func firstBlockQuoteChildForest(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        childKind expectedChildKind: LiminalKind
    ) -> LiminalForest? {
        tree.withRoot { root in
            for rootIndex in 0..<root.childOrTokenCount {
                let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
                guard rootChildKind == .blockQuote else { continue }

                return root.withChildNode(atRawIndex: rootIndex) { blockQuote in
                    for childIndex in 0..<blockQuote.childOrTokenCount {
                        let childKind = blockQuote.green { $0.child(at: childIndex) }.kind
                        guard childKind == expectedChildKind else { continue }
                        return LiminalForest(
                            parent: blockQuote.makeHandle(),
                            anchorChildIndex: childIndex,
                            headChildIndex: childIndex
                        )
                    }
                    return nil
                } ?? nil
            }
            return nil
        }
    }

    private func listItemFragment(
        source: String,
        needle: String
    ) throws -> StructuralCSTFragment {
        let parsed = try LiminalParser().parse(source)
        let offset = try byteOffset(of: needle, in: source)
        let forest = try #require(
            listItemForest(containing: offset, in: parsed.tree)
        )
        return try StructuralCSTFragment.capture(forest)
    }

    private func listItemForest(
        containing offset: Int,
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        guard var forest = LiminalForest.cstVisualEntry(
            at: TextSize(UInt32(offset)),
            in: tree
        ) else { return nil }
        while true {
            let parentKind = forest.parent.withCursor { $0.kind }
            let childKind = forest.parent.withCursor {
                $0.green { green in green.child(at: forest.anchorChildIndex) }.kind
            }
            if parentKind == .list, childKind == .listItem {
                return forest
            }
            guard let parent = forest.parentForest() else { return nil }
            forest = parent
        }
    }

    private func firstChildListForestInFirstListItem(
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        firstForestInFirstListItem(in: tree, childKind: .list)
    }

    private func firstParagraphForestInFirstListItem(
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        firstForestInFirstListItem(in: tree, childKind: .paragraph)
    }

    private func firstForestInFirstListItem(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        childKind expectedKind: LiminalKind
    ) -> LiminalForest? {
        tree.withRoot { root in
            for rootIndex in 0..<root.childOrTokenCount {
                let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
                guard rootChildKind == .list else { continue }

                return root.withChildNode(atRawIndex: rootIndex) { list in
                    list.withChildNode(atRawIndex: 0) { item in
                        for childIndex in 0..<item.childOrTokenCount {
                            let childKind = item.green { $0.child(at: childIndex) }.kind
                            guard childKind == expectedKind else { continue }
                            return LiminalForest(
                                parent: item.makeHandle(),
                                anchorChildIndex: childIndex,
                                headChildIndex: childIndex
                            )
                        }
                        return nil
                    } ?? nil
                } ?? nil
            }
            return nil
        }
    }

    private func byteOffset(of needle: String, in source: String) throws -> Int {
        let range = try #require(source.range(of: needle))
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
    }

    private func rangeLabels(
        _ ranges: [CambiumCore.TextRange]
    ) -> [String] {
        ranges.map { "\($0.start.rawValue)..<\($0.end.rawValue)" }
    }
}
