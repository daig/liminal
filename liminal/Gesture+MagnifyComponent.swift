import SwiftUI
import RealityKit

// Magnify gesture extension
public extension Gesture where Value == EntityTargetValue<MagnifyGesture.Value> {
    func useGestureComponent() -> some Gesture {
        onChanged { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            gestureComponent.onChanged(value: value)
            value.entity.components.set(gestureComponent)
        }
        .onEnded { value in
            guard var gestureComponent = value.entity.gestureComponent else { return }
            gestureComponent.onEnded(value: value)
            value.entity.components.set(gestureComponent)
        }
    }
}
