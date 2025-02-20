//
//  ManyBodyForce.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

import RealityKit
/*
/// A force that simulate the many-body force.
///
/// This is a very expensive force, the complexity is `O(n log(n))`,
/// where `n` is the number of nodes. The complexity might degrade to `O(n^2)` if the nodes are too close to each other.
/// See [Manybody Force - D3](https://d3js.org/d3-force/many-body).
struct ManyBodyForce: ForceEffectProtocol {
    var parameterTypes: PhysicsBodyParameterTypes { [.position] }
    var forceMode: ForceMode { .velocity }

    //MARK: - Custom properties
    let strength: Float = 1 //TODO: set correctly
    let theta2: Float = 0.81
    let theta: Float = 0.9
//    let theta: Float {
//        didSet {
//            theta2 = theta * theta
//        }
    }
    let distanceMin: Float = 1
    let distanceMin2: Float = 1
    let distanceMax2: Float = .infinity
    let distanceMax: Float = .infinity

    let mass: Float = 1
    @usableFromInline var precalculatedMass: UnsafeArray<Vector.Scalar>! = nil

    @inlinable
    public init(
        strength: Vector.Scalar,
        nodeMass: NodeMass = .constant(1.0),
        theta: Vector.Scalar = 0.9
    ) {
        self.strength = strength
        self.mass = nodeMass
        self.theta = theta
        self.theta2 = theta * theta

    }
    



    @inlinable
    public func apply(to kinetics: inout Kinetics) {
        
        // Avoid capturing self
        let alpha = kinetics.alpha
        let theta2 = self.theta2
        let distanceMin2 = self.distanceMin2
        let distanceMax2 = self.distanceMax2
        let strength = self.strength
        let precalculatedMass = self.precalculatedMass.mutablePointer
        let positionBufferPointer = kinetics.position.mutablePointer
        // let random = kinetics.randomGenerator
        let tree = self.tree!

        let coveringBox = KDBox<Vector>.cover(of: kinetics.position)
        tree.pointee.reset(rootBox: coveringBox, rootDelegate: .init(massProvider: precalculatedMass))
        for p in kinetics.range {
            tree.pointee.add(nodeIndex: p, at: positionBufferPointer[p])
        }

        for i in kinetics.range {
            let pos = positionBufferPointer[i]
            var f = Vector.zero
            tree.pointee.visit { t in

                guard t.delegate.accumulatedCount > 0 else { return false }
                let centroid =
                    t.delegate.accumulatedMassWeightedPositions / t.delegate.accumulatedMass

                let vec = centroid - pos
                let boxWidth = (t.box.p1 - t.box.p0)[0]
                var distanceSquared =
                    (vec
                    .jiggled(by: &kinetics.randomGenerator)).lengthSquared()

                let farEnough: Bool =
                    (distanceSquared * theta2) > (boxWidth * boxWidth)

                if distanceSquared < distanceMin2 {
                    distanceSquared = (distanceMin2 * distanceSquared).squareRoot()
                }

                if farEnough {

                    guard distanceSquared < distanceMax2 else { return true }

                    /// Workaround for "The compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions"
                    let k: Vector.Scalar =
                        strength * alpha * t.delegate.accumulatedMass
                        / distanceSquared  // distanceSquared.squareRoot()

                    f += vec * k
                    return false

                } else if t.childrenBufferPointer != nil {
                    return true
                }

                if t.isFilledLeaf {

                    if t.nodeIndices!.contains(i) { return false }

                    let massAcc = t.delegate.accumulatedMass

                    let k: Vector.Scalar = strength * alpha * massAcc / distanceSquared  // distanceSquared.squareRoot()
                    f += vec * k
                    return false
                } else {
                    return true
                }
            }

            positionBufferPointer[i] += f / precalculatedMass[i]
        }
    }

    // public var kinetics: Kinetics! = nil

    @inlinable
    public mutating func bindKinetics(_ kinetics: Kinetics) {
        // self.kinetics = kinetics
        self.precalculatedMass = self.mass.calculateUnsafe(for: (kinetics.validCount))

        self.tree = .allocate(capacity: 1)
        self.tree.initialize(
            to:
                BufferedKDTree(
                    rootBox: .init(
                        p0: .init(repeating: 0),
                        p1: .init(repeating: 1)
                    ),
                    nodeCapacity: kinetics.validCount,
                    rootDelegate: MassCentroidKDTreeDelegate<Vector>(
                        massProvider: precalculatedMass.mutablePointer)
                )
        )
    }

    /// The buffered KDTree used across all ticks.
    @usableFromInline
    internal var tree:
        UnsafeMutablePointer<BufferedKDTree<Vector, MassCentroidKDTreeDelegate<Vector>>>! = nil
    
    /// Deinitialize the tree and deallocate the memory.
    /// Called when `Simulation` is deinitialized.
    @inlinable
    public func dispose() {
        self.tree.deinitialize(count: 1)
        self.tree.deallocate()
    }
}
*/
