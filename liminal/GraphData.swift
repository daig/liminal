import Foundation

/// Represents the data structure for a graph, including the number of nodes, edges, and node names.
struct GraphData {
    let nodeCount: Int
    let edges: Set<Set<Int>>
    let names: [String] // Array of short names for each node
    
    /// Initializes a GraphData instance with the given node count, edges, and optional names.
    init(nodeCount: Int, edges: Set<Set<Int>>, names: [String]? = nil) {
        self.nodeCount = nodeCount
        self.edges = edges
        // If names aren't provided, generate default ones like "N1", "N2", etc.
        if let providedNames = names, providedNames.count == nodeCount {
            self.names = providedNames
        } else {
            self.names = (0..<nodeCount).map { "N\($0 + 1)" }
        }
    }
    
    /// Generates a ring graph where each node is connected to its immediate neighbors in a circular fashion.
    /// - Parameter nodeCount: The number of nodes in the graph.
    /// - Returns: A GraphData instance representing the ring graph.
    static func ringGraph(nodeCount: Int) -> GraphData {
        let edges = generateRingEdges(nodeCount: nodeCount)
        return GraphData(nodeCount: nodeCount, edges: edges)
    }
    
    /// Generates a simple small-world network by starting with a ring graph and adding extra random edges.
    /// - Parameters:
    ///   - nodeCount: The number of nodes in the graph.
    ///   - extraEdgeCount: The number of additional random edges to add.
    /// - Returns: A GraphData instance representing the small-world graph.
    static func smallWorldGraph(nodeCount: Int, extraEdgeCount: Int) -> GraphData {
        var edges = generateRingEdges(nodeCount: nodeCount)
        for _ in 0..<extraEdgeCount {
            var newEdge: Set<Int>
            repeat {
                let node1 = Int.random(in: 0..<nodeCount)
                let node2 = Int.random(in: 0..<nodeCount)
                if node1 != node2 {
                    newEdge = Set([node1, node2])
                } else {
                    newEdge = Set<Int>()
                }
            } while edges.contains(newEdge) || newEdge.count != 2
            edges.insert(newEdge)
        }
        return GraphData(nodeCount: nodeCount, edges: edges)
    }
    
    /// Generates edges for a ring graph.
    /// - Parameter nodeCount: The number of nodes in the graph.
    /// - Returns: A set of edges, where each edge is a set of two node indices.
    private static func generateRingEdges(nodeCount: Int) -> Set<Set<Int>> {
        var edges = Set<Set<Int>>()
        for i in 0..<nodeCount {
            let nextNode = (i + 1) % nodeCount
            edges.insert(Set([i, nextNode]))
        }
        return edges
    }
}
