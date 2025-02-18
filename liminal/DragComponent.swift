/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A component that handles standard drag, rotate, and scale gestures for an entity.
*/

import RealityKit
import SwiftUI

@MainActor
public final class DragGestureState {
    static let shared = DragGestureState()
    
    struct DraggingState {
        var target: Entity
        var startPosition: SIMD3<Float>
        var startOrientation: simd_quatf
    }
    
    var state: DraggingState? = nil
    
 }

/// A component that handles gesture logic for an entity.

public struct GestureComponent: Component, Codable {
    
    /// A Boolean value that indicates whether a gesture can drag the entity.
    public var canDrag: Bool = true
    
    public init() {}
    
    @MainActor
    mutating func onChanged(value: EntityTargetValue<DragGesture.Value>) {
        guard canDrag else { return }
        
        let state = DragGestureState.shared

        if state.state == nil {
            // Start dragging
            state.state = DragGestureState.DraggingState(
                target: value.entity,
                startPosition: value.entity.scenePosition,
                startOrientation: value.entity.orientation(relativeTo: nil)
            )
        }
        
        if let draggingState = state.state {
            let translation3D = value.convert(value.gestureValue.translation3D, from: .local, to: .scene)
            let offset = SIMD3<Float>(x: Float(translation3D.x),
                                    y: Float(translation3D.y),
                                    z: Float(translation3D.z))
            
            draggingState.target.scenePosition = draggingState.startPosition + offset
            draggingState.target.setOrientation(draggingState.startOrientation, relativeTo: nil)
        }
    }
    
    @MainActor
    mutating func onEnded(value: EntityTargetValue<DragGesture.Value>) {
        DragGestureState.shared.state = nil
    }
}

