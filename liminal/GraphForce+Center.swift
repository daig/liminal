import RealityKit
import SwiftUI

extension GraphForce {
    /// Applies a force that drives nodes towards the center.
    /// Complexity: O(n) where n is the number of nodes.
    func applyCenterForce(parameters: inout ForceEffectParameters, accumulatedForces: inout [SIMD3<Float>]) {
        guard let positions = parameters.positions else { return }
        let N = parameters.physicsBodyCount
        
        // Calculate mean position (center of mass)
        var meanPosition: SIMD3<Float> = .zero
        for i in 0..<N {
            meanPosition += positions[i]
        }
        meanPosition /= Float(N)
        
        // Apply spring-like force towards center for each node
        for i in 0..<N {
            let displacement = meanPosition - positions[i]
            // F = -kx where k is centerStrength
            let force = displacement * centerStrength
            accumulatedForces[i] += force
        }
    }
} 