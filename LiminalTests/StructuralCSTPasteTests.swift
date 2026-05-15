import CambiumCore
import Testing
@testable import Liminal

@Suite("Structural CST paste")
struct StructuralCSTPasteTests {
    @Test("capturing a root paragraph wraps it in a root snapshot")
    func captureRootParagraph() throws {
        let source = "Hello.\n\nWorld.\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsed.tree)
        )

        let fragment = try StructuralCSTFragment.capture(forest)
        #expect(fragment.wrapperKind == .root)
        #expect(fragment.childKinds == [.paragraph])
        #expect(fragment.sourceText == "Hello.\n")

        let decoded = try StructuralCSTFragment.decode(
            data: fragment.serializedData()
        )
        #expect(decoded.wrapperKind == .root)
        #expect(decoded.childKinds == [.paragraph])
        #expect(decoded.sourceText == "Hello.\n")
    }

    @Test("capturing a nested list item wraps the selected item in a list snapshot")
    func captureNestedListItem() throws {
        let source = """
        - foo
          - bar
            - bax
          - qux
        - zot
        """
        let parsed = try LiminalParser().parse(source)
        let offset = try byteOffset(of: "bar", in: source)
        let forest = try #require(
            listItemForest(containing: offset, in: parsed.tree)
        )

        let fragment = try StructuralCSTFragment.capture(forest)
        #expect(fragment.wrapperKind == .list)
        #expect(fragment.childKinds == [.listItem])
        #expect(fragment.sourceText.contains("  - bar\n"))
        #expect(fragment.sourceText.contains("    - bax\n"))
        #expect(!fragment.sourceText.contains("  - qux\n"))
    }

    @Test("root paragraph paste inserts a blank-line separator to avoid merging")
    func rootParagraphPasteSeparatesParagraphs() throws {
        let source = "One.\n\nTwo.\n"
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsed.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsed.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "\nOne.\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: source
        )
        #expect(newSource == "One.\n\nOne.\n\nTwo.\n")
    }

    @Test("list item block paste after a top-level list separates root lists")
    func listItemBlockPasteAfterTopLevelListSeparatesRootLists() throws {
        let fragment = try nestedBarFragment()
        let target = "- zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "\n- bar\n  - bax\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- zot\n\n- bar\n  - bax\n")
    }

    @Test("list item block paste from inside a nested list targets the root block")
    func listItemBlockPasteFromNestedListTargetsRootBlock() throws {
        let fragment = try nestedBarFragment()
        let target = """
        - foo
          - qux
        """
        let parsedTarget = try LiminalParser().parse(target)
        let offset = try byteOffset(of: "qux", in: target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(offset)),
            after: false
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "- bar\n  - bax\n\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- bar\n  - bax\n\n- foo\n  - qux")
    }

    @Test("list block paste preserves the source marker")
    func listBlockPastePreservesSourceMarker() throws {
        let source = "* foo\n  + bar\n"
        let parsedSource = try LiminalParser().parse(source)
        let sourceOffset = try byteOffset(of: "foo", in: source)
        let forest = try #require(
            listItemForest(containing: sourceOffset, in: parsedSource.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let target = "- zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "\n* foo\n  + bar\n")
    }

    @Test("EOF list item block pasted before a list gets a blank boundary")
    func eofListItemBlockPastedBeforeListGetsBlankBoundary() throws {
        let source = "* foo"
        let parsedSource = try LiminalParser().parse(source)
        let sourceOffset = try byteOffset(of: "foo", in: source)
        let forest = try #require(
            listItemForest(containing: sourceOffset, in: parsedSource.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let target = "- one\n- two\n"
        let parsedTarget = try LiminalParser().parse(target)
        let targetOffset = try byteOffset(of: "two", in: target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(targetOffset)),
            after: false
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "* foo\n\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "* foo\n\n- one\n- two\n")
    }

    @Test("EOF paragraph pasted before a paragraph gets a blank-line boundary")
    func eofParagraphPastedBeforeParagraphGetsBlankBoundary() throws {
        let source = "One."
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsedSource.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let target = "Two.\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: false
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "One.\n\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "One.\n\nTwo.\n")
    }

    @Test("unordered list fragment refuses ordered-list splice target")
    func unorderedIntoOrderedListSpliceRefuses() throws {
        let fragment = try nestedBarFragment()
        let target = "1. zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let payload = StructuralCSTClipboardPayload(
            fragment: fragment,
            projection: StructuralCSTSourceProjection(fragment: fragment)
        )
        #expect(throws: StructuralCSTPasteRejection.incompatibleMarkers) {
            _ = try StructuralCSTPastePlanner.planSplice(
                payload: payload,
                in: parsedTarget.tree,
                cursorByteOffset: .zero,
                after: true
            )
        }
    }

    @Test("block quote paragraph pasted at root strips continuation quote markers")
    func blockQuoteParagraphPastedAtRootStripsContinuationMarkers() throws {
        let source = "> foo\n> bar\n> baz\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstBlockQuoteChildForest(
                in: parsedSource.tree,
                childKind: .paragraph
            )
        )
        let fragment = try StructuralCSTFragment.capture(forest)
        #expect(fragment.wrapperKind == .blockQuote)
        #expect(fragment.sourceText == "foo\n> bar\n> baz\n")

        let target = "after\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: false
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "foo\nbar\nbaz\n\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "foo\nbar\nbaz\n\nafter\n")
    }

    @Test("block quote multi-child paste strips direct quote prefix tokens")
    func blockQuoteMultiChildPasteStripsDirectQuotePrefixTokens() throws {
        let source = "> foo\n> - item\n"
        let parsedSource = try LiminalParser().parse(source)
        let paragraph = try #require(
            firstBlockQuoteChildForest(
                in: parsedSource.tree,
                childKind: .paragraph
            )
        )
        let forest = try #require(paragraph.extendedForward())
        let fragment = try StructuralCSTFragment.capture(forest)
        #expect(fragment.wrapperKind == .blockQuote)
        #expect(fragment.childKinds.contains(.greaterThan))
        #expect(fragment.sourceText == "foo\n> - item\n")

        let parsedTarget = try LiminalParser().parse("")
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "foo\n- item\n")
    }

    @Test("block quote paste removes only the outer quote layer")
    func blockQuotePasteRemovesOnlyOuterQuoteLayer() throws {
        let source = """
        > > nested
        > after
        """
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstBlockQuoteChildForest(
                in: parsedSource.tree,
                childKind: .blockQuote
            )
        )
        let fragment = try StructuralCSTFragment.capture(forest)
        #expect(fragment.wrapperKind == .blockQuote)
        #expect(fragment.childKinds == [.blockQuote])
        #expect(fragment.sourceText == "> nested\n")

        let parsedTarget = try LiminalParser().parse("")
        let plan = try StructuralCSTPastePlanner.planBlock(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "> nested\n")
    }

    @Test("list item paragraph content pastes at root as paragraph")
    func listItemParagraphContentPastesAtRoot() throws {
        let source = "- foo\n  bar\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstParagraphForestInFirstListItem(in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        let target = "after\n"
        let parsedTarget = try LiminalParser().parse(target)

        let plan = try StructuralCSTPastePlanner.planBlock(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: false
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "foo\nbar\n\n")
    }

    @Test("list item child list content pastes at root as list")
    func listItemChildListContentPastesAtRoot() throws {
        let source = "- foo\n  - bar\n    - bax\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstChildListForestInFirstListItem(in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        let parsedTarget = try LiminalParser().parse("")

        let plan = try StructuralCSTPastePlanner.planBlock(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "- bar\n  - bax\n")
    }

    @Test("explicit list item paste splices after a top-level item marker")
    func explicitListItemPasteSplicesAfterTopLevelMarker() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n"
        )
        let target = "- foo\n  - one\n- qux\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - one\n- bar\n- baz\n- qux\n")
    }

    @Test("explicit list item paste finds a target marker after a blank line")
    func explicitListItemPasteFindsMarkerAfterBlankLine() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n"
        )
        let target = "\n- foo\n- qux\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "\n- foo\n- bar\n- baz\n- qux\n")
    }

    @Test("explicit list item paste splices after a nested item marker")
    func explicitListItemPasteSplicesAfterNestedItemMarker() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n"
        )
        let target = "- foo\n  - one\n  - two\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- one", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - one\n  - bar\n  - baz\n  - two\n")
    }

    @Test("explicit list item paste accepts direct list-item payload")
    func explicitListItemPasteAcceptsDirectListItemPayload() throws {
        let source = "- bar\n- baz\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            rootListItemsForest(in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        #expect(capture.fragment.wrapperKind == .list)
        #expect(capture.fragment.childKinds == [.listItem, .listItem])

        let target = "- foo\n- qux\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n- bar\n- baz\n- qux\n")
    }

    @Test("explicit direct list-item paste finds a target marker after a blank line")
    func explicitDirectListItemPasteFindsMarkerAfterBlankLine() throws {
        let source = "- bar\n- baz\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            rootListItemsForest(in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        let target = "\n- foo\n- qux\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "\n- foo\n- bar\n- baz\n- qux\n")
    }

    @Test("explicit list item paste accepts list item prefix whitespace")
    func explicitListItemPasteAcceptsListItemPrefixWhitespace() throws {
        let source = "- bar\n- baz\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            rootListItemsForest(in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )

        let target = "- foo\n- qux\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: " foo", in: target)

        let plan = try StructuralCSTPastePlanner.planSplice(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n- bar\n- baz\n- qux\n")
    }

    @Test("explicit list item paste refuses cursor inside item content")
    func explicitListItemPasteRefusesItemContentCursor() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n"
        )
        let target = "- foo\n  - one\n  - two\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "one", in: target)

        #expect(throws: StructuralCSTPasteRejection.invalidTarget) {
            _ = try StructuralCSTPastePlanner.planSplice(
                payload: capture.clipboardPayload,
                in: parsedTarget.tree,
                cursorByteOffset: TextSize(UInt32(cursorOffset)),
                after: true
            )
        }
    }

    @Test("explicit list item paste refuses root-list-block payload")
    func explicitListItemPasteRefusesRootListBlockPayload() throws {
        let source = "- bar\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstRootForest(in: parsedSource.tree, childKind: .list)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        #expect(capture.fragment.wrapperKind == .root)
        #expect(capture.fragment.childKinds == [.list])

        let target = "- foo\n  - one\n"
        let parsedTarget = try LiminalParser().parse(target)

        #expect(throws: StructuralCSTPasteRejection.unsupportedSource) {
            _ = try StructuralCSTPastePlanner.planSplice(
                payload: capture.clipboardPayload,
                in: parsedTarget.tree,
                cursorByteOffset: .zero,
                after: true
            )
        }
    }

    @Test("nested list paste creates child list in current list item")
    func nestedListPasteCreatesChildList() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n"
        )
        let target = "- foo\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - bar\n  - baz\n")
    }

    @Test("nested list paste accepts list item prefix whitespace")
    func nestedListPasteAcceptsListItemPrefixWhitespace() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n"
        )
        let target = "- foo\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: " foo", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - bar\n")
    }

    @Test("nested list paste refuses cursor inside item content")
    func nestedListPasteRefusesItemContentCursor() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n"
        )
        let target = "- foo\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "foo", in: target)

        #expect(throws: StructuralCSTPasteRejection.invalidTarget) {
            _ = try StructuralCSTPastePlanner.planNest(
                payload: capture.clipboardPayload,
                in: parsedTarget.tree,
                cursorByteOffset: TextSize(UInt32(cursorOffset)),
                after: true
            )
        }
    }

    @Test("nested root list paste creates a child list")
    func nestedRootListPasteCreatesChildList() throws {
        let source = "* bar\n* baz\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            firstRootForest(in: parsedSource.tree, childKind: .list)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        let target = "- foo\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  * bar\n  * baz\n")
    }

    @Test("nested list paste appends to current item's existing child list")
    func nestedListPasteAppendsToExistingChildList() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n    - quoz\n"
        )
        let target = "- foo\n  - bar\n  - baz\n    - quoz\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- baz", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - bar\n  - baz\n    - quoz\n    - bar\n    - baz\n      - quoz\n")
    }

    @Test("nested list paste normalizes to an existing child list marker")
    func nestedListPasteNormalizesExistingChildListMarker() throws {
        let capture = try childListCapture(
            from: "- source\n  * bar\n  * baz\n"
        )
        let target = "- foo\n  + one\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  + one\n  + bar\n  + baz\n")
    }

    @Test("nested list paste targets third-level current item")
    func nestedListPasteTargetsThirdLevelItem() throws {
        let capture = try childListCapture(
            from: "- source\n  - bar\n  - baz\n    - quoz\n"
        )
        let target = "- foo\n  - bar\n  - baz\n    - quoz\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- quoz", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - bar\n  - baz\n    - quoz\n      - bar\n      - baz\n        - quoz\n")
    }

    @Test("nested paragraph paste wraps paragraph as child list item")
    func nestedParagraphPasteWrapsParagraphAsChildListItem() throws {
        let source = "hello\n"
        let parsedSource = try LiminalParser().parse(source)
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsedSource.tree)
        )
        let capture = try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
        let target = "- foo\n"
        let parsedTarget = try LiminalParser().parse(target)
        let cursorOffset = try byteOffset(of: "- foo", in: target)

        let plan = try StructuralCSTPastePlanner.planNest(
            payload: capture.clipboardPayload,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(cursorOffset)),
            after: true
        )

        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- foo\n  - hello\n")
    }

    private func nestedBarFragment() throws -> StructuralCSTFragment {
        let source = """
        - foo
          - bar
            - bax
          - qux
        - zot
        """
        let parsed = try LiminalParser().parse(source)
        let offset = try byteOffset(of: "bar", in: source)
        let forest = try #require(
            listItemForest(containing: offset, in: parsed.tree)
        )
        return try StructuralCSTFragment.capture(forest)
    }

    private func childListCapture(
        from source: String
    ) throws -> StructuralCSTSelectionCapture {
        let parsed = try LiminalParser().parse(source)
        let forest = try #require(
            firstChildListForestInFirstListItem(in: parsed.tree)
        )
        return try StructuralCSTSelectionCapture.capture(
            forest: forest,
            source: source
        )
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

    private func firstRootForest(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        childKind expectedKind: LiminalKind
    ) -> LiminalForest? {
        tree.withRoot { root in
            for childIndex in 0..<root.childOrTokenCount {
                let childKind = root.green { $0.child(at: childIndex) }.kind
                guard childKind == expectedKind else { continue }
                return LiminalForest(
                    parent: root.makeHandle(),
                    anchorChildIndex: childIndex,
                    headChildIndex: childIndex
                )
            }
            return nil
        }
    }

    private func rootListItemsForest(
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        tree.withRoot { root in
            for rootIndex in 0..<root.childOrTokenCount {
                let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
                guard rootChildKind == .list else { continue }

                return root.withChildNode(atRawIndex: rootIndex) { list in
                    guard list.childOrTokenCount > 0 else { return nil }
                    return LiminalForest(
                        parent: list.makeHandle(),
                        anchorChildIndex: 0,
                        headChildIndex: list.childOrTokenCount - 1
                    )
                } ?? nil
            }
            return nil
        }
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
}
