//
//  liminalApp.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI


@main
struct liminalApp: App {
    let volumeSize = 2.0

    init() { GestureComponent.registerComponent() }

    var body: some Scene {
        WindowGroup(id: "my2DWindow"){
            ContentView()
        }
        WindowGroup {
            GraphView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: volumeSize, height: volumeSize, depth: volumeSize, in: .meters)
    }
}
