//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit

struct EdgeConnection {
    let entity: Entity
    let nodeIndices: (Int, Int)
}

struct ContentView: View {
    
    var body: some View {
        graphView()
    }
}
