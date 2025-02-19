//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit


struct ContentView: View {

    let positions: [Float] = [0.5,0.7,1,1.2,1.4]

    var body: some View {
        RealityView { content in

            // Create spring force effect
            let spring = ForceEffect(
                effect: Spring(),
                strengthScale: 1,
                mask: CollisionGroup.all
            )

            for (index, y) in positions.enumerated() {
                let node = Entity.makeNode(
                    position: [0, y, -1],
                    groupId: 0,
                    size: 5,
                    shape: .sphere
                )
                
                // Add spring force to middle node (index 2 since positions array has 5 elements)
                if index == 2 {
                    node.components.set(ForceEffectComponent(effect: spring))
                }
                
                content.add(node)
            }
            
        }
        .installDrag()
    }
}
