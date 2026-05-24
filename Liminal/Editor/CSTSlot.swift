import CambiumCore
import CambiumSelection

/// Stable identifier for a typed child-sequence role that can host a CST slot.
///
/// The string form is intentionally open-ended so new grammar roles can be
/// added without changing this data model. Known roles are exposed as constants
/// for the structural paste and motion grammar documented today.
public struct CSTSlotRole: Sendable, Equatable, Hashable, RawRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

public extension CSTSlotRole {
    static let rootDocumentItems: CSTSlotRole = "root.documentItems"
    static let listItems: CSTSlotRole = "list.items"
    static let listItemInterior: CSTSlotRole = "listItem.interior"
    static let blockQuoteDocumentItems: CSTSlotRole = "blockQuote.documentItems"
    static let pipeTableRows: CSTSlotRole = "pipeTable.rows"
    static let pipeTableRowCells: CSTSlotRole = "pipeTableRow.cells"
    static let inlineContentChildren: CSTSlotRole = "inlineContent.children"
    static let fieldsChildren: CSTSlotRole = "fields.children"
    static let listValueValues: CSTSlotRole = "listValue.values"
    static let recordValueFields: CSTSlotRole = "recordValue.fields"
    static let typedBlockDocumentItems: CSTSlotRole = "typedBlock.documentItems"
    static let schemaBodyDocumentItems: CSTSlotRole = "schemaBody.documentItems"
    static let templateBodyDocumentItems: CSTSlotRole = "templateBody.documentItems"
    static let blockLiteralDocumentItems: CSTSlotRole = "blockLiteral.documentItems"
}

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

/// A typed child-boundary slot in the current CST.
///
/// This is the structural target Land should produce before Apply renders an
/// insertion. It intentionally carries no paste payload and performs no target
/// lookup by itself.
public struct CSTSlot: Sendable, Equatable, Hashable {
    public let parentPath: LiminalCSTPath
    public let parentKind: LiminalKind
    public let role: CSTSlotRole
    public let boundary: CSTSlotBoundary

    public init(
        parentPath: LiminalCSTPath,
        parentKind: LiminalKind,
        role: CSTSlotRole,
        boundary: CSTSlotBoundary
    ) {
        self.parentPath = parentPath
        self.parentKind = parentKind
        self.role = role
        self.boundary = boundary
    }
}

/// Persistent, version-independent capture of a CST slot.
public struct CSTSlotAnchor: Sendable, Equatable, Hashable {
    public let parent: CSTNodeAnchor
    public let role: CSTSlotRole
    public let boundary: CSTSlotBoundaryAnchor

    public init(
        parent: CSTNodeAnchor,
        role: CSTSlotRole,
        boundary: CSTSlotBoundaryAnchor
    ) {
        self.parent = parent
        self.role = role
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
    /// Parent/child roles survive, but at least one fingerprint changed.
    case weak(ResolvedCSTSlot)
    /// Exact references failed, but a meaningful enclosing slot was recovered.
    case recovered(ResolvedCSTSlot)
    /// No usable slot can be recovered.
    case lost
}
