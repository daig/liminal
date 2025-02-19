//
//  NodeForces.swift
//  liminal
//
//  Created by David Girardo on 2/17/25.
//

import SwiftUI
import RealityKit

struct Spring: ForceEffectProtocol {
    var parameterTypes: PhysicsBodyParameterTypes { [.position, .distance] }
    var forceMode: ForceMode { .force }

    //MARK: - Custom properties

    var magnitude: Float = 0.1
    var minimumDistance: Float = 0.2
    var springDistance: Float = 0.3 // meters

    func update(parameters: inout ForceEffectParameters) {

        guard let distances = parameters.distances,
              let positions = parameters.positions else { return }

        for i in 0..<parameters.physicsBodyCount {

            let distance = distances[i]
            let position = positions[i]

            // There is a singularity at the origin; ignore any objects near the origin.
            guard distance > minimumDistance else { continue }

            let force = computeForce(position: position, distance: distance)
            parameters.setForce(force, index: i)
        }
    }

    func computeForce(position: SIMD3<Float>, distance: Float) -> SIMD3<Float> {
        
        // Spring force follows Hooke's law: F = -kx
        // where k is the spring constant (magnitude) and x is displacement
        let springForce = -normalize(position) * magnitude * (distance - springDistance)
        
        return springForce
    }
}

