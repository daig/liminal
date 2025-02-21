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
    let nodeCount = 20
    let radius: Float = 0.5
    let center = SIMD3<Float>(0, 1.5, -1.5)
    
    var body: some View {
        RealityView { content in
            // Create graph data for a small-world network
            let graphData = GraphData.smallWorldGraph(nodeCount: nodeCount, extraEdgeCount: 9)
            let nodePositions = NodeLayout.circleLayout(graphData: graphData, radius: radius, center: center)
            
            var nodeEntities: [Entity] = []
            
            // Create edgesArray for force simulation
            let edgesArray = graphData.edges.map { edge in
                let nodes = Array(edge)
                return EdgeID(source: NodeID(id: nodes[0]), target: NodeID(id: nodes[1]))
            }
            
            // Set up force container and graph force
            let graphForce = ForceEffect(
                effect: GraphForce(
                    centerStrength: 1,
                    manyBodyStrength: -0.0005,
                    theta: 0.9,
                    distanceMin: 1.0,
                    links: edgesArray,
                    linkStiffness: 1,
                    linkLength: 0.5
                ),
                strengthScale: 1.0,
                mask: .all
            )
            
            let forceContainer = Entity()
            forceContainer.position = center
            forceContainer.components.set(ForceEffectComponent(effect: graphForce))
            content.add(forceContainer)
            
            // Create node entities
            for (index, position) in nodePositions {
                let node = Entity.makeNode(
                    position: position,
                    groupId: index,
                    size: 2,
                    shape: .sphere,
                    center: center
                )
                nodeEntities.append(node)
                forceContainer.addChild(node)
            }
            
            // Create edge entities with fixed meshes
            var edgeConnections: [EdgeConnection] = []
            for edge in graphData.edges {
                let edgeArray = Array(edge)
                guard edgeArray[0] < nodeEntities.count, edgeArray[1] < nodeEntities.count else {
                    continue
                }
                
                let startNode = nodeEntities[edgeArray[0]]
                let endNode = nodeEntities[edgeArray[1]]
                
                // Create edge entity with a unit-height box
                let edgeEntity = Entity()
                let mesh = try! MeshResource.generateBox(size: SIMD3<Float>(0.002, 1.0, 0.002))
                let material = SimpleMaterial(color: .white, isMetallic: false)
                edgeEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
                
                // Initial position and orientation in world space
                let startPos = startNode.scenePosition
                let endPos = endNode.scenePosition
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
                
                content.add(edgeEntity)
                edgeConnections.append(EdgeConnection(entity: edgeEntity, nodeIndices: (edgeArray[0], edgeArray[1])))
            }
            
            // Single subscription to update all edges
            content.subscribe(to: SceneEvents.Update.self) { event in
                for connection in edgeConnections {
                    let startNode = nodeEntities[connection.nodeIndices.0]
                    let endNode = nodeEntities[connection.nodeIndices.1]
                    
                    let startPos = startNode.scenePosition
                    let endPos = endNode.scenePosition
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
        }
        .installGestures()
    }
}
