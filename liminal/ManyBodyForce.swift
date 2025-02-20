import RealityKit
import SwiftUI

/// Delegate for KDTree to track mass and center-of-mass properties.
struct MassDelegate: KDTreeDelegate {
    let massProvider: (NodeID) -> Float
    var accumulatedMass: Float = 0
    var accumulatedMassWeightedPositions: SIMD3<Float> = .zero
    
    init(massProvider: @escaping (NodeID) -> Float) {
        self.massProvider = massProvider
    }
    
    mutating func didAddNode(_ node: NodeID, at position: SIMD3<Float>) {
        let mass = massProvider(node)
        accumulatedMass += mass
        accumulatedMassWeightedPositions += position * mass
    }
    
    mutating func didRemoveNode(_ node: NodeID, at position: SIMD3<Float>) {
        let mass = massProvider(node)
        accumulatedMass -= mass
        accumulatedMassWeightedPositions -= position * mass
    }
    
    func spawn() -> Self {
        MassDelegate(massProvider: massProvider)
    }
}

/// A many-body force effect that applies repulsive or attractive forces between all nodes.
struct ManyBodyForce: ForceEffectProtocol {
    // Required properties for ForceEffectProtocol
    var parameterTypes: PhysicsBodyParameterTypes { [.position, .mass] }
    var forceMode: ForceMode { .force }
    
    // Custom properties
    let strength: Float    // Negative for repulsion, positive for attraction
    let theta: Float      // Barnes-Hut approximation threshold
    let distanceMin: Float // Minimum distance to prevent singularities
    let distanceMax: Float // Maximum distance for force application
    
    /// Initializes the many-body force with customizable parameters.
    init(
        strength: Float = -30,      // Default: repulsion
        theta: Float = 0.9,         // Default theta for Barnes-Hut
        distanceMin: Float = 1,     // Avoid division-by-zero
        distanceMax: Float = Float.greatestFiniteMagnitude // Apply force over all distances by default
    ) {
        self.strength = strength
        self.theta = theta
        self.distanceMin = distanceMin
        self.distanceMax = distanceMax
    }
    
    /// Updates the forces applied to each physics body.
    func update(parameters: inout ForceEffectParameters) {
        guard let positions = parameters.positions,
              let masses = parameters.masses else { return }
        let N = parameters.physicsBodyCount
        
        // Precompute squared values for efficiency
        let theta2 = theta * theta
        let distanceMin2 = distanceMin * distanceMin
        let distanceMax2 = distanceMax * distanceMax
        
        // Build the KDTree with current positions and masses
        let massProvider: (NodeID) -> Float = { index in masses[index.id] }
        let rootDelegate = MassDelegate(massProvider: massProvider)
        let coveringBox = KDBox.cover(of: positions, count: parameters.physicsBodyCount)
        var tree = BufferedKDTree<MassDelegate>(
            rootBox: coveringBox,
            nodeCapacity: N,
            rootDelegate: rootDelegate
        )
        for i in 0..<N {
            tree.add(nodeIndex: NodeID(id: i), at: positions[i])
        }
        
        // Compute force for each body
        for i in 0..<N {
            let pos = positions[i]
            var f: SIMD3<Float> = .zero
            
            tree.visit { t in
                guard t.delegate.accumulatedMass > 0 else { return false }
                
                let centroid = t.delegate.accumulatedMassWeightedPositions / t.delegate.accumulatedMass
                let vec = centroid - pos
                let boxWidth = (t.box.p1 - t.box.p0)[0] // Assumes cubic boxes
                var distanceSquared = vec.lengthSquared()
                
                // Prevent division by zero
                if distanceSquared < 1e-7 {
                    distanceSquared = 1e-7
                }
                
                let farEnough = (distanceSquared * theta2) > (boxWidth * boxWidth)
                
                // Clamp distance to minimum
                if distanceSquared < distanceMin2 {
                    distanceSquared = distanceMin2
                }
                
                if farEnough {
                    // Approximate distant nodes as a single mass
                    if distanceSquared < distanceMax2 {
                        let k = strength * t.delegate.accumulatedMass / distanceSquared
                        f += vec * k
                    }
                    return false // No need to visit children
                } else if t.childrenBufferPointer != nil {
                    return true // Continue to children
                }
                
                // Handle leaf nodes
                if t.isFilledLeaf {
                    if t.nodeIndices?.contains(NodeID(id: i)) == true {
                        return false // Skip self-interaction
                    }
                    let massAcc = t.delegate.accumulatedMass
                    let k = strength * massAcc / distanceSquared
                    f += vec * k
                    return false
                } else {
                    return true
                }
            }
            
            // Apply the computed force
            parameters.setForce(f, index: i)
        }
    }
}
