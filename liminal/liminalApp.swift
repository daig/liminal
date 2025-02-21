//
//  liminalApp.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI

@main
struct liminalApp: App {

    init() { GestureComponent.registerComponent() }

    var body: some Scene {
        ImmersiveSpace {
            ContentView()
        }
    }
}
