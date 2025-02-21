//
//  liminalApp.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI

struct My2DWindowView: View {
    var body: some View {
        Text("This is a 2D Window")
            .font(.largeTitle)
            .padding()
    }
}

@main
struct liminalApp: App {
    let volumeSize = 2.0

    init() { GestureComponent.registerComponent() }

    var body: some Scene {
        WindowGroup(id: "my2DWindow"){
            My2DWindowView()
        }
        WindowGroup {
            GraphView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: volumeSize, height: volumeSize, depth: volumeSize, in: .meters)
    }
}
