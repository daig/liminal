import CambiumCore
import Testing
@testable import Liminal

@Suite("CSTSlot data model")
struct CSTSlotTests {

    @Test("known slot roles expose stable raw identifiers")
    func knownRoleIdentifiers() {
        #expect(CSTSlotRole.rootDocumentItems.rawValue == "root.documentItems")
        #expect(CSTSlotRole.listItems.rawValue == "list.items")
        #expect(CSTSlotRole.blockQuoteDocumentItems.rawValue == "blockQuote.documentItems")

        let custom: CSTSlotRole = "custom.role"
        #expect(custom.rawValue == "custom.role")
        #expect(custom.description == "custom.role")
    }

    @Test("slot anchor records parent role and stable boundary child")
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
            role: .rootDocumentItems,
            boundary: .before(reference: child)
        )

        #expect(anchor.parent == parent)
        #expect(anchor.role == .rootDocumentItems)
        #expect(anchor.boundary == .before(reference: child))
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
                role: .rootDocumentItems,
                boundary: .before(reference: childAnchor)
            )
            let slot = CSTSlot(
                parentPath: rootPath,
                parentKind: root.kind,
                role: .rootDocumentItems,
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

        #expect(resolved.slot.role == .rootDocumentItems)
        #expect(resolved.slot.boundary == .beforeChild(index: 0))
        #expect(resolved.insertionChildIndex == 0)
        #expect(resolved.insertionByteOffset == .zero)
        #expect(resolved.leftNeighbor == nil)
        #expect(resolved.rightNeighbor?.kind == .atxHeading)
        #expect(CSTSlotResolution.strong(resolved) == .strong(resolved))
    }
}
