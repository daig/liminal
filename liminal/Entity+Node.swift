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
        shape: NodeShape
    ) -> ModelEntity {
        let mesh : MeshResource
        switch shape {
        case .sphere:
            mesh = MeshResource.generateSphere(radius: size * 0.01)
        case .cube:
            mesh = MeshResource.generateBox(size: .init(x: size * 0.0161, y: size * 0.0161, z: size * 0.0161))
        }
        let entity = ModelEntity( mesh: mesh, materials: [nodeMaterial] )
        
        
        
        entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        
        let highlightStyle = HoverEffectComponent.HighlightHoverEffectStyle(color: .white , strength: 0.2)
        let hoverEffect = HoverEffectComponent(.highlight(highlightStyle))
        entity.components.set(hoverEffect)
        
        entity.components.set(DragComponent())
        
        
        //add collision component
        entity.generateCollisionShapes(recursive: true)
        if let collisionShape = entity.collision?.shapes.first {
            
            var physicsBody = PhysicsBodyComponent(shapes: [collisionShape],mass: 1, mode: .dynamic)
            physicsBody.isAffectedByGravity = false
            physicsBody.linearDamping = 0
            physicsBody.angularDamping = 0
            entity.components.set(physicsBody)
        }
        
        //    // Add force effects if provided
        //    if !forces.isEmpty {
        //        entity.components.set(ForceEffectComponent(effects: forces))
        //    }
        
        entity.position = position
        
        return entity
    }
}
