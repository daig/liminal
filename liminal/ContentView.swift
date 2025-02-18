//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit

enum NodeShape { case sphere; case cube }

struct ContentView: View {

    let positions: [Float] = [0.5,0.7,1,1.2,1.4]

    var body: some View {
        RealityView { content in
            for y in positions {
                let node = createNodeEntity(
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
