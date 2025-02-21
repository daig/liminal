import RealityKit
import SwiftUI

extension GraphForce {
    /// Applies spring forces between connected nodes to maintain target distances.
    /// Complexity: O(e) where e is the number of links.
    func applyLinkForce(parameters: inout ForceEffectParameters, accumulatedForces: inout [SIMD3<Float>]) {
        guard let positions = parameters.positions,
              let velocities = parameters.velocities else { return }
        
        // Compute bias based on node degrees
        let linkLookup = LinkLookup(links: links)
        let bias = links.map { link in
            let sourceCount = Float(linkLookup.count[link.source, default: 0])
            let targetCount = Float(linkLookup.count[link.target, default: 0])
            let total = sourceCount + targetCount
            return total > 0 ? sourceCount / total : 0.5
        }
        
        // Apply forces for each iteration
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
            
            // Force magnitude: proportional to deviation from target length
            let l = (length - linkLength) / length * linkStiffness
            vec *= l
            
            // Apply forces with bias
            let b = bias[i]
            
            accumulatedForces[targetIndex] += -vec * b
            accumulatedForces[sourceIndex] += vec * (1 - b)
        }
    }
} 
