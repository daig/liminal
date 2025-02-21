import Foundation

struct GraphData {
    let nodeCount: Int
    let edges: [EdgeID] // Directed edges
    let names: [String]
    let bodies: [String] // Markdown content for each node
    
    init(nodeCount: Int, edges: [EdgeID], names: [String]? = nil, bodies: [String]? = nil) {
        self.nodeCount = nodeCount
        self.edges = edges
        if let providedNames = names, providedNames.count == nodeCount {
            self.names = providedNames
        } else {
            self.names = (0..<nodeCount).map { "N\($0 + 1)" }
        }
        if let providedBodies = bodies, providedBodies.count == nodeCount {
            self.bodies = providedBodies
        } else {
            self.bodies = (0..<nodeCount).map { _ in "" } // Default empty content
        }
    }
    
    static func ringGraph(nodeCount: Int) -> GraphData {
        let edges = (0..<nodeCount).map { i in
            let nextNode = (i + 1) % nodeCount
            return EdgeID(source: NodeID(id: i), target: NodeID(id: nextNode))
        }
        return GraphData(nodeCount: nodeCount, edges: edges)
    }
    
    static func smallWorldGraph(nodeCount: Int, extraEdgeCount: Int) -> GraphData {
        var edges = (0..<nodeCount).map { i in
            let nextNode = (i + 1) % nodeCount
            return EdgeID(source: NodeID(id: i), target: NodeID(id: nextNode))
        }
        
        var edgeSet = Set(edges.map { Set([$0.source.id, $0.target.id]) }) // For uniqueness check
        for _ in 0..<extraEdgeCount {
            var newEdge: EdgeID
            var undirectedSet: Set<Int>
            repeat {
                let node1 = Int.random(in: 0..<nodeCount)
                let node2 = Int.random(in: 0..<nodeCount)
                if node1 != node2 {
                    newEdge = EdgeID(source: NodeID(id: node1), target: NodeID(id: node2))
                    undirectedSet = Set([node1, node2])
                } else {
                    newEdge = EdgeID(source: NodeID(id: 0), target: NodeID(id: 0)) // Temporary invalid edge
                    undirectedSet = Set<Int>()
                }
            } while edgeSet.contains(undirectedSet) || undirectedSet.count != 2
            edges.append(newEdge)
            edgeSet.insert(undirectedSet)
        }
        return GraphData(nodeCount: nodeCount, edges: edges)
    }
}
