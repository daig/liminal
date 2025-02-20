//
//  KDBox.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
import simd
import RealityFoundation

/// A box in N-dimensional space.
///
/// - Note: `p0` is the minimum point of the box, `p1` is the maximum point of the box.
public struct KDBox: Equatable {
    public typealias V = SIMD3<Float>
    /// the minimum anchor of the box
    public var p0: V

    /// the maximum anchor of the box
    public var p1: V

    /// Create a box with 2 anchors.
    ///
    /// - Parameters:
    ///   - p0: anchor
    ///   - p1: another anchor in the diagonal position of `p0`
    /// - Note: `p0` you pass does not have to be minimum point of the box.
    ///         `p1` does not have to be maximum point of the box. The initializer will
    ///         automatically adjust the order of `p0` and `p1` to make sure `p0` is the
    ///        minimum point of the box and `p1` is the maximum point of the box.
    @inlinable
    public init(p0: V, p1: V) {
        self.p0 = pointwiseMin(p0, p1)
        self.p1 = pointwiseMax(p0, p1)
    }

    @inlinable
    internal init(uncheckedP0: V, uncheckedP1: V) {
        // assert(pMin != pMax, "NdBox was initialized with 2 same anchor")
        self.p0 = uncheckedP0
        self.p1 = uncheckedP1
    }


}

extension KDBox {
    /// Create a box with 2 anchors.
    /// - Parameters:
    ///   - p0: anchor
    ///   - p1: another anchor in the diagonal position of `p0`
    /// - Note: `p0` you pass does not have to be minimum point of the box.
    ///         `p1` does not have to be maximum point of the box. The initializer will
    ///         automatically adjust the order of `p0` and `p1` to make sure `p0` is the
    ///        minimum point of the box and `p1` is the maximum point of the box.
    @inlinable
    public init(_ p0: V, _ p1: V) { self.init(p0: p0, p1: p1) }
    
    @inlinable
    @inline(__always)
    var diagnalVector: V { return p1 - p0 }

    @inlinable
    static var zero: Self {
        return Self(uncheckedP0: .zero, uncheckedP1: .zero) }

    @inlinable
    @inline(__always)
    var center: V { (p1 + p0) / 2.0 }

    /// Test if the box contains a point.
    /// - Parameter point: N dimensional point
    /// - Returns: `true` if the box contains the point, `false` otherwise.
    ///            The boundary test is similar to ..< operator.
    @inlinable
    @inline(__always)
//    func contains(_ point: V) -> Bool {
//        return !any((p0 .> point) .| (point .>= p1)) }
        func contains(_ point: V) -> Bool {
            return !any((p0 .> point) .| (point .> p1)) // Inclusive upper bound
        }

    
    @inlinable func getCorner(of direction: Int) -> V {
        var mask = SIMDMask<V.MaskStorage>()

        for i in 0..<V.scalarCount {
            mask[i] = ((direction >> i) & 0b1) == 1 }
        return p0.replacing(with: p1, where: mask)
    }

    /// Get the small box that contains a list points and guarantees the box's size is at least 1x..x1.
    ///
    /// - Parameter points: The points to be covered.
    /// - Returns: The box that contains all the points.
    @inlinable public static func cover(of points: [V]) -> Self {

        var _p0 = points[0]
        var _p1 = points[0]

        for p in points {

            _p0 = pointwiseMin(p, _p0)
            _p1 = pointwiseMax(p, _p1)
        }

        #if DEBUG
            let _box = Self(_p0, _p1)
            assert(
                points.allSatisfy { p in
                    _box.contains(p)
                })
        #endif

        return Self(_p0, _p1)
    }

    @inlinable public static func cover(of points: UnsafeArray<V>) -> Self {

        var _p0 = points[0]
        var _p1 = points[0]

        for pi in 0..<points.header {
            let p = points[pi]

            _p0 = pointwiseMin(p, _p0)
            _p1 = pointwiseMax(p, _p1) }
        return Self(_p0, _p1 + 1)
    }
    
    /// Get the small box that contains a buffer of points (UnsafeForceEffectBuffer version).
        @inlinable
        public static func cover(of buffer: UnsafeForceEffectBuffer<SIMD3<Float>>, count: Int) -> Self {
            precondition(count > 0, "Cannot compute cover of an empty buffer")
            var _p0 = buffer[0]
            var _p1 = buffer[0]
            for i in 1..<count {
                let p = buffer[i]
                _p0 = pointwiseMin(p, _p0)
                _p1 = pointwiseMax(p, _p1)
            }
            #if DEBUG
                let _box = Self(_p0, _p1)
                assert((0..<count).allSatisfy { i in _box.contains(buffer[i]) })
            #endif
            return Self(_p0, _p1)
        }
}
