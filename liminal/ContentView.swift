//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    @State private var sphere: ModelEntity = {
        let sphereMesh = MeshResource.generateSphere(radius: 0.1)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let entity = ModelEntity(mesh: sphereMesh, materials: [material])
        entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        entity.generateCollisionShapes(recursive: true)
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        entity.components.set(GestureComponent())
        return entity
    }()

    var body: some View {
        RealityView { content in
            content.add(sphere)
        }
        .gesture(
            DragGesture()
                .targetedToEntity(sphere)
                .useGestureComponent()
        )
    }
}

#Preview("ImmersiveStyle", immersionStyle: .automatic, body: {
    ContentView()
})
