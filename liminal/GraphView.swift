import RealityKit
import SwiftUI

struct EdgeConnection {
    let entity: Entity
    let nodeIndices: (Int, Int)
}

struct EditorContext: Hashable, Codable {
    let noteData: NoteData
    let isEditing: Bool
}

struct GraphView: View {
    @State private var showFilters = false
    @State private var showCommandInput = false
    @State private var commandText = ""
    @State private var isProcessingCommand = false
    @State private var commandError: String? = nil
    @State private var commandResponse: String? = nil
    @State private var showSettings = false
    @AppStorage("openAIKey") private var apiKey = ""
    let radius: Float
    let graphData: GraphData
    let openAIClient: OpenAIClient
    @Environment(\.openWindow) private var openWindow
    
    init(radius: Float = 0.5, graphData: GraphData, openAIClient: OpenAIClient) {
        self.radius = radius
        self.graphData = graphData
        self.openAIClient = openAIClient
    }
    
    var body : some View {
        RealityView { content, attachments in
            let nodePositions = NodeLayout.circleLayout(graphData: graphData, radius: radius)
            
            var nodeEntities: [Entity] = []
            
            // Set up force simulation
            let graphForce = ForceEffect(
                effect: GraphForce(
                    centerStrength: 1,
                    manyBodyStrength: -0.1,
                    theta: 0.9,
                    distanceMin: 0,
                    links: graphData.edges,
                    linkStiffness: 10,
                    linkLength: 0.1
                ),
                strengthScale: 1.0,
                mask: .all
            )
            
            let forceContainer = Entity()
            forceContainer.position = .zero
            forceContainer.components.set(ForceEffectComponent(effect: graphForce))
            content.add(forceContainer)
            
            // Create nodes and attach labels
            for (index, position) in nodePositions {
                let node = Entity.makeNode(
                    position: position,
                    groupId: index,
                    size: 3,
                    shape: .sphere,
                    name: graphData.names[index],
                    content: graphData.contents[index]
                )
                // Add NodeComponent with the node's index
                node.components.set(NodeComponent(index: NodeID(id: index)))
                nodeEntities.append(node)
                forceContainer.addChild(node)
                
                if let attachment = attachments.entity(for: "node_\(index)") {
                    attachment.position = [0, 0.05, 0]
                    node.addChild(attachment)
                }
            }
            
            // Create edges (rendering as undirected lines)
            var edgeConnections: [EdgeConnection] = []
            for edge in graphData.edges {
                let sourceIndex = edge.source.id
                let targetIndex = edge.target.id
                guard sourceIndex < nodeEntities.count, targetIndex < nodeEntities.count else { continue }
                
                let startNode = nodeEntities[sourceIndex]
                let endNode = nodeEntities[targetIndex]
                
                let edgeEntity = Entity()
                let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.002, 1.0, 0.002))
                let material = SimpleMaterial(color: .white, isMetallic: false)
                edgeEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
                
                let startPos = startNode.position
                let endPos = endNode.position
                let distance = length(endPos - startPos)
                let midpoint = (startPos + endPos) / 2
                let direction = normalize(endPos - startPos)
                
                edgeEntity.position = midpoint
                
                let up = SIMD3<Float>(0, 1, 0)
                if abs(dot(up, direction)) < 0.999 {
                    let rotationAxis = cross(up, direction)
                    let rotationAngle = acos(dot(up, direction))
                    edgeEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                } else if dot(up, direction) < 0 {
                    edgeEntity.orientation = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(1, 0, 0))
                }
                
                edgeEntity.scale = SIMD3<Float>(1, distance, 1)
                
