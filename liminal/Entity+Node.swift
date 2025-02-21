import SwiftUI
import RealityKit

enum NodeShape { case sphere; case cube }

@MainActor
let nodeMaterial: PhysicallyBasedMaterial = {
        let color = UIColor(.gray)
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1.0)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.01)
        
        material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: color)
        material.emissiveIntensity = 0.4
        return material
    }()

extension Entity {
    static func makeNode(
        position: SIMD3<Float>,
        groupId: Int,
        size: Float = 1,
        shape: NodeShape,
        center: SIMD3<Float>
    ) -> ModelEntity {
        let mesh : MeshResource
        switch shape {
        case .sphere:
            mesh = MeshResource.generateSphere(radius: size * 0.01)
        case .cube:
            mesh = MeshResource.generateBox(size: .init(x: size * 0.0161, y: size * 0.0161, z: size * 0.0161))
        }
        
        // Create a unique color based on the groupId
        var material = PhysicallyBasedMaterial()
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .systemPurple, .systemOrange]
        let color = colors[groupId % colors.count]
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1.0)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.01)
        material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: color)
        material.emissiveIntensity = 0.4
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        
        let highlightStyle = HoverEffectComponent.HighlightHoverEffectStyle(color: .white , strength: 0.2)
        let hoverEffect = HoverEffectComponent(.highlight(highlightStyle))
        entity.components.set(hoverEffect)
        
        entity.components.set(DragComponent())
        
        //Set customgroup based on groupId[],
         
        //add mpent
        entity.generateCollisionShapes(recursive: true)
        if let collisionShape = entity.collision?.shapes.first {
            
            var physicsBody = PhysicsBodyComponent(shapes: [collisionShape],mass: 1, mode: .dynamic)
            physicsBody.isAffectedByGravity = false
            physicsBody.linearDamping = 1.5
            physicsBody.angularDamping = 1
            entity.components.set(physicsBody)
        }
        
        //    // Add force effects if provided
        //    if !forces.isEmpty {
        //        entity.components.set(ForceEffectComponent(effects: forces))
        //    }
        
        entity.position = position - center
        
        return entity
    }
    
    static func makeEdge(from startPosition: SIMD3<Float>, to endPosition: SIMD3<Float>) -> ModelEntity {
        // Calculate the distance between points
        let distance = length(endPosition - startPosition)
        
        // Create a thin cylinder to represent the edge
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.002, distance, 0.002))
        
        // Create a gray material for the edge
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .gray)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1.0)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.01)
        
        let edge = ModelEntity(mesh: mesh, materials: [material])
        
        // Position and orient the edge
        let midPoint = (startPosition + endPosition) / 2
        edge.position = midPoint
        
        // Calculate rotation to point from start to end
        let direction = normalize(endPosition - startPosition)
        let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
        let rotationAngle = acos(dot(SIMD3<Float>(0, 1, 0), direction))
        if length(rotationAxis) > 0.001 {  // Avoid division by zero
            edge.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
        }
        
        return edge
    }
}
