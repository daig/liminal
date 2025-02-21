import Foundation

/// Handles the layout of nodes in a graph.
struct NodeLayout {
    /// Calculates node positions in a circular layout.
    /// - Parameters:
    ///   - graphData: The graph data containing the number of nodes and edges (currently only nodeCount is used).
    ///   - radius: The radius of the circle.
    ///   - center: The center point of the circle in 3D space.
    /// - Returns: An array of tuples, each containing a node index and its position.
    static func circleLayout(graphData: GraphData, radius: Float, center: SIMD3<Float>) -> [(Int, SIMD3<Float>)] {
        let nodeCount = graphData.nodeCount
        let angleStep = 2 * Float.pi / Float(nodeCount)
        return (0..<nodeCount).map { i in
            let angle = angleStep * Float(i)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            return (i, SIMD3<Float>(x, y, center.z))
        }
    }
}
