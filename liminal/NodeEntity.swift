import SwiftUI
import RealityKit

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

@MainActor
func createNodeEntity(
    position: SIMD3<Float>,
    groupId: Int,
    size: Float = 1,
    shape: NodeShape
) -> ModelEntity {
    let nodeMesh : MeshResource
    switch shape {
    case .sphere:
        nodeMesh = MeshResource.generateSphere(radius: size * 0.01)
    case .cube:
        nodeMesh = MeshResource.generateBox(size: .init(x: size * 0.0161, y: size * 0.0161, z: size * 0.0161))
    }
    let nodeEntity = ModelEntity(
                mesh: nodeMesh,
                materials: [nodeMaterial]
            )
            nodeEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            nodeEntity.position = position
            nodeEntity.generateCollisionShapes(recursive: true)
            nodeEntity.components.set(GroundingShadowComponent(castsShadow: true))
            
            let highlightStyle = HoverEffectComponent.HighlightHoverEffectStyle(color: .white , strength: 0.2)
            let hoverEffect = HoverEffectComponent(.highlight(highlightStyle))
            nodeEntity.components.set(hoverEffect)

            nodeEntity.components.set(DragComponent())
            
            
            return nodeEntity
        }
