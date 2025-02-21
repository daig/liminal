//
//  GraphForce.swift
//  liminal
//
//  Created by David Girardo on 2/20/25.
//

import Foundation
import RealityKit
import SwiftUI

/// A combined force effect that orchestrates center, many-body, and link forces for graph visualization.
struct GraphForce: ForceEffectProtocol {
    // Required by ForceEffectProtocol
    var parameterTypes: PhysicsBodyParameterTypes { [.position, .velocity, .distance] }
    var forceMode: ForceMode { .velocity }
    
    // Center force properties
    let centerStrength: Float
    
    // Many-body force properties
    let manyBodyStrength: Float
    let theta: Float
    let distanceMin: Float
    let distanceMax: Float
    
    // Link force properties
    let links: [EdgeID]
    let linkStiffness: Float
    let linkLength: Float
    let linkIterations: UInt
    
    /// Initializes the combined graph force with customizable parameters for all three forces.
    init(
        // Center force parameters
        centerStrength: Float = 1.0,
        
        // Many-body force parameters
        manyBodyStrength: Float = -30.0,
        theta: Float = 0.9,
        distanceMin: Float = 1.0,
        distanceMax: Float = Float.greatestFiniteMagnitude,
        
        // Link force parameters
        links: [EdgeID],
        linkStiffness: Float = 0.5,
        linkLength: Float = 0.5,
        linkIterations: UInt = 1
    ) {
        self.centerStrength = centerStrength
        self.manyBodyStrength = manyBodyStrength
        self.theta = theta
        self.distanceMin = distanceMin
        self.distanceMax = distanceMax
        self.links = links
        self.linkStiffness = linkStiffness
        self.linkLength = linkLength
        self.linkIterations = linkIterations
    }
    
    func update(parameters: inout ForceEffectParameters) {
        guard parameters.physicsBodyCount > 0 else { return }
        
        // Initialize accumulated forces array
        var accumulatedForces = Array(repeating: SIMD3<Float>.zero, count: parameters.physicsBodyCount)
        
        // Apply center force
        applyCenterForce(parameters: &parameters, accumulatedForces: &accumulatedForces)
        
        // Apply many-body force
        applyManyBodyForce(parameters: &parameters, accumulatedForces: &accumulatedForces)
        
        // Apply link force
        applyLinkForce(parameters: &parameters, accumulatedForces: &accumulatedForces)
        
        // Apply all accumulated forces
        for i in 0..<parameters.physicsBodyCount {
            parameters.setForce(accumulatedForces[i], index: i)
        }
    }
}
