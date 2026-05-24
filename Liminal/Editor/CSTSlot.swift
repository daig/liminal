import CambiumCore
import CambiumSelection

/// Stable identity for a CST node used by slot anchors.
///
/// Unlike `CSTAnchor`, this identifies a node itself rather than a byte position
/// inside a node. Resolution functions will later use the path and fingerprint
/// together to grade strong, weak, recovered, and lost outcomes.
public struct CSTNodeAnchor: Sendable, Equatable, Hashable {
    public let path: LiminalCSTPath
    public let fingerprint: NodeFingerprint

    public init(path: LiminalCSTPath, fingerprint: NodeFingerprint) {
        self.path = path
        self.fingerprint = fingerprint
    }
}

/// Stable identity for a reference child used by a slot boundary anchor.
public struct CSTSlotChildAnchor: Sendable, Equatable, Hashable {
    public let path: LiminalCSTPath
    public let indexInParent: UInt32
    public let fingerprint: NodeFingerprint

    public init(
        path: LiminalCSTPath,
        indexInParent: UInt32,
        fingerprint: NodeFingerprint
    ) {
        self.path = path
        self.indexInParent = indexInParent
        self.fingerprint = fingerprint
    }
}

/// Persistent boundary description for a slot anchor.
public enum CSTSlotBoundaryAnchor: Sendable, Equatable, Hashable {
    case atStart
    case atEnd
    case before(reference: CSTSlotChildAnchor)
    case after(reference: CSTSlotChildAnchor)
    case between(
        left: CSTSlotChildAnchor,
        right: CSTSlotChildAnchor,
        affinity: SyntaxPointAffinity
    )
}

/// Current-tree boundary description for a slot.
///
/// This is path/index based and does not carry fingerprints. Persistent storage
/// should use `CSTSlotAnchor` instead.
public enum CSTSlotBoundary: Sendable, Equatable, Hashable {
    case atStart
    case atEnd
    case beforeChild(index: UInt32)
    case afterChild(index: UInt32)
    case betweenChildren(
        leftIndex: UInt32,
        rightIndex: UInt32,
        affinity: SyntaxPointAffinity
    )
}

/// A direct child-boundary slot in the current CST.
///
/// This is the structural target Land should produce before Apply renders an
/// insertion. It is identified by one concrete parent node plus a boundary in
/// that parent's direct children. It intentionally carries no paste payload and
/// performs no target lookup by itself.
public struct CSTSlot: Sendable, Equatable, Hashable {
    public let parentPath: LiminalCSTPath
    public let parentKind: LiminalKind
    public let boundary: CSTSlotBoundary

    public init(
        parentPath: LiminalCSTPath,
        parentKind: LiminalKind,
        boundary: CSTSlotBoundary
    ) {
        self.parentPath = parentPath
        self.parentKind = parentKind
        self.boundary = boundary
    }
}

/// Persistent, version-independent capture of a CST slot.
public struct CSTSlotAnchor: Sendable, Equatable, Hashable {
    public let parent: CSTNodeAnchor
    public let boundary: CSTSlotBoundaryAnchor

    public init(
        parent: CSTNodeAnchor,
        boundary: CSTSlotBoundaryAnchor
    ) {
        self.parent = parent
        self.boundary = boundary
    }
}

/// Metadata for a child adjacent to a resolved slot.
public struct CSTSlotNeighbor: Sendable, Equatable, Hashable {
    public let path: LiminalCSTPath
    public let indexInParent: UInt32
    public let kind: LiminalKind
    public let textRange: TextRange
    public let fingerprint: NodeFingerprint

    public init(
        path: LiminalCSTPath,
        indexInParent: UInt32,
        kind: LiminalKind,
        textRange: TextRange,
        fingerprint: NodeFingerprint
    ) {
        self.path = path
        self.indexInParent = indexInParent
        self.kind = kind
        self.textRange = textRange
        self.fingerprint = fingerprint
    }
}

/// Current-tree execution data for a CST slot.
///
/// Apply may use this immediately to build an edit plan. Persistent marks,
/// deferred commands, and target-picking UI should store `CSTSlotAnchor`
/// instead and re-resolve it against the current tree.
public struct ResolvedCSTSlot: Sendable, Equatable, Hashable {
    public let slot: CSTSlot
    public let anchor: CSTSlotAnchor?
    public let parentHandle: SyntaxNodeHandle<LiminalLanguage>
    public let insertionChildIndex: UInt32
    public let insertionByteOffset: TextSize
    public let leftNeighbor: CSTSlotNeighbor?
    public let rightNeighbor: CSTSlotNeighbor?

    public init(
        slot: CSTSlot,
        anchor: CSTSlotAnchor?,
        parentHandle: SyntaxNodeHandle<LiminalLanguage>,
        insertionChildIndex: UInt32,
        insertionByteOffset: TextSize,
        leftNeighbor: CSTSlotNeighbor?,
        rightNeighbor: CSTSlotNeighbor?
    ) {
        self.slot = slot
        self.anchor = anchor
        self.parentHandle = parentHandle
        self.insertionChildIndex = insertionChildIndex
        self.insertionByteOffset = insertionByteOffset
        self.leftNeighbor = leftNeighbor
        self.rightNeighbor = rightNeighbor
    }
}

/// Outcome of resolving a `CSTSlotAnchor` against a tree.
public enum CSTSlotResolution: Sendable, Equatable, Hashable {
    /// Parent and boundary references resolve with matching fingerprints.
    case strong(ResolvedCSTSlot)
    /// Parent and boundary references survive, but at least one fingerprint
    /// changed.
    case weak(ResolvedCSTSlot)
    /// Exact references failed, but a meaningful enclosing slot was recovered.
    case recovered(ResolvedCSTSlot)
    /// No usable slot can be recovered.
    case lost
}
