import RealityKit
import SwiftUI
import Speech
import AVFoundation

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
    @State private var voiceCommandHandler: VoiceCommandHandler
    
    let radius: Float
    let graphData: GraphData
    
    init(radius: Float = 0.5, graphData: GraphData) {
        self.radius = radius
        self.graphData = graphData
        let openAIClient = OpenAIClient(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
        _voiceCommandHandler = State(wrappedValue: VoiceCommandHandler(openAIClient: openAIClient))
    }
    @Environment(\.openWindow) private var openWindow
    
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
                Button(action: {
                    Task {
                        do {
                            if voiceCommandHandler.isRecording {
                                print("Stopping recording via button")
                                voiceCommandHandler.stopRecording()
                            } else {
                                print("Starting recording via button")
                                try await voiceCommandHandler.startRecording()
                            }
                        } catch {
                            print("Error in voice command: \(error.localizedDescription)")
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: voiceCommandHandler.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundColor(voiceCommandHandler.isRecording ? .red : .blue)
                        if voiceCommandHandler.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                Button("Filter") { showFilters.toggle() }
                Button("Upload") { }
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
            }
        }
        .ornament(attachmentAnchor: .scene(.leading)) {
            if showFilters {
                FiltersView()
            }
        }
    }
}
