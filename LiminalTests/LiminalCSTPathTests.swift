import CambiumCore
import Testing
@testable import Liminal

@Suite("Liminal CST path")
struct LiminalCSTPathTests {
    @Test("path relationships distinguish root ancestors descendants and siblings")
    func pathRelationships() {
        let root: LiminalCSTPath = []
        let branch: LiminalCSTPath = [1]
        let descendant: LiminalCSTPath = [1, 2, 3]
        let sibling: LiminalCSTPath = [1, 4]
        let unrelated: LiminalCSTPath = [2]

        #expect(root.isRoot)
        #expect(root.depth == 0)
        #expect(root.isAncestor(of: root))
        #expect(root.isAncestor(of: descendant))
        #expect(branch.isProperAncestor(of: descendant))
        #expect(descendant.isDescendant(of: branch))
        #expect(descendant.isProperDescendant(of: branch))
        #expect(!branch.isProperAncestor(of: branch))
        #expect(!sibling.isAncestor(of: descendant))
        #expect(!branch.isAncestor(of: unrelated))
        #expect(descendant.droppingLast() == [1, 2])
        #expect(root.droppingLast() == nil)
    }

    @Test("common ancestor covers equality ancestry and sibling branches")
    func commonAncestor() {
        let path: LiminalCSTPath = [1, 2, 3]
        #expect(path.commonAncestor(with: path) == path)
        #expect(path.commonAncestor(with: [1, 2]) == [1, 2])
        #expect(path.commonAncestor(with: [1, 2, 4, 0]) == [1, 2])
        #expect(path.commonAncestor(with: [9, 0]) == [])
    }

    @Test("relative path and projection are prefix based")
    func relativePathAndProjection() {
        let root: LiminalCSTPath = []
        let container: LiminalCSTPath = [1]
        let descendant: LiminalCSTPath = [1, 0, 2]
        let sibling: LiminalCSTPath = [2, 0]

        let expectedRelative: SyntaxNodePath = [0, 2]
        #expect(descendant.relativePath(from: container) == expectedRelative)
        #expect(descendant.relativePath(from: root) == [1, 0, 2])
        #expect(descendant.relativePath(from: sibling) == nil)

        #expect(root.projectedChildIndex(containing: descendant) == 1)
        #expect(container.projectedChildIndex(containing: descendant) == 0)
        #expect(descendant.projectedChildIndex(containing: descendant) == nil)
        #expect(sibling.projectedChildIndex(containing: descendant) == nil)
    }

    @Test("route records movement through the lowest common ancestor")
    func route() {
        let source: LiminalCSTPath = [1, 2, 3]
        let destination: LiminalCSTPath = [1, 4, 0]
        let route = source.route(to: destination)

        #expect(route.source == source)
        #expect(route.destination == destination)
        #expect(route.commonAncestor == [1])
        #expect(route.stepsUp == 2)
        #expect(route.stepsDown == [4, 0])

        let descendantRoute = source.route(to: [1, 2, 3, 5])
        #expect(descendantRoute.commonAncestor == source)
        #expect(descendantRoute.stepsUp == 0)
        #expect(descendantRoute.stepsDown == [5])

        let sameRoute = source.route(to: source)
        #expect(sameRoute.commonAncestor == source)
        #expect(sameRoute.stepsUp == 0)
        #expect(sameRoute.stepsDown.isEmpty)
    }

    @Test("live cursor and forest paths match Cambium full child-index paths")
    func liveCursorAndForestPaths() throws {
        let parsed = try LiminalParser().parse("""
        One.

        - two
          - three
        """)
        let tree = parsed.tree

        let rootPath = tree.withRoot { root in
            root.liminalCSTPath
        }
        #expect(rootPath == [])

        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: tree)
        )
        #expect(forest.parentCSTPath == rootPath)
        #expect(forest.anchorCSTPath == rootPath.appending(UInt32(forest.anchorChildIndex)))
        #expect(forest.headCSTPath == forest.anchorCSTPath)
        #expect(forest.firstCSTPath == forest.anchorCSTPath)
        #expect(forest.lastCSTPath == forest.anchorCSTPath)

        let anchorPath = forest.anchorCSTPath
        let anchorKind = forest.parent.withCursor { parent in
            parent.green { green in
                green.child(at: forest.anchorChildIndex)
            }.kind
        }
        let resolvedKind = tree.withRoot { root in
            root.withDescendant(atPath: anchorPath.rawValue) { descendant in
                descendant.kind
            }
        }
        #expect(resolvedKind == anchorKind)
    }
}
