//  NDTree.swift
//
//
//  Created by li3zhen1 on 10/14/23.
//

/// The data structure carried by a node of NDTree.
///
/// It receives notifications when a node is added or removed on a node,
/// regardless of whether the node is internal or leaf.
/// It is designed to calculate properties like a box's center of mass.
///
/// When implementing your delegates, ensure they
/// are value types to enable memberwise copy.
public protocol KDTreeDelegate {

    /// Called when a node is added on a node, regardless of whether the node is internal or leaf.
    ///
    /// If you add `n` points to the root, this method will be called `n` times in the root delegate,
    /// although it is probably not containing points now.
    /// - Parameters:
    ///   - node: The nodeID of the node that is added.
    ///   - position: The position of the node that is added.
    @inlinable mutating func didAddNode(_ node: NodeID, at position: SIMD3<Float>)

    /// Called when a node is removed on a node, regardless of whether the node is internal or leaf.
    @inlinable mutating func didRemoveNode(_ node: NodeID, at position: SIMD3<Float>)

    /// Create new object with properties set to initial value as if the box is empty.
    ///
    /// However, you can still carry something like a closure to get information from outside.
    /// This method is called when a leaf box is splited due to the insertion of a new node in this box.
    @inlinable func spawn() -> Self
    
}
