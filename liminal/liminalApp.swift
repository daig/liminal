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
    @State private var graphData: GraphData?
    @AppStorage("openAIKey") private var apiKey = ""
    private var openAIClient: OpenAIClient {
        OpenAIClient(apiKey: apiKey)
    }

    init() {
        GestureComponent.registerComponent()
        NodeComponent.registerComponent()
    }

    var body: some Scene {
        WindowGroup {
            if let data = graphData {
                GraphView(graphData: data, openAIClient: openAIClient)
                    .frame(minWidth: volumeSize.width, minHeight: volumeSize.height)
                    .frame(minDepth: volumeSize.depth)
            } else {
                ProgressView("Loading graph...")
                    .task {
                        do {
                            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
                                throw NSError(domain: "iCloudContainerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
                            }
                            let documentsURL = containerURL.appendingPathComponent("Documents")
                            graphData = try parseGraphData(from: documentsURL)
                        } catch {
                            print("Error loading graph: \(error)")
                            graphData = GraphData(nodeCount: 0, edges: [])
                        }
                    }
            }
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize)
        
        // Settings window
        WindowGroup(id: "settings") {
            SettingsView()
                .frame(minWidth: 400, minHeight: 300)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.all, 16)
        }
        
        // Existing WindowGroup for editor windows
        WindowGroup(id: "editor", for: EditorContext.self) { $context in
            if let context = context, let data = graphData {
                ContentView(noteData: context.noteData, graphData: data, onSave: { savedNote in
                    // When a note is saved, reload the graph data
                    Task {
                        do {
                            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
                                throw NSError(domain: "iCloudContainerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
                            }
                            let documentsURL = containerURL.appendingPathComponent("Documents")
                            graphData = try parseGraphData(from: documentsURL)
                        } catch {
                            print("Error reloading graph: \(error)")
                        }
                    }
                }, isEditing: context.isEditing)
                .frame(minWidth: 300, minHeight: 200)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.all, 16)
            }
        }
        
        // New WindowGroup for PDF viewer windows
        WindowGroup(id: "pdfViewer", for: URL.self) { $url in
            if let url = url {
                PDFViewer(url: url) { savedPDF in
                    // When a PDF is renamed, reload the graph data
                    Task {
                        do {
                            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
                                throw NSError(domain: "iCloudContainerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
                            }
                            let documentsURL = containerURL.appendingPathComponent("Documents")
                            graphData = try parseGraphData(from: documentsURL)
                        } catch {
                            print("Error reloading graph after PDF rename: \(error)")
                        }
                    }
                }
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
