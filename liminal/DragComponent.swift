/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A component that handles standard drag, rotate, and scale gestures for an entity.
*/

import RealityKit
import SwiftUI

@MainActor
public final class DragGestureState {
    static let shared = DragGestureState()

    var target: Entity? = nil
    var startPosition: SIMD3<Float> = .zero
    var isDragging: Bool = false
 }

/// A component that handles gesture logic for an entity.

public struct DragComponent: Component, Codable {
    
    /// A Boolean value that indicates whether a gesture can drag the entity.
    public var canDrag: Bool = true
    
    public init() {}
    
    @MainActor
    mutating func onChanged(value: EntityTargetValue<DragGesture.Value>) {
        guard canDrag else { return }
        
        let state = DragGestureState.shared

        if state.target == nil {
            // Start dragging
            state.target = value.entity
        }

        guard let target = state.target else { fatalError("No drag target found") }

        if !state.isDragging {
            state.isDragging = true
            state.startPosition = target.scenePosition
        }
        
        let translation3D = value.convert(value.gestureValue.translation3D, from: .local, to: .scene)
        let offset = SIMD3<Float>(Float(translation3D.x), Float(translation3D.y), Float(translation3D.z))

        // let offset - value.convert(value.gestureValue.translation3D, from: .local, to: .scene)

        target.scenePosition = state.startPosition + offset

        // target.move(
        //     to: Transform(
        //         rotation: state.startOrientation,
        //         translation: targetPosition
        //     ),
        //     relativeTo: state.target!.parent!,
        //     duration: 0.1,
        //     timingFunction: .linear
        // )
        
    }
    
    @MainActor
    mutating func onEnded(value: EntityTargetValue<DragGesture.Value>) {
        DragGestureState.shared.isDragging = false
        DragGestureState.shared.target = nil
    }
}

