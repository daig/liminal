import RealityKit
import SwiftUI

struct EdgeConnection {
    let entity: Entity
    let nodeIndices: (Int, Int)
}

struct GraphView: View {
    @State private var showFilters = false
    let radius: Float
    let graphData: GraphData
    
    init(radius: Float = 0.5) {
        do {
            let mdFiles = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
            self.graphData = try parseGraphDataFromBundleRoot(mdFiles: mdFiles)
        } catch {
            print("Error parsing from root: \(error)")
            self.graphData = GraphData(nodeCount: 0, edges: [])
        }
        self.radius = radius
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
                    linkStiffness: 1,
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
                    name: graphData.names[index]
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
                Button("Compose") { }
            }
        }
        .overlay(alignment: .bottom) {
            Button("Open 2D Window") {
                openWindow(id: "my2DWindow")
            }
            .padding()
        }
        .ornament(attachmentAnchor: .scene(.leading)) {
            if showFilters {
                FiltersView()
            }
        }
    }
}
