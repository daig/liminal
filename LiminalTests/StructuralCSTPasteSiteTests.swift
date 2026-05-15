import CambiumCore
import Testing
@testable import Liminal

@Suite("Structural CST paste site")
struct StructuralCSTPasteSiteTests {
    @Test("exact cursor captures the smallest cursor focus without climbing")
    func exactCursorCapturesSmallestFocusWithoutClimbing() throws {
        let parsed = try LiminalParser().parse("Hello.\n")
        let resolved = try #require(
            StructuralCSTPasteSiteResolver.resolve(
                scope: .exactCursor,
                in: parsed.tree,
                cursorByteOffset: .zero
            )
        )

        let focus = try #require(resolved.site.originFocus)
        #expect(resolved.site.scope == .exactCursor)
        #expect(focus.parentKind == .inlineContent)
        #expect(focus.childKind == .inlineText)
        #expect(focus.childPath == focus.parentPath.appending(focus.childIndex))
        #expect(resolved.originForest != nil)
        #expect(resolved.exactTargetForest != nil)

        let exact = try exactTarget(from: resolved.site)
        #expect(exact == focus)
    }

    @Test("exact cursor returns nil for an empty root")
    func exactCursorReturnsNilForEmptyRoot() throws {
        let parsed = try LiminalParser().parse("")
        let resolved = StructuralCSTPasteSiteResolver.resolve(
            scope: .exactCursor,
            in: parsed.tree,
            cursorByteOffset: .zero
        )
        if resolved != nil {
            Issue.record("expected exact cursor resolution to fail for an empty root")
        }
    }

    @Test("root projection in an empty document targets root without a reference child")
    func rootProjectionInEmptyDocumentTargetsRootWithoutReferenceChild() throws {
        let parsed = try LiminalParser().parse("")
        let resolved = try #require(
            StructuralCSTPasteSiteResolver.resolve(
                scope: .rootProjectedFromCursor,
                in: parsed.tree,
                cursorByteOffset: .zero
            )
        )
        let projected = try projectedContainer(from: resolved.site)

        #expect(resolved.site.scope == .rootProjectedFromCursor)
        #expect(resolved.site.originFocus == nil)
        #expect(resolved.originForest == nil)
        #expect(resolved.exactTargetForest == nil)
        #expect(projected.containerPath == [])
        #expect(projected.containerKind == .root)
        #expect(projected.referenceChildIndex == nil)
        #expect(projected.referenceChildKind == nil)
        #expect(projected.referenceChildPath == nil)
        #expect(resolved.containerHandle.withCursor { $0.kind } == .root)
    }

    @Test("root projection from nested list content references the top-level list")
    func rootProjectionFromNestedListContentReferencesTopLevelList() throws {
        let source = """
        Intro.

        - foo
          - bar
        """
        let parsed = try LiminalParser().parse(source)
        let listIndex = try #require(
            rootChildIndex(in: parsed.tree, kind: .list)
        )
        let cursorOffset = try byteOffset(of: "bar", in: source)

        let resolved = try #require(
            StructuralCSTPasteSiteResolver.resolve(
                scope: .rootProjectedFromCursor,
                in: parsed.tree,
                cursorByteOffset: TextSize(UInt32(cursorOffset))
            )
        )
        let projected = try projectedContainer(from: resolved.site)

        #expect(resolved.site.originFocus != nil)
        #expect(projected.containerPath == [])
        #expect(projected.containerKind == .root)
        #expect(projected.referenceChildIndex == UInt32(listIndex))
        #expect(projected.referenceChildKind == .list)
        #expect(projected.referenceChildPath == [UInt32(listIndex)])
    }

    @Test("root projection at EOF references the last root child")
    func rootProjectionAtEOFReferencesLastRootChild() throws {
        let source = "One.\n\nTwo.\n"
        let parsed = try LiminalParser().parse(source)
        let last = try #require(lastRootChild(in: parsed.tree))

        let resolved = try #require(
            StructuralCSTPasteSiteResolver.resolve(
                scope: .rootProjectedFromCursor,
                in: parsed.tree,
                cursorByteOffset: TextSize(UInt32(source.utf8.count))
            )
        )
        let projected = try projectedContainer(from: resolved.site)

        #expect(projected.referenceChildIndex == UInt32(last.index))
        #expect(projected.referenceChildKind == last.kind)
        #expect(projected.referenceChildPath == [UInt32(last.index)])
    }

    @Test("root projection after a blank line at a list marker chooses the list")
    func rootProjectionAfterBlankLineAtListMarkerChoosesList() throws {
        let source = "before\n\n- foo\n- baz\n"
        let parsed = try LiminalParser().parse(source)
        let listIndex = try #require(
            rootChildIndex(in: parsed.tree, kind: .list)
        )
        let cursorOffset = try byteOffset(of: "- foo", in: source)

        let resolved = try #require(
            StructuralCSTPasteSiteResolver.resolve(
                scope: .rootProjectedFromCursor,
                in: parsed.tree,
                cursorByteOffset: TextSize(UInt32(cursorOffset))
            )
        )
        let projected = try projectedContainer(from: resolved.site)

        #expect(projected.referenceChildIndex == UInt32(listIndex))
        #expect(projected.referenceChildKind == .list)
        #expect(projected.referenceChildPath == [UInt32(listIndex)])
    }

    private func exactTarget(
        from site: StructuralCSTPasteSite
    ) throws -> StructuralCSTPasteCursorFocus {
        var result: StructuralCSTPasteCursorFocus?
        if case .exact(let focus) = site.target {
            result = focus
        }
        return try #require(result)
    }

    private func projectedContainer(
        from site: StructuralCSTPasteSite
    ) throws -> StructuralCSTPasteProjectedContainer {
        var result: StructuralCSTPasteProjectedContainer?
        if case .projectedContainer(let projected) = site.target {
            result = projected
        }
        return try #require(result)
    }

    private func rootChildIndex(
        in tree: SharedSyntaxTree<LiminalLanguage>,
        kind: LiminalKind
    ) -> Int? {
        tree.withRoot { root in
            for index in 0..<root.childOrTokenCount {
                let childKind = root.green { green in
                    green.child(at: index)
                }.kind
                if childKind == kind {
                    return index
                }
            }
            return nil
        }
    }

    private func lastRootChild(
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> (index: Int, kind: LiminalKind)? {
        tree.withRoot { root in
            guard root.childOrTokenCount > 0 else { return nil }
            let index = root.childOrTokenCount - 1
            let kind = root.green { green in
                green.child(at: index)
            }.kind
            return (index, kind)
        }
    }

    private func byteOffset(of needle: String, in source: String) throws -> Int {
        let range = try #require(source.range(of: needle))
        return source.utf8.distance(from: source.startIndex, to: range.lowerBound)
    }
}
