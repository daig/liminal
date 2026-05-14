import CambiumCore
import CambiumSelection
import Testing
@testable import Liminal

@Suite("LiminalForest smoke")
struct LiminalForestSmokeTests {

    @Test("forest at root child wraps a navigable kind")
    func forestAtRootChildIsNavigable() throws {
        let parser = LiminalParser()
        let parsed = try parser.parse("# Hello\n\nA paragraph.\n")
        let tree = parsed.tree

        // The first navigable thing under root is a paragraph or heading.
        let f = try #require(LiminalForest.containing(.zero, in: tree))
        #expect(f.parent.identity == tree.rootHandle().identity)
        let kindAtAnchor = tree.withRoot { root in
            root.green { $0.child(at: f.anchorChildIndex) }.kind
        }
        #expect(LiminalCSTPolicy.isNavigable(kindAtAnchor))
    }

    @Test("slidForward at root level moves between navigable document items")
    func slidForwardCrossesNavigableSiblings() throws {
        let parser = LiminalParser()
        let parsed = try parser.parse("""
        # Heading

        First paragraph.

        Second paragraph.
        """)
        let tree = parsed.tree

        let f = try #require(LiminalForest.containing(.zero, in: tree))
        // Walk forward until we run out, collecting kinds.
        var current: LiminalForest = f
        var visitedKinds: [LiminalKind] = []
        while true {
            let kind = tree.withRoot { root in
                root.green { $0.child(at: current.anchorChildIndex) }.kind
            }
            visitedKinds.append(kind)
            if let next = current.slidForward() {
                current = next
            } else {
                break
            }
        }
        // We should have visited at least the heading and the two paragraphs.
        #expect(visitedKinds.contains(.atxHeading))
        #expect(visitedKinds.contains(.paragraph))
        // No non-navigable kinds end up as anchor endpoints.
        for kind in visitedKinds {
            #expect(
                LiminalCSTPolicy.isNavigable(kind),
                "Encountered non-navigable kind \(kind) as endpoint"
            )
        }
    }

    @Test("firstChildForest refuses to descend into an opaque fenced code block")
    func opaqueCodeBlockBlocksDescent() throws {
        let parser = LiminalParser()
        let parsed = try parser.parse("""
        ```swift
        let x = 1
        ```
        """)
        let tree = parsed.tree

        // Find the fenced code block as a singleton forest.
        let f = try #require(LiminalForest.containing(.zero, in: tree))
        let kind = tree.withRoot { root in
            root.green { $0.child(at: f.anchorChildIndex) }.kind
        }
        #expect(kind == .fencedCodeBlock)
        // Cannot descend: childPolicy(.fencedCodeBlock) == .opaque
        #expect(f.firstChildForest() == nil)
    }

    @Test("anchor captured against unchanged tree round-trips strong")
    func anchorRoundTripsStrong() throws {
        let parser = LiminalParser()
        let parsed = try parser.parse("First paragraph.\n\nSecond paragraph.\n")
        let tree = parsed.tree

        let f = try #require(LiminalForest.containing(.zero, in: tree))
        let anchor = LiminalForestAnchor.from(f)
        let resolution = anchor.resolve(in: tree)
        guard case .strong(let restored) = resolution else {
            Issue.record("Expected .strong, got \(resolution)")
            return
        }
        #expect(restored.anchorChildIndex == f.anchorChildIndex)
        #expect(restored.headChildIndex == f.headChildIndex)
    }

    @Test("anchor survives intra-paragraph edit as weak when block structure stays")
    func anchorReportsWeakAfterIntraSubtreeEdit() throws {
        let parser = LiminalParser()
        let parsed1 = try parser.parse("First paragraph.\n")
        let firstTree = parsed1.tree

        // containing(.zero, in:) descends to the smallest navigable node
        // covering offset 0 — for a markdown paragraph that's the inline
        // text token inside the paragraph's inlineContent. Capture an
        // anchor at that depth.
        let f = try #require(LiminalForest.containing(.zero, in: firstTree))
        let originalParentKind = f.parent.withCursor { $0.kind }
        let anchor = LiminalForestAnchor.from(f)

        // Reparse with edited content (paragraph still exists, with different text).
        let parsed2 = try parser.parse("First paragraph, edited.\n")
        let newTree = parsed2.tree

        let resolution = anchor.resolve(in: newTree)
        switch resolution {
        case .weak(let forest):
            // The parent at the same path in the new tree should be a
            // node of the same kind — the structural role is preserved
            // even though the byte content changed.
            let newParentKind = forest.parent.withCursor { $0.kind }
            #expect(newParentKind == originalParentKind)
            #expect(forest.anchorChildIndex == f.anchorChildIndex)
        case .strong:
            // Acceptable if the captured subtree happens to share a
            // structural hash with the post-edit subtree — extremely
            // unlikely with different inline text. Treat as a
            // tighter-than-expected pass.
            break
        case .recovered, .lost:
            Issue.record("Expected .weak/.strong after intra-block edit, got \(resolution)")
        }
    }
}
