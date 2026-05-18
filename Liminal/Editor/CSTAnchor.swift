import CambiumCore

/// Compact metadata about a CST node, captured at anchor time. Combines
/// the semantic kind with Cambium's content-addressed `greenHash` so we
/// can distinguish "still the same node" from "completely replaced with
/// something else at the same path".
public struct NodeFingerprint: Sendable, Equatable, Hashable {
    public let kind: LiminalKind
    public let contentHash: ContentHash

    public init(kind: LiminalKind, contentHash: ContentHash) {
        self.kind = kind
        self.contentHash = contentHash
    }
}

/// Anchors a position to a specific point inside a CST node so it can be
/// re-resolved after intervening edits as long as the marked node
/// (or a meaningful enclosing ancestor) still exists.
///
/// The path comes from Cambium's `SyntaxNodeCursor.childIndexPath()` —
/// the sequence of child indices from root to the target. The internal
/// offset is a byte offset within that node's `textRange`. The
/// fingerprint validates that the path still resolves to a node of the
/// expected shape; if not, resolution falls through a recovery ladder.
public struct CSTAnchor: Sendable, Equatable, Hashable {
    public let path: [UInt32]
    public let internalOffset: TextSize
    public let fingerprint: NodeFingerprint

    public init(
        path: [UInt32],
        internalOffset: TextSize,
        fingerprint: NodeFingerprint
    ) {
        self.path = path
        self.internalOffset = internalOffset
        self.fingerprint = fingerprint
    }
}

/// Outcome of resolving a `CSTAnchor` against a tree.
public enum AnchorResolution: Sendable, Equatable {
    /// Path resolves and the structural hash matches — the node is
    /// unchanged. The byte offset is `nodeStart + internalOffset`.
    case strong(byteOffset: TextSize)
    /// Path resolves to a node of the same kind but with different
    /// content (intra-node edit). `internalOffset` is clamped to the
    /// new node length.
    case weak(byteOffset: TextSize)
    /// Path no longer resolves to a node of the expected kind. The
    /// resolver walked up to the deepest path-prefix that does resolve
    /// and reports the start of that ancestor.
    case recovered(byteOffset: TextSize)
    /// Anchor is fully lost — even the root path failed (effectively
    /// only happens if the tree itself is gone).
    case lost
}

public extension CSTAnchor {

    /// Build an anchor for the byte offset `offset` in `root`. Descends
    /// to the innermost node whose range contains the offset; the
    /// anchor's `internalOffset` is the delta from that node's start.
    /// Returns nil only if the root cursor itself is unusable (e.g.,
    /// offset is past end of an empty tree).
    static func atSourceOffset(
        _ offset: TextSize,
        in root: RootSyntax
    ) -> CSTAnchor? {
        var found: CSTAnchor?
        root.syntax.withCursor { cursor in
            descendInnermost(cursor, offset: offset, into: &found)
        }
        return found
    }

    /// Resolve this anchor against `root`. Walks the stored path; on
    /// success compares fingerprints. On kind mismatch or unresolved
    /// path, falls back to ancestor recovery.
    func resolve(in root: RootSyntax) -> AnchorResolution {
        return root.syntax.withCursor { rootCursor -> AnchorResolution in
            // Step 1: try the exact path.
            let exactResult: AnchorResolution? = rootCursor.withDescendant(
                atPath: path
            ) { descendant -> AnchorResolution? in
                let nodeStart = descendant.textRange.start.rawValue
                let nodeLen = descendant.textLength.rawValue
                let descendantKind = LiminalLanguage.kind(for: descendant.rawKind)
                guard descendantKind == fingerprint.kind else {
                    return nil  // signal: try recovery
                }
                if descendant.greenHash == fingerprint.contentHash {
                    let off = min(internalOffset.rawValue, nodeLen)
                    return .strong(byteOffset: TextSize(nodeStart + off))
                }
                let clamped = min(internalOffset.rawValue, nodeLen)
                return .weak(byteOffset: TextSize(nodeStart + clamped))
            } ?? nil  // outer Optional from withDescendant returning nil

            if let exactResult { return exactResult }

            // Step 2: recovery ladder — try shorter path prefixes.
            return Self.recoverAncestor(in: rootCursor, fullPath: path)
        }
    }

    // MARK: - Helpers

    /// Recursive descent that records the deepest containing node's
    /// path + fingerprint. The cursor is borrowed; recursion happens
    /// inside `forEachChild`'s closure so the borrow scope is valid.
    private static func descendInnermost(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        offset: TextSize,
        into found: inout CSTAnchor?
    ) {
        var descended = false
        cursor.forEachChild { child in
            guard !descended else { return }
            let range = child.textRange
            // Half-open containment: [start, start+length). Offsets at the
            // very end of a node fall through to the parent.
            let childStart = range.start.rawValue
            let childEnd = childStart + range.length.rawValue
            if childStart <= offset.rawValue && offset.rawValue < childEnd {
                descended = true
                descendInnermost(child, offset: offset, into: &found)
            }
        }
        guard !descended else { return }
        // No child contained the offset — this cursor IS the innermost.
        let nodeStart = cursor.textRange.start.rawValue
        let delta = TextSize(
            offset.rawValue >= nodeStart
                ? offset.rawValue - nodeStart
                : 0
        )
        found = CSTAnchor(
            path: cursor.childIndexPath(),
            internalOffset: delta,
            fingerprint: NodeFingerprint(
                kind: LiminalLanguage.kind(for: cursor.rawKind),
                contentHash: cursor.greenHash
            )
        )
    }

    /// Walk shorter prefixes of `fullPath` until one resolves to a node;
    /// report its start as a `.recovered` byte offset.
    private static func recoverAncestor(
        in rootCursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        fullPath: [UInt32]
    ) -> AnchorResolution {
        // Try from longest valid prefix down to the root (empty path).
        for prefixLen in stride(from: max(0, fullPath.count - 1), through: 0, by: -1) {
            let prefix = Array(fullPath.prefix(prefixLen))
            if let resolved = rootCursor.withDescendant(atPath: prefix, { ancestor in
                AnchorResolution.recovered(byteOffset: ancestor.textRange.start)
            }) {
                return resolved
            }
        }
        return .lost
    }
}
