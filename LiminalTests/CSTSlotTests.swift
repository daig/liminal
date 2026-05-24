import CambiumCore
import Testing
@testable import Liminal

@Suite("CSTSlot data model")
struct CSTSlotTests {

    @Test("slot anchor records parent and stable boundary child")
    func slotAnchorRecordsBoundaryChild() {
        let parent = CSTNodeAnchor(
            path: [],
            fingerprint: NodeFingerprint(
                kind: .root,
                contentHash: ContentHash(low64: 1, high64: 2)
            )
        )
        let child = CSTSlotChildAnchor(
            path: [0],
            indexInParent: 0,
            fingerprint: NodeFingerprint(
                kind: .paragraph,
                contentHash: ContentHash(low64: 3, high64: 4)
            )
        )
        let anchor = CSTSlotAnchor(
            parent: parent,
            boundary: .before(reference: child)
        )

        #expect(anchor.parent == parent)
        #expect(anchor.boundary == .before(reference: child))
    }

    @Test("list splice slot is a list parent plus child boundary")
    func listSpliceSlotUsesParentAndBoundaryOnly() {
        let slot = CSTSlot(
            parentPath: [0],
            parentKind: .list,
            boundary: .afterChild(index: 0)
        )
        let parent = CSTNodeAnchor(
            path: [0],
            fingerprint: NodeFingerprint(
                kind: .list,
                contentHash: ContentHash(low64: 1, high64: 2)
            )
        )
        let listItem = CSTSlotChildAnchor(
            path: [0, 0],
            indexInParent: 0,
            fingerprint: NodeFingerprint(
                kind: .listItem,
                contentHash: ContentHash(low64: 3, high64: 4)
            )
        )
        let anchor = CSTSlotAnchor(
            parent: parent,
            boundary: .after(reference: listItem)
        )

        #expect(slot.parentPath == [0])
        #expect(slot.parentKind == .list)
        #expect(slot.boundary == .afterChild(index: 0))
        #expect(anchor.parent == parent)
        #expect(anchor.boundary == .after(reference: listItem))
    }

    @Test("resolved slot carries execution metadata without planning paste")
    func resolvedSlotCarriesExecutionMetadata() throws {
        let parser = LiminalParser()
        let parsed = try parser.parse(CambiumSource("""
        # Heading

        Body paragraph.
        """))

        let resolved = parsed.tree.withRoot { root -> ResolvedCSTSlot in
            let rootPath = root.liminalCSTPath
            let parentAnchor = CSTNodeAnchor(
                path: rootPath,
                fingerprint: NodeFingerprint(
                    kind: root.kind,
                    contentHash: root.greenHash
                )
            )
            let childFingerprint = root.green { green in
                let child = green.child(at: 0)
                return NodeFingerprint(
                    kind: child.kind,
                    contentHash: child.contentHash
                )
            }
            let childAnchor = CSTSlotChildAnchor(
                path: rootPath.appending(0),
                indexInParent: 0,
                fingerprint: childFingerprint
            )
            let anchor = CSTSlotAnchor(
                parent: parentAnchor,
                boundary: .before(reference: childAnchor)
            )
            let slot = CSTSlot(
                parentPath: rootPath,
                parentKind: root.kind,
                boundary: .beforeChild(index: 0)
            )
            let childRange = root.childTextRange(at: 0)
            let rightNeighbor = CSTSlotNeighbor(
                path: rootPath.appending(0),
                indexInParent: 0,
                kind: childFingerprint.kind,
                textRange: childRange,
                fingerprint: childFingerprint
            )

            return ResolvedCSTSlot(
                slot: slot,
                anchor: anchor,
                parentHandle: root.makeHandle(),
                insertionChildIndex: 0,
                insertionByteOffset: childRange.start,
                leftNeighbor: nil,
                rightNeighbor: rightNeighbor
            )
        }

        #expect(resolved.slot.parentKind == .root)
        #expect(resolved.slot.boundary == .beforeChild(index: 0))
        #expect(resolved.insertionChildIndex == 0)
        #expect(resolved.insertionByteOffset == .zero)
        #expect(resolved.leftNeighbor == nil)
        #expect(resolved.rightNeighbor?.kind == .atxHeading)
        #expect(CSTSlotResolution.strong(resolved) == .strong(resolved))
    }
}
