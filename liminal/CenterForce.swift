//
//  CenterForce.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

import SwiftUI
import RealityKit


/// A force that drives nodes towards the center.
///
/// Center force is relatively fast, the complexity is `O(n)`,
/// where `n` is the number of nodes.
/// See [Collide Force - D3](https://d3js.org/d3-force/collide).
struct CenterForce: ForceEffectProtocol {
    var parameterTypes: PhysicsBodyParameterTypes { [.position, .distance] }
    var forceMode: ForceMode { .velocity }

    //MARK: - Custom properties

    func update(parameters: inout ForceEffectParameters) {
        guard let positions = parameters.positions else {return}
        let N = parameters.physicsBodyCount
        var meanPosition : SIMD3<Float> = .zero
        for i in 0..<N {
            meanPosition += positions[i]  //.position
        }
        let delta : SIMD3<Float> = meanPosition / Float(Double(N) * parameters.elapsedTime)

        for i in 0..<N {
            parameters.setForce(-delta, index: i)
        }
    }
}
