//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit


struct ContentView: View {
    let nodeCount = 5
    
    var body: some View {
        RealityView { content in
            
            // Create spring force effect
            let spring = ForceEffect(
                effect: Spring(),
                strengthScale: 1,
                mask: CollisionGroup.all
            )
            
            // Calculate positions in a circle
            let radius: Float = 0.5 // Distance between nodes
            let angleStep = 2 * Float.pi / Float(nodeCount)
            let center = SIMD3<Float>(0, 0.7, -1) // Center position in front of player
            
            for i in 0..<nodeCount {
                let angle = angleStep * Float(i)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                
                let node = Entity.makeNode(
                    position: [x, y, center.z],
                    groupId: i,
                    size: 2,
                    shape: .sphere
                )
                
                node.components.set(ForceEffectComponent(effect: spring))
                
                content.add(node)
            }
            
        }
        .installDrag()
    }
}
