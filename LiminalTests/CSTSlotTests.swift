import CambiumCore
import Testing
@testable import Liminal

@Suite("CSTSlot model")
struct CSTSlotTests {

    // MARK: - Inward selectors (parent = the selected node)

    @Test("prepend/append resolve inside the selected node")
    func inwardResolvesInsideNode() throws {
        let parsed = try LiminalParser().parse(CambiumSource("- one\n- two\n"))

        // Root's child 0 is the list; use it as the slot's container.
        let (prepend, append, listChildCount) = try parsed.tree.withRoot {
            root -> (CSTSlotAnchor, CSTSlotAnchor, UInt32) in
            try #require(root.withChildNode(atRawIndex: 0) { list in
                let node = CSTNodeAnchor(
                    path: list.liminalCSTPath,
                    fingerprint: NodeFingerprint(kind: list.kind, contentHash: list.greenHash)
                )
                return (
                    CSTSlotAnchor(node: node, selector: .prepend),
                    CSTSlotAnchor(node: node, selector: .append),
                    UInt32(list.childOrTokenCount)
                )
            })
        }

        guard case .strong(let prependSlot) = prepend.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong prepend"); return
        }
        #expect(prependSlot.insertionChildIndex == 0)
        #expect(prependSlot.parentHandle.withCursor { $0.kind } == .list)

        guard case .strong(let appendSlot) = append.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong append"); return
        }
        #expect(appendSlot.insertionChildIndex == listChildCount)
        #expect(appendSlot.parentHandle.withCursor { $0.kind } == .list)
    }

    // MARK: - Outward selectors (parent = the selected node's parent)

    @Test("before/after resolve beside the selected node in its parent")
    func outwardResolvesInParent() throws {
        let parsed = try LiminalParser().parse(CambiumSource("# Heading\n\nBody.\n"))

        // Root's child 0 is the heading; before/after target root.
        let (before, after) = try parsed.tree.withRoot {
            root -> (CSTSlotAnchor, CSTSlotAnchor) in
            try #require(root.withChildNode(atRawIndex: 0) { node in
                let anchor = CSTNodeAnchor(
                    path: node.liminalCSTPath,
                    fingerprint: NodeFingerprint(kind: node.kind, contentHash: node.greenHash)
                )
                return (
                    CSTSlotAnchor(node: anchor, selector: .before),
                    CSTSlotAnchor(node: anchor, selector: .after)
                )
            })
        }

        guard case .strong(let beforeSlot) = before.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong before"); return
        }
        #expect(beforeSlot.insertionChildIndex == 0)
        #expect(beforeSlot.parentHandle.withCursor { $0.kind } == .root)

        guard case .strong(let afterSlot) = after.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong after"); return
        }
        #expect(afterSlot.insertionChildIndex == 1)
        #expect(afterSlot.parentHandle.withCursor { $0.kind } == .root)
    }

    // MARK: - Root node edge cases

    @Test("inward selector on the root node targets the document")
    func inwardOnRootTargetsDocument() throws {
        let parsed = try LiminalParser().parse(CambiumSource("One.\n"))
        let anchor = parsed.tree.withRoot { root in
            CSTSlotAnchor(
                node: CSTNodeAnchor(
                    path: root.liminalCSTPath,
                    fingerprint: NodeFingerprint(kind: root.kind, contentHash: root.greenHash)
                ),
                selector: .prepend
            )
        }

        guard case .strong(let resolved) = anchor.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong"); return
        }
        #expect(resolved.insertionChildIndex == 0)
        #expect(resolved.parentHandle.withCursor { $0.kind } == .root)
    }

    @Test("outward selector on the root node is lost (no parent)")
    func outwardOnRootIsLost() throws {
        let parsed = try LiminalParser().parse(CambiumSource("One.\n"))
        let anchor = parsed.tree.withRoot { root in
            CSTSlotAnchor(
                node: CSTNodeAnchor(
                    path: root.liminalCSTPath,
                    fingerprint: NodeFingerprint(kind: root.kind, contentHash: root.greenHash)
                ),
                selector: .before
            )
        }
        #expect(anchor.resolve(in: parsed.rootSyntax) == .lost)
    }

    // MARK: - Resolution grading

    @Test("resolves weak when the node survives but its content changed")
    func weakOnContentChange() throws {
        let original = try LiminalParser().parse(CambiumSource("One.\n"))
        let edited = try LiminalParser().parse(CambiumSource("One changed.\n"))
        let anchor = try original.tree.withRoot { root -> CSTSlotAnchor in
            try #require(root.withChildNode(atRawIndex: 0) { node in
                CSTSlotAnchor(
                    node: CSTNodeAnchor(
                        path: node.liminalCSTPath,
                        fingerprint: NodeFingerprint(kind: node.kind, contentHash: node.greenHash)
                    ),
                    selector: .before
                )
            })
        }

        guard case .weak(let resolved) = anchor.resolve(in: edited.rootSyntax) else {
            Issue.record("expected .weak, got \(anchor.resolve(in: edited.rootSyntax))"); return
        }
        #expect(resolved.parentHandle.withCursor { $0.kind } == .root)
        #expect(resolved.insertionChildIndex == 0)
    }

    @Test("resolves lost when the node is deleted")
    func lostOnDeletion() throws {
        let original = try LiminalParser().parse(CambiumSource("One.\n"))
        let edited = try LiminalParser().parse(CambiumSource(""))
        let anchor = try original.tree.withRoot { root -> CSTSlotAnchor in
            try #require(root.withChildNode(atRawIndex: 0) { node in
                CSTSlotAnchor(
                    node: CSTNodeAnchor(
                        path: node.liminalCSTPath,
                        fingerprint: NodeFingerprint(kind: node.kind, contentHash: node.greenHash)
                    ),
                    selector: .append
                )
            })
        }
        #expect(anchor.resolve(in: edited.rootSyntax) == .lost)
    }

    @Test("resolves lost when the node's kind changes")
    func lostOnKindChange() throws {
        let original = try LiminalParser().parse(CambiumSource("One.\n"))       // paragraph
        let edited = try LiminalParser().parse(CambiumSource("# One\n"))         // atxHeading
        let anchor = try original.tree.withRoot { root -> CSTSlotAnchor in
            try #require(root.withChildNode(atRawIndex: 0) { node in
                CSTSlotAnchor(
                    node: CSTNodeAnchor(
                        path: node.liminalCSTPath,
                        fingerprint: NodeFingerprint(kind: node.kind, contentHash: node.greenHash)
                    ),
                    selector: .before
                )
            })
        }
        #expect(anchor.resolve(in: edited.rootSyntax) == .lost)
    }

    // MARK: - Framing-aware interior bounds

    @Test("inward slots on a payload wrapper land at the content, inside the framing")
    func inwardSkipsFramingToPayloadContent() throws {
        // "[text](url)": the linkDestination is "(url)" — the parens are
        // syntactic framing, the URL text is a (non-navigable) payload token.
        // prepend must land just after '(', append just before ')'.
        let source = "[text](url)\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let node = try #require(parsed.tree.withRoot { root in
            Self.findNodeAnchor(ofKind: .linkDestination, in: root)
        })

        let prepend = CSTSlotAnchor(node: node, selector: .prepend)
        let append = CSTSlotAnchor(node: node, selector: .append)

        guard case .strong(let prependSlot) = prepend.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong prepend"); return
        }
        guard case .strong(let appendSlot) = append.resolve(in: parsed.rootSyntax) else {
            Issue.record("expected .strong append"); return
        }
        // "[text](url)\n": '(' at byte 6, "url" at 7...9, ')' at 10.
        #expect(prependSlot.insertionByteOffset == TextSize(7))   // after '('
        #expect(appendSlot.insertionByteOffset == TextSize(10))   // before ')'
    }

    /// Depth-first search for the first node of `kind`, returning a stable
    /// anchor to it.
    private static func findNodeAnchor(
        ofKind kind: LiminalKind,
        in cursor: borrowing SyntaxNodeCursor<LiminalLanguage>
    ) -> CSTNodeAnchor? {
        if cursor.kind == kind {
            return CSTNodeAnchor(
                path: cursor.liminalCSTPath,
                fingerprint: NodeFingerprint(kind: cursor.kind, contentHash: cursor.greenHash)
            )
        }
        for i in 0..<cursor.childOrTokenCount {
            let found = cursor.withChildNode(atRawIndex: i) { child in
                findNodeAnchor(ofKind: kind, in: child)
            } ?? nil
            if let found { return found }
        }
        return nil
    }
}
