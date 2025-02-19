import RealityKit
import SwiftUI


public extension Entity {
    var dragComponent: DragComponent? {
        get { components[DragComponent.self] }
        set { components[DragComponent.self] = newValue }
    }
    
    /// Returns the position of the entity specified in the app's coordinate system. On
    /// iOS and macOS, which don't have a device native coordinate system, scene
    /// space is often referred to as "world space".
    var scenePosition: SIMD3<Float> {
        get { position(relativeTo: nil) }
        set { setPosition(newValue, relativeTo: nil) }
    }

    var parentPosition: SIMD3<Float> {
        get { position(relativeTo: parent) }
        set { setPosition(newValue, relativeTo: parent) }
    }
    
    /// Returns the orientation of the entity specified in the app's coordinate system. On
    /// iOS and macOS, which don't have a device native coordinate system, scene
    /// space is often referred to as "world space".
    var sceneOrientation: simd_quatf {
        get { orientation(relativeTo: nil) }
        set { setOrientation(newValue, relativeTo: nil) }
    }

    var parentOrientation: simd_quatf {
        get { orientation(relativeTo: parent) }
        set { setOrientation(newValue, relativeTo: parent) }
    }
}

public extension RealityView {
    func installDrag() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .useGestureComponent()
        )

    }
}