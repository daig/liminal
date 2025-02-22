// File: liminal/GraphForce+Box.swift
import RealityKit
import SwiftUI

extension GraphForce {
    /// Applies a strong, sharply localized repulsive force from the edges of a 2-meter cubic volume.
    /// The force activates only near the boundaries (within 0.2 meters) and falls off quickly.
    /// Complexity: O(n) where n is the number of nodes.
    func applyBoxBoundaryForce(parameters: inout ForceEffectParameters, accumulatedForces: inout [SIMD3<Float>]) {
        guard let positions = parameters.positions else { return }
        let N = parameters.physicsBodyCount
        
        // Define the 2-meter box boundaries (centered at origin)
        let boxSize: Float = 2.0
        let halfBoxSize: Float = boxSize / 2.0
        let minBound: SIMD3<Float> = [-halfBoxSize, -halfBoxSize, -halfBoxSize]
        let maxBound: SIMD3<Float> = [halfBoxSize, halfBoxSize, halfBoxSize]
        
        // Boundary force parameters
        let boundaryStrength: Float = 100.0  // Strong force, but only near edges
        let boundaryDistance: Float = 0.2     // Force activates within 0.2m of edge
        let falloffExponent: Float = 3.0      // Cubic falloff for sharp decay
        
        for i in 0..<N {
            let pos = positions[i]
            var boundaryForce: SIMD3<Float> = .zero
            
            // Compute force for each axis
            for axis in 0..<3 {
                let distanceToMin = pos[axis] - minBound[axis]
                let distanceToMax = maxBound[axis] - pos[axis]
                
                // Force from lower boundary (positive direction)
                if distanceToMin < boundaryDistance {
                    let normalizedDistance = distanceToMin / boundaryDistance
                    let forceMagnitude = boundaryStrength * pow(1.0 - normalizedDistance, falloffExponent)
                    boundaryForce[axis] += forceMagnitude
                }
                
                // Force from upper boundary (negative direction)
                if distanceToMax < boundaryDistance {
                    let normalizedDistance = distanceToMax / boundaryDistance
                    let forceMagnitude = boundaryStrength * pow(1.0 - normalizedDistance, falloffExponent)
                    boundaryForce[axis] -= forceMagnitude
                }
            }
            
            // Apply the boundary force
            accumulatedForces[i] += boundaryForce
        }
    }
    
}
