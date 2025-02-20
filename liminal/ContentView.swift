//
//  ContentView.swift
//  liminal
//
//  Created by David Girardo on 2/15/25.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    let nodeCount = 6
    
    // Generate edges for a ring configuration
    func generateRingEdges(nodeCount: Int) -> Set<Set<Int>> {
        var edges = Set<Set<Int>>()
        for i in 0..<nodeCount {
            let nextNode = (i + 1) % nodeCount
            edges.insert(Set([i, nextNode]))
        }
        return edges
    }
    
    // Calculate positions in a circle layout
    func calculateCircleLayout(nodeCount: Int, radius: Float, center: SIMD3<Float>) -> [(Int, SIMD3<Float>)] {
        let angleStep = 2 * Float.pi / Float(nodeCount)
        return (0..<nodeCount).map { i in
            let angle = angleStep * Float(i)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            return (i, SIMD3<Float>(x, y, center.z))
        }
    }
    
    var body: some View {
        RealityView { content in

            // Generate ring edges
            let edges = generateRingEdges(nodeCount: nodeCount)
            
            // Convert edges to node connections mapping
            var nodeConnections: [Int: Set<Int>] = [:]
            for edge in edges {
                let nodeArray = Array(edge)
                nodeConnections[nodeArray[0], default: []].insert(nodeArray[1])
                nodeConnections[nodeArray[1], default: []].insert(nodeArray[0])
            }
            
            /*
            // Create spring force effect for connected nodes
            func makeSpringForce(nodeId: Int) -> ForceEffect<Spring> {
                let connectedNodes = nodeConnections[nodeId] ?? []
                let mask = connectedNodes.reduce(CollisionGroup()) {
                    $0.union(CollisionGroup(rawValue: 1 << $1))
                }
                let spring = Spring()
                return ForceEffect(
                    effect: spring,
                    strengthScale: 1,
                    mask: mask
                )
            }
             */
            
            
            let center = SIMD3<Float>(0, 1.5, -1.5)
//            let center: SIMD3<Float> = .zero
            let centerForce = ForceEffect(
                effect: CenterForce(),
                strengthScale: 0.1,
                mask: .all
            )
            let manyBodyForce = ForceEffect(
                effect: ManyBodyForce(strength: 1, theta: 0.9, distanceMin: 1),
                strengthScale: 1.0,
                mask: .all
            )
//            let centerAnchor = AnchorEntity(world: .zero)
            let forceContainer = Entity()
            forceContainer.position = center
            
            forceContainer.components.set(ForceEffectComponent(effect: centerForce))
            forceContainer.components.set(ForceEffectComponent(effect: manyBodyForce))

//            centerAnchor.addChild(forceContainer)
            content.add(forceContainer)

            
            // Calculate node positions
            let radius: Float = 0.5
            let nodePositions = calculateCircleLayout(nodeCount: nodeCount, radius: radius, center: center)
            
            // Create and add nodes
            for (index, position) in nodePositions {
                let node = Entity.makeNode(
                    position: position,
                    groupId: index,
                    size: 2,
                    shape: .sphere,
                    center: center
                )
                
                forceContainer.addChild(node)
            }
            
            /*
            // Create and add edges
            for edge in edges {
                let edgeArray = Array(edge)
                guard let startNode = nodeEntities[edgeArray[0]],
                      let endNode = nodeEntities[edgeArray[1]] else {
                    continue
                }
                
                let edgeEntity = Entity.makeEdge(
                    from: startNode.position,
                    to: endNode.position
                )
                content.add(edgeEntity)
                
                // Update edge position and orientation when nodes move
                content.subscribe(to: SceneEvents.Update.self) { event in
                    guard let startNode = nodeEntities[edgeArray[0]],
                          let endNode = nodeEntities[edgeArray[1]] else {
                        return
                    }
                    
                    // Calculate new edge properties using world-space positions
                    let startPos = startNode.scenePosition
                    let endPos = endNode.scenePosition
                    let distance = length(endPos - startPos)
                    
                    // Update position to midpoint
                    edgeEntity.position = (startPos + endPos) / 2
                    
                    // Update orientation
                    let direction = normalize(endPos - startPos)
                    let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
                    let rotationAngle = acos(dot(SIMD3<Float>(0, 1, 0), direction))
                    if length(rotationAxis) > 0.001 {
                        edgeEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                    }
                    
                    // Update length
                    if var model = edgeEntity.components[ModelComponent.self] {
                        model.mesh = .generateBox(size: SIMD3<Float>(0.002, distance, 0.002))
                        edgeEntity.components.set(model)
                    }
                }
            }
             */
        }
        .installDrag()
    }
}
