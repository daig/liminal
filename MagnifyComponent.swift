//
//  MagnifyComponent.swift

//  liminal
//
//  Created by David Girardo on 2/20/25.
//

import RealityKit
import SwiftUI

public struct MagnifyComponent: Component, Codable {
    
    /// A Boolean value that indicates whether a gesture can drag the entity.
    public var canDrag: Bool = true
    
    public init() {}
    
    @MainActor
    mutating func onChanged(value: EntityTargetValue<DragGesture.Value>) {
        guard canDrag else { return }
        
        let state = GestureState.shared

        if state.target == nil {
            // Start dragging
            state.target = value.entity
        }

        guard let target = state.target else { fatalError("No drag target found") }

        if !state.isDragging {
            state.isDragging = true
            state.startPosition = target.scenePosition
            
            // Only update material when dragging starts
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

        // target.move(
        //     to: Transform(
        //         rotation: target.sceneOrientation,
        //         translation: state.startPosition + offset
        //     ),
        //     relativeTo: nil,
        //     duration: 0.1,
        //     timingFunction: .linear
        // )
    }
    
    @MainActor
    mutating func onEnded(value: EntityTargetValue<DragGesture.Value>) {
        GestureState.shared.isDragging = false
        GestureState.shared.target = nil

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
