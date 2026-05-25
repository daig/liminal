import CambiumCore
import CambiumSelection

/// Stable identity for a CST node.
///
/// This identifies a node itself rather than a byte position inside a node.
/// A slot's persistent identity is one of these (the visual-CST selected node)
/// plus a ``CSTSlotSelector`` that decides how to reinterpret it. Resolution is
/// exact-only for now (path + kind survive, fingerprint graded); content-based
/// recovery is handled by the shared node-anchor layer and is out of scope here.
public struct CSTNodeAnchor: Sendable, Equatable, Hashable {
    public let path: LiminalCSTPath
    public let fingerprint: NodeFingerprint

    public init(path: LiminalCSTPath, fingerprint: NodeFingerprint) {
        self.path = path
        self.fingerprint = fingerprint
    }
}

/// How a slot reinterprets its reference node into a parent + insertion point.
///
/// `prepend` / `append` face *inward* (the reference node is the slot's parent);
/// `before` / `after` face *outward* (the slot's parent is the reference node's
/// parent, and the reference node is the child the insertion sits beside). Child
/// specificity comes from node-to-node navigation, not from this grammar: the
/// user navigates the forest selection onto the target node, then picks a side.
public enum CSTSlotSelector: Sendable, Equatable, Hashable {
    /// Inward: slot parent = the node; insertion at its first child slot.
    case prepend
    /// Inward: slot parent = the node; insertion at its last child slot.
    case append
    /// Outward: slot parent = the node's parent; insertion before the node.
    case before
    /// Outward: slot parent = the node's parent; insertion after the node.
    case after

    public init?(commandArgument: String) {
        switch commandArgument {
        case "prepend": self = .prepend
        case "append":  self = .append
        case "before":  self = .before
        case "after":   self = .after
        default:        return nil
        }
    }

    public var commandArgument: String {
        switch self {
        case .prepend: return "prepend"
        case .append:  return "append"
        case .before:  return "before"
        case .after:   return "after"
        }
    }

    /// Argument options surfaced in the `:CSTSlot` completion popup. Order is
    /// the canonical display order.
    public static let argOptions: [ArgOption] = [
        .init(value: "prepend", description: "Insert at the start of the selected node (inward)"),
        .init(value: "append",  description: "Insert at the end of the selected node (inward)"),
        .init(value: "before",  description: "Insert before the selected node (outward)"),
        .init(value: "after",   description: "Insert after the selected node (outward)"),
    ]
}

/// Persistent, version-independent capture of a CST slot.
///
/// A slot's identity is a single reference node plus a selector. The selector
/// decides whether the node plays "container" (`prepend`/`append`) or
/// "reference child" (`before`/`after`). The slot's *parent* — the node an
/// insertion mechanically lands inside — is derived at resolution time, never
/// stored: it is the reference node itself for inward selectors, or the
/// reference node's parent for outward selectors.
public struct CSTSlotAnchor: Sendable, Equatable, Hashable {
    public let node: CSTNodeAnchor
    public let selector: CSTSlotSelector

    public init(node: CSTNodeAnchor, selector: CSTSlotSelector) {
        self.node = node
        self.selector = selector
    }
}

/// Current-tree execution data for a CST slot.
///
/// This is the only representation Apply needs: the concrete parent the
/// insertion lands inside, the child index within that parent, and the byte
/// offset to edit at. Presentation metadata (parent range, neighbor ranges) is
/// derived on demand by the overlay from `parentHandle` + `insertionChildIndex`;
/// it is deliberately not cached here. Persistent storage uses ``CSTSlotAnchor``.
public struct ResolvedCSTSlot: Sendable, Equatable, Hashable {
    public let parentHandle: SyntaxNodeHandle<LiminalLanguage>
    public let insertionChildIndex: UInt32
    public let insertionByteOffset: TextSize

    public init(
        parentHandle: SyntaxNodeHandle<LiminalLanguage>,
        insertionChildIndex: UInt32,
        insertionByteOffset: TextSize
    ) {
        self.parentHandle = parentHandle
        self.insertionChildIndex = insertionChildIndex
        self.insertionByteOffset = insertionByteOffset
    }
}

/// Outcome of resolving a ``CSTSlotAnchor`` against a tree.
public enum CSTSlotResolution: Sendable, Equatable, Hashable {
    /// The reference node resolves with a matching fingerprint.
    case strong(ResolvedCSTSlot)
    /// The reference node's path/kind survive, but its fingerprint changed.
    case weak(ResolvedCSTSlot)
    /// Exact reference failed, but a meaningful enclosing slot was recovered.
    /// Reserved for the future shared node-anchor recovery; never produced yet.
    case recovered(ResolvedCSTSlot)
    /// No usable slot can be recovered.
    case lost
}

public extension CSTNodeAnchor {
    /// Result of resolving a node anchor against the current tree.
    ///
    /// `parentHandle` / `indexInParent` are `nil` only when the node is the
    /// root (which has no parent). For every node a slot anchor captures from a
    /// visual-CST selection, the node is a child of some parent, so both are
    /// populated.
    struct Resolution {
        public let nodeHandle: SyntaxNodeHandle<LiminalLanguage>
        public let parentHandle: SyntaxNodeHandle<LiminalLanguage>?
        public let indexInParent: UInt32?
        public let fingerprintMatches: Bool
    }

