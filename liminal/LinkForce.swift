import RealityKit

/// A force that maintains distances between connected nodes in a force-directed graph.
///
/// This implementation adapts the original LinkForce to the ForceEffectProtocol,
/// using a constant stiffness of 0.5 as specified. It applies forces to nodes
/// to achieve a target distance between linked pairs.
///
/// Complexity: O(e), where e is the number of links.
struct LinkForce: ForceEffectProtocol {
    // Required by ForceEffectProtocol
    var parameterTypes: PhysicsBodyParameterTypes { [.position] }
    var forceMode: ForceMode { .velocity }

    // Properties mirroring the original LinkForce
    private let links: [EdgeID]
    private let calculatedStiffness: [Float]
    private let calculatedLength: [Float]
    private let calculatedBias: [Float]
    private let iterationsPerTick: UInt

    /// Initializes the LinkForce with a list of edges.
    ///
    /// - Parameters:
    ///   - links: Array of edges defining node connections.
    ///   - originalLength: Desired distance between nodes (default: 30).
    ///   - iterationsPerTick: Number of force application iterations (default: 1).
    init(
        links: [EdgeID],
        originalLength: Float = 0.5,
        iterationsPerTick: UInt = 1
    ) {
        self.links = links
        self.iterationsPerTick = iterationsPerTick

        // Simplify LinkStiffness to constant 0.5
        self.calculatedStiffness = Array(repeating: 0.5, count: links.count)
        self.calculatedLength = Array(repeating: originalLength, count: links.count)

        // Compute bias based on node degrees using LinkLookup
        let linkLookup = LinkLookup(links: links)
        self.calculatedBias = links.map { link in
            let sourceCount = Float(linkLookup.count[link.source, default: 0])
            let targetCount = Float(linkLookup.count[link.target, default: 0])
            let total = sourceCount + targetCount
            return total > 0 ? sourceCount / total : 0.5
        }
    }

    /// Updates node forces based on current positions to maintain link distances.
    func update(parameters: inout ForceEffectParameters) {
        guard let positions = parameters.positions, !links.isEmpty else { return }

        for _ in 0..<iterationsPerTick {
            for i in links.indices {
                let link = links[i]
                let sourceIndex = link.source.id
                let targetIndex = link.target.id

                // Ensure indices are valid
                guard sourceIndex < parameters.physicsBodyCount,
                      targetIndex < parameters.physicsBodyCount else {
                    continue
                }

                // Compute displacement vector
                let sourcePos = positions[sourceIndex]
                let targetPos = positions[targetIndex]
                var vec = targetPos - sourcePos

                // Compute current length and adjustment
                let length = vec.length()
                guard length > 0 else { continue } // Avoid division by zero

                let stiffness = calculatedStiffness[i]
                let targetLength = calculatedLength[i]
                let bias = calculatedBias[i]

                // Force magnitude: proportional to deviation from target length
                let l = (length - targetLength) / length * stiffness
                vec *= l

                // Apply forces: target moves opposite, source moves along vec
                parameters.setForce(-vec * bias, index: targetIndex)
                parameters.setForce(vec * (1 - bias), index: sourceIndex)
            }
        }
    }
}
