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

    @State private var sphere: ModelEntity
    = createNodeEntity(position: [0,1,-1],
                       groupId: 0,
                       size: 5,
                       shape: .sphere)


    var body: some View {
        RealityView { content in
            content.add(sphere)
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .useGestureComponent()
        )
    }
}