                forceContainer.addChild(edgeEntity)
                edgeConnections.append(EdgeConnection(entity: edgeEntity, nodeIndices: (sourceIndex, targetIndex)))
            }
            
            // Subscribe to scene updates for edge positioning
            content.subscribe(to: SceneEvents.Update.self) { event in
                for connection in edgeConnections {
                    let startNode = nodeEntities[connection.nodeIndices.0]
                    let endNode = nodeEntities[connection.nodeIndices.1]
                    
                    let startPos = startNode.position
                    let endPos = endNode.position
                    let distance = length(endPos - startPos)
                    let midpoint = (startPos + endPos) / 2
                    let direction = normalize(endPos - startPos)
                    
                    connection.entity.position = midpoint
                    
                    let up = SIMD3<Float>(0, 1, 0)
                    if abs(dot(up, direction)) < 0.999 {
                        let rotationAxis = cross(up, direction)
                        let rotationAngle = acos(dot(up, direction))
                        connection.entity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                    } else if dot(up, direction) < 0 {
                        connection.entity.orientation = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(1, 0, 0))
                    }
                    
                    connection.entity.scale = SIMD3<Float>(1, distance, 1)
                }
            }
        } attachments: {
            ForEach(0..<graphData.nodeCount, id: \.self) { index in
                Attachment(id: "node_\(index)") {
                    Text(graphData.names[index])
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                }
            }
        }
        .installGestures(graphData: graphData, openWindow: openWindow)
        .toolbar {
            ToolbarItemGroup() {
                Button("Filter") { showFilters.toggle() }
                Button("Upload") { }
                Button("Command") { 
                    if apiKey.isEmpty {
                        openWindow(id: "settings")
                    } else {
                        showCommandInput.toggle()
                        commandText = ""
                        commandError = nil
                        commandResponse = nil
                    }
                }
                Button("Compose") {
                    // Create a new note with a unique name based on timestamp
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let newNoteName = "Note-\(timestamp)"
                    var newNote = NoteData(title: newNoteName, content: "")
                    
                    // First save the note to create the file
                    Task {
                        do {
                            try newNote.save()
                            // Wait a brief moment to ensure file is written
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            // Then open the editor window in edit mode
                            let context = EditorContext(noteData: newNote, isEditing: true)
                            openWindow(id: "editor", value: context)
                        } catch {
                            print("Error creating new note: \(error)")
                        }
                    }
                }
                Button("Settings") {
                    openWindow(id: "settings")
                }
            }
        }
        .ornament(attachmentAnchor: .scene(.leading)) {
            if showFilters {
                FiltersView()
            }
        }
        .ornament(attachmentAnchor: .scene(.trailing)) {
            if showCommandInput {
                VStack(spacing: 16) {
                    Text("Enter Command")
                        .font(.title2)
                        .padding(.top)
                    
                    if let response = commandResponse {
                        ScrollView {
                            Text(response)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                        
                        HStack {
                            Button("New Command") {
                                commandText = ""
                                commandError = nil
                                commandResponse = nil
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Close") {
                                showCommandInput = false
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.bottom)
                    } else {
                        TextField("Type your command here...", text: $commandText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        
                        if let error = commandError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                        
                        HStack {
                            Button("Cancel") {
                                commandText = ""
                                commandError = nil
                                showCommandInput = false
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Execute") {
                                Task {
                                    await processCommand(commandText)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(commandText.isEmpty || isProcessingCommand)
                        }
                        .padding(.bottom)
                    }
                }
                .frame(width: 400)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func processCommand(_ command: String) async {
        guard !command.isEmpty else { return }
        guard !apiKey.isEmpty else {
            commandError = "Error: OpenAI API key not set. Please set it in Settings."
            return
        }
        
        isProcessingCommand = true
        commandError = nil
        
        do {
            print("Available files:", graphData.names)
            
            // First, analyze which files are relevant to the command
            let relevantFiles = try await openAIClient.analyzeCommand(
                command: command,
                availableFiles: graphData.names
            )
            
            print("LLM requested files:", relevantFiles)
            
            // Create a context map of file contents
            var fileContexts: [String: String] = [:]
            for filename in relevantFiles {
                print("Looking for file:", filename)
                if let index = graphData.names.firstIndex(of: filename) {
                    print("Found file at index:", index)
                    if case .markdown(let content) = graphData.contents[index] {
                        print("Successfully extracted markdown content for:", filename)
                        fileContexts[filename] = content
                    } else {
                        print("File is not markdown:", filename)
                    }
                } else {
                    print("File not found in graph data:", filename)
                }
            }
            
            print("Final file contexts:", fileContexts.keys)
            
            // Execute the command with the file contexts
            let result = try await openAIClient.executeCommand(
                command: command,
                fileContexts: fileContexts
            )
            
            // Display the result
            commandResponse = result
            
        } catch {
            print("Command processing error:", error)
            commandError = "Error: \(error.localizedDescription)"
        }
        
        isProcessingCommand = false
    }
}
