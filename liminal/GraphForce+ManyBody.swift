import RealityKit
import SwiftUI

extension GraphForce {
    /// Applies repulsive or attractive forces between all nodes using Barnes-Hut approximation.
    /// Complexity: O(n log n) where n is the number of nodes.
    func applyManyBodyForce(parameters: inout ForceEffectParameters, accumulatedForces: inout [SIMD3<Float>]) {
        guard let positions = parameters.positions,
              var velocities = parameters.velocities else { return }
        let N = parameters.physicsBodyCount
        
        // Precompute squared values for efficiency
        let theta2 = theta * theta
        let distanceMin2 = distanceMin * distanceMin
        let distanceMax2 = distanceMax * distanceMax
        
        // Initialize Barnes-Hut tree
        let massProvider: (NodeID) -> Float = { _ in 1 }
        let rootDelegate = MassDelegate(massProvider: massProvider)
        let coveringBox = KDBox.cover(of: positions, count: N)
        var tree = BufferedKDTree<MassDelegate>(
            rootBox: coveringBox,
            nodeCapacity: N,
            rootDelegate: rootDelegate
        )
        
        // Build tree
        for i in 0..<N {
            tree.add(nodeIndex: NodeID(id: i), at: positions[i])
        }
        
        // Compute forces for each node
        for i in 0..<N {
            let pos = positions[i]
            var force: SIMD3<Float> = .zero
            
            tree.visit { t in
                guard t.delegate.accumulatedMass > 0 else { return false }
                
                let centroid = t.delegate.accumulatedMassWeightedPositions / t.delegate.accumulatedMass
                let vec = centroid - pos
                let boxWidth = (t.box.p1 - t.box.p0)[0]
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
                        let k = manyBodyStrength * t.delegate.accumulatedMass / distanceSquared
                        force += vec * k
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
                    let k = manyBodyStrength * massAcc / distanceSquared
                    force += vec * k
                    return false
                } else {
                    return true
                }
            }
            
            // Apply force
            let velocityChange = force * Float(parameters.elapsedTime)
            let nsq = Float(N) * Float(N)
            accumulatedForces[i] += velocityChange / [nsq,nsq,nsq]
        }
    }
} 
