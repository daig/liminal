import RealityKit
import SwiftUI
import UIKit


public extension Entity {
    var gestureComponent: GestureComponent? {
        get { components[GestureComponent.self] }
        set { components[GestureComponent.self] = newValue }
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
    internal func installGestures(graphData: GraphData, openWindow: OpenWindowAction) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .useGestureComponent()
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let entity = value.entity
                    if let nodeComponent = entity.components[NodeComponent.self] {
                        let nodeIndex = nodeComponent.index
                        switch graphData.contents[nodeIndex.id] {
                        case .markdown(let text):
                            openWindow(id: "editor", value: NoteData(title: graphData.names[nodeIndex.id], content: text))
                        case .pdf(let url):
                            openWindow(id: "pdfViewer", value: url)
                        }
                    }
                }
        )
    }
}

extension SIMD3<Float> {
    public static var clusterDistance: Float {
        return 1e-5
    }
    public static var clusterDistanceSquared: Float {
        return clusterDistance * clusterDistance
    }
    @inlinable
    public func distanceSquared(to point: SIMD3<Scalar>) -> Scalar {
        return simd_distance_squared(self, point)
    }

    @inlinable
    public func distance(to point: SIMD3<Scalar>) -> Scalar {
        return simd_distance(self, point)
    }

    @inlinable
    public func lengthSquared() -> Scalar {
        return simd_length_squared(self)
    }

    @inlinable
    public func length() -> Scalar {
        return simd_fast_length(self)
    }

}
