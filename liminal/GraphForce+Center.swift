import RealityKit
import SwiftUI

extension GraphForce {
    /// Applies a force that drives nodes towards the center.
    /// Complexity: O(n) where n is the number of nodes.
    func applyCenterForce(parameters: inout ForceEffectParameters, accumulatedForces: inout [SIMD3<Float>]) {
        guard let positions = parameters.positions else { return }
        let N = parameters.physicsBodyCount
        
        // Calculate mean position
        var meanPosition: SIMD3<Float> = .zero
        for i in 0..<N {
            meanPosition += positions[i]
        }
        
        // Calculate center force
        let delta = meanPosition / Float(Double(N) * parameters.elapsedTime)
        let centerForce = -delta * centerStrength
        
        // Apply force to each node
        for i in 0..<N {
            accumulatedForces[i] += centerForce
        }
    }
} 