//
//  NodeForces.swift
//  liminal
//
//  Created by David Girardo on 2/17/25.
//

import SwiftUI
import RealityKit


struct Gravity: ForceEffectProtocol {
    var parameterTypes: PhysicsBodyParameterTypes { [.mass] }
    var forceMode: ForceMode = .force
    func update(parameters: inout ForceEffectParameters) {
        for (i, mass) in parameters.masses!.enumerated() {
            parameters.setForce([0, -1 * mass, 0], index: i) // -9.81
        }
    }
        
}

