//
//  liminalApp.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI


@main
struct liminalApp: App {
    static let volumeLength = 3000.0
    let volumeSize = Size3D(width: volumeLength, height: volumeLength, depth: volumeLength)

    init() { GestureComponent.registerComponent() }

    var body: some Scene {
        WindowGroup(id: "my2DWindow"){
            ContentView()
                .frame(minWidth: 300, minHeight: 200)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.all, 16)
        }
        WindowGroup {
            GraphView()
                .frame(minWidth: volumeSize.width, minHeight: volumeSize.height)
                .frame(minDepth: volumeSize.depth)
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize) //default
    }
}
