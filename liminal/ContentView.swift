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

            let gravity = ForceEffect(
                effect: Gravity(),
                strengthScale: 1,
                mask: CollisionGroup.all
                )    

            for y in positions {
                let node = Entity.makeNode(
                    position: [0, y, -1],
                    groupId: 0,
                    size: 5,
                    shape: .sphere
                )
                content.add(node)
            }
            
        }
        .installDrag()
    }
}