    /// Resolve this node anchor against `root`, exact-only.
    ///
    /// Returns `nil` when the stored path no longer descends to a node of the
    /// recorded kind (deletion, structural drift, or a path that now crosses a
    /// token). Content drift is reported via `fingerprintMatches`, not failure.
    func resolve(in root: RootSyntax) -> Resolution? {
        root.syntax.withCursor { rootCursor -> Resolution? in
            // Root node: empty path, no parent. (Not produced by slot capture,
            // but handled so resolution is total.)
            guard let parentPath = path.droppingLast(),
                  let index = path.rawValue.last
            else {
                guard rootCursor.kind == fingerprint.kind else { return nil }
                return Resolution(
                    nodeHandle: rootCursor.makeHandle(),
                    parentHandle: nil,
                    indexInParent: nil,
                    fingerprintMatches: rootCursor.greenHash == fingerprint.contentHash
                )
            }

            return rootCursor.withDescendant(atPath: parentPath.rawValue) {
                parentCursor -> Resolution? in
                guard index < UInt32(parentCursor.childOrTokenCount) else { return nil }
                let child = parentCursor.green { green in green.child(at: Int(index)) }
                guard child.kind == fingerprint.kind else { return nil }
                guard let nodeHandle = parentCursor.withChildNode(atRawIndex: Int(index), {
                    $0.makeHandle()
                }) else { return nil }
                return Resolution(
                    nodeHandle: nodeHandle,
                    parentHandle: parentCursor.makeHandle(),
                    indexInParent: index,
                    fingerprintMatches: child.contentHash == fingerprint.contentHash
                )
            } ?? nil
        }
    }
}

public extension CSTSlotAnchor {
    /// Resolve this persistent slot anchor against the current tree.
    ///
    /// Exact-only: `.strong` when the reference node's fingerprint matches,
    /// `.weak` when its path/kind survive but the fingerprint changed, `.lost`
    /// when the node can't be resolved (or an outward selector lands on a node
    /// with no parent). `.recovered` is reserved for future node-anchor recovery.
    func resolve(in root: RootSyntax) -> CSTSlotResolution {
        guard let node = node.resolve(in: root) else { return .lost }

        // Pick the slot's parent handle and (for outward selectors) the
        // reference child's index, per the selector.
        let slotParent: SyntaxNodeHandle<LiminalLanguage>
        let referenceIndex: UInt32?
        switch selector {
        case .prepend, .append:
            slotParent = node.nodeHandle
            referenceIndex = nil
        case .before, .after:
            guard let parentHandle = node.parentHandle,
                  let idx = node.indexInParent
            else { return .lost }
            slotParent = parentHandle
            referenceIndex = idx
        }

        guard let resolved = slotParent.withCursor({ parent -> ResolvedCSTSlot? in
            let childCount = UInt32(parent.childOrTokenCount)
            let index: UInt32
            switch selector {
            case .prepend: index = contentChildBounds(of: parent)?.first ?? 0
            case .append:  index = contentChildBounds(of: parent)?.afterLast ?? childCount
            case .before:  index = referenceIndex ?? 0
            case .after:   index = (referenceIndex ?? 0) + 1
            }
            guard index <= childCount else { return nil }
            let byteOffset: TextSize = index < childCount
                ? parent.childTextRange(at: Int(index)).start
                : parent.textRange.end
            return ResolvedCSTSlot(
                parentHandle: parent.makeHandle(),
                insertionChildIndex: index,
                insertionByteOffset: byteOffset
            )
        }) else { return .lost }

        return node.fingerprintMatches ? .strong(resolved) : .weak(resolved)
    }
}

/// First and one-past-last *content* child indices of `node` — the bounds that
/// skip the node's own leading/trailing syntactic framing (the `!` before an
/// image label, the `|` around table cells, the `(` `)` around a link
/// destination, list markers, …). Returns `nil` when the node has no content
/// children (a leaf, or a node of pure framing) so inward slot callers fall
/// back to the raw child-count edges.
///
/// "Content" is anything not classified ``NavigationRole/skip`` — every stop,
/// plus the pass-through wrappers that hold content. So a slot inside a link
/// destination bounds to the URL payload token, and a slot inside a link label
/// bounds to its inline-content wrapper.
func contentChildBounds(
    of node: borrowing SyntaxNodeCursor<LiminalLanguage>
) -> (first: UInt32, afterLast: UInt32)? {
    let count = node.childOrTokenCount
    var first: Int?
    var last: Int?
    for i in 0..<count {
        let kind = node.green { $0.child(at: i).kind }
        guard LiminalCSTPolicy.navigationRole(kind) != .skip else { continue }
        if first == nil { first = i }
        last = i
    }
    guard let first, let last else { return nil }
    return (UInt32(first), UInt32(last) + 1)
}
