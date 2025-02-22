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

    init() {
        GestureComponent.registerComponent()
        NodeComponent.registerComponent()
    }

    var body: some Scene {
        WindowGroup {
            GraphView()
                .frame(minWidth: volumeSize.width, minHeight: volumeSize.height)
                .frame(minDepth: volumeSize.depth)
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize)
        
        // Existing WindowGroup for editor windows
        WindowGroup(id: "editor", for: String.self) { $text in
            ContentView(text: text ?? "")
                .frame(minWidth: 300, minHeight: 200)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.all, 16)
        }
        
        // New WindowGroup for PDF viewer windows
        WindowGroup(id: "pdfViewer", for: URL.self) { $url in
            if let url = url {
                PDFViewer(url: url)
                    .frame(minWidth: 300, minHeight: 200)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.all, 16)
            } else {
                Text("No PDF to display")
            }
        }
    }
}
