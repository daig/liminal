/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A component that handles standard drag, rotate, and scale gestures for an entity.
*/

import RealityKit
import SwiftUI

@MainActor
public final class GestureState {
    static let shared = GestureState()

    var target: Entity? = nil
    var startPosition: SIMD3<Float> = .zero
    var startScale: SIMD3<Float> = .one
    var isDragging: Bool = false
    var isScaling: Bool = false
    var storedPhysicsBody: PhysicsBodyComponent? = nil
}

/// A component that handles gesture logic for an entity.

public struct GestureComponent: Component, Codable {
    public var canDrag: Bool = true
    public var canScale: Bool = true

    public init() {}

    // Drag gesture handling
    @MainActor
    mutating func onChanged(value: EntityTargetValue<DragGesture.Value>) {
        let state = GestureState.shared
        guard canDrag, !state.isScaling else { return }
        if state.target == nil {
            state.target = value.entity
            // Store and remove physics body when drag starts
            if let physicsBody = value.entity.components[PhysicsBodyComponent.self] {
                state.storedPhysicsBody = physicsBody
                value.entity.components.remove(PhysicsBodyComponent.self)
            }
        }
        guard let target = state.target else { fatalError("No drag target found") }
        if !state.isDragging {
            state.isDragging = true
            state.startPosition = target.scenePosition
            // Update material when dragging starts
            if var model = target.components[ModelComponent.self],
               var material = model.materials.first as? PhysicallyBasedMaterial {
                material.baseColor.tint = UIColor(white: 0.7, alpha: 0.2)
                model.materials = [material]
                target.components.set(model)
            }
        }
        let translation3D = value.convert(value.gestureValue.translation3D, from: .local, to: .scene)
        let offset = SIMD3<Float>(Float(translation3D.x), Float(translation3D.y), Float(translation3D.z))
        target.scenePosition = state.startPosition + offset
    }

    @MainActor
    mutating func onEnded(value: EntityTargetValue<DragGesture.Value>) {
        let state = GestureState.shared
        state.isDragging = false
        
        // Restore physics body when drag ends
        if let storedPhysicsBody = state.storedPhysicsBody {
            value.entity.components.set(storedPhysicsBody)
            state.storedPhysicsBody = nil
        }
        
        state.target = nil
        // Reset material when dragging ends
        if var model = value.entity.components[ModelComponent.self],
           var material = model.materials.first as? PhysicallyBasedMaterial {
            withAnimation(.easeInOut(duration: 1)) {
                material.baseColor.tint = .gray
                model.materials = [material]
                value.entity.components.set(model)
            }
        }
    }

    // Magnify gesture handling
    @MainActor
    mutating func onChanged(value: EntityTargetValue<MagnifyGesture.Value>) {
        let state = GestureState.shared
        guard canScale else { return }
        let entity = value.entity
        if !state.isScaling {
            state.isScaling = true
            state.startScale = entity.scale
            // Optionally, update material when scaling starts
            if var model = entity.components[ModelComponent.self],
               var material = model.materials.first as? PhysicallyBasedMaterial {
                material.baseColor.tint = UIColor(white: 0.7, alpha: 0.2)
                model.materials = [material]
                entity.components.set(model)
            }
        }
        let magnification = Float(value.magnification)
        entity.scale = state.startScale * magnification
    }

    @MainActor
    mutating func onEnded(value: EntityTargetValue<MagnifyGesture.Value>) {
        let state = GestureState.shared
        state.isScaling = false
        // Optionally, reset material when scaling ends
        if var model = value.entity.components[ModelComponent.self],
           var material = model.materials.first as? PhysicallyBasedMaterial {
            withAnimation(.easeInOut(duration: 1)) {
                material.baseColor.tint = .gray
                model.materials = [material]
                value.entity.components.set(model)
            }
        }
    }
}
