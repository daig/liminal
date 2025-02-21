//
//  GraphView.swift
//  liminal
//
//  Created by David Girardo on 2/20/25.
//

import RealityKit
import SwiftUI


struct EdgeConnection {
    let entity: Entity
    let nodeIndices: (Int, Int)
}

struct GraphView: View {
    let nodeCount: Int
    let radius: Float
    
    let graphData: GraphData
    
    init(nodeCount: Int = 20, radius: Float = 0.5) {
        self.nodeCount = nodeCount
        self.radius = radius
        self.graphData = GraphData.smallWorldGraph(nodeCount: nodeCount, extraEdgeCount: 20)
    }

    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        RealityView { content, attachments in
            // Create graph data and layout
            let nodePositions = NodeLayout.circleLayout(graphData: graphData, radius: radius)
            
            var nodeEntities: [Entity] = []
            
            // Define edges for force simulation
            let edgesArray = graphData.edges.map { edge in
                let nodes = Array(edge)
                return EdgeID(source: NodeID(id: nodes[0]), target: NodeID(id: nodes[1]))
            }
            
            // Set up force simulation
            let graphForce = ForceEffect(
                effect: GraphForce(
                    centerStrength: 1,
                    manyBodyStrength: -0.1,
                    theta: 0.9,
                    distanceMin: 0,
                    links: edgesArray,
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
                nodeEntities.append(node)
                forceContainer.addChild(node)
                
                // Attach the name label
                if let attachment = attachments.entity(for: "node_\(index)") {
                    attachment.position = [0, 0.05, 0] // Position above the node
                    node.addChild(attachment)
                }
            }
            
            // Create edges (implementation remains the same)
            var edgeConnections: [EdgeConnection] = []
            for edge in graphData.edges {
                let edgeArray = Array(edge)
                guard edgeArray[0] < nodeEntities.count, edgeArray[1] < nodeEntities.count else { continue }
                
                let startNode = nodeEntities[edgeArray[0]]
                let endNode = nodeEntities[edgeArray[1]]
                
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
                edgeConnections.append(EdgeConnection(entity: edgeEntity, nodeIndices: (edgeArray[0], edgeArray[1])))
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
            // Create attachments for each node's name
            ForEach(0..<nodeCount, id: \.self) { index in
                Attachment(id: "node_\(index)") {
                    Text(graphData.names[index])
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                }
            }
        }
        .installGestures()
        .overlay(alignment: .bottom) {
            Button("Open 2D Window") {
                openWindow(id: "my2DWindow")
            }
            .padding()
        }
    }
}
