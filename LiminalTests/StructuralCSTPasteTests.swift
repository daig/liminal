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

        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsed.tree,
            cursorByteOffset: .zero,
            after: true
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "\nOne.\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: source
        )
        #expect(newSource == "One.\n\nOne.\n\nTwo.\n")
    }

    @Test("nested list item pasted into top-level list rebases relative indent")
    func nestedListItemPastedAtTopLevelRebasesIndent() throws {
        let fragment = try nestedBarFragment()
        let target = "- zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "- bar\n  - bax\n")
    }

    @Test("nested list item pasted into nested list preserves nested base indent")
    func nestedListItemPastedIntoNestedListKeepsIndent() throws {
        let fragment = try nestedBarFragment()
        let target = """
        - foo
          - qux
        """
        let parsedTarget = try LiminalParser().parse(target)
        let offset = try byteOffset(of: "qux", in: target)
        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(offset)),
            after: false
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "  - bar\n    - bax\n")
    }

    @Test("unordered list paste normalizes only the top-level marker")
    func unorderedListItemPasteNormalizesTargetMarker() throws {
        let source = "* foo\n  + bar\n"
        let parsedSource = try LiminalParser().parse(source)
        let sourceOffset = try byteOffset(of: "foo", in: source)
        let forest = try #require(
            listItemForest(containing: sourceOffset, in: parsedSource.tree)
        )
        let fragment = try StructuralCSTFragment.capture(forest)

        let target = "- zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "- foo\n  + bar\n")
    }

    @Test("EOF list item pasted before a sibling gets a boundary newline")
    func eofListItemPastedBeforeSiblingGetsBoundaryNewline() throws {
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
        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: TextSize(UInt32(targetOffset)),
            after: false
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "- foo\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "- one\n- foo\n- two\n")
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
        let plan = try #require(try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: false
        ))

        #expect(String(decoding: plan.edit.replacementUTF8, as: UTF8.self) == "One.\n\n")
        let newSource = try LiminalEditorSession.applyingEdits(
            [plan.edit],
            to: target
        )
        #expect(newSource == "One.\n\nTwo.\n")
    }

    @Test("unordered list fragment refuses ordered-list target")
    func unorderedIntoOrderedListRefuses() throws {
        let fragment = try nestedBarFragment()
        let target = "1. zot\n"
        let parsedTarget = try LiminalParser().parse(target)
        let plan = try StructuralCSTPastePlanner.plan(
            fragment: fragment,
            in: parsedTarget.tree,
            cursorByteOffset: .zero,
            after: true
        )
        if case .some = plan {
            Issue.record("unordered fragment should refuse ordered-list target")
        }
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

    private func byteOffset(of needle: String, in source: String) throws -> Int {
        let range = try #require(source.range(of: needle))
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
    }
}
