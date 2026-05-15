import CambiumCore
import CambiumSelection

/// Liminal-owned wrapper around Cambium's raw full-child-index node path.
///
/// `rawValue` has the same semantics as `SyntaxNodeCursor.childIndexPath()`:
/// each element is a full child index, counting both nodes and tokens.
public struct LiminalCSTPath: Sendable, Hashable, Equatable, ExpressibleByArrayLiteral,
    CustomStringConvertible
{
    public let rawValue: SyntaxNodePath

    public init(_ rawValue: SyntaxNodePath) {
        self.rawValue = rawValue
    }

    public init(arrayLiteral elements: UInt32...) {
        self.rawValue = elements
    }

    public var depth: Int {
        rawValue.count
    }

    public var isRoot: Bool {
        rawValue.isEmpty
    }

    public var description: String {
        rawValue.description
    }

    public func appending(_ childIndex: UInt32) -> LiminalCSTPath {
        LiminalCSTPath(rawValue + [childIndex])
    }

    public func droppingLast() -> LiminalCSTPath? {
        guard !rawValue.isEmpty else { return nil }
        return LiminalCSTPath(Array(rawValue.dropLast()))
    }

    public func isAncestor(of other: LiminalCSTPath) -> Bool {
        guard rawValue.count <= other.rawValue.count else { return false }
        return zip(rawValue, other.rawValue).allSatisfy { $0 == $1 }
    }

    public func isProperAncestor(of other: LiminalCSTPath) -> Bool {
        rawValue.count < other.rawValue.count && isAncestor(of: other)
    }

    public func isDescendant(of ancestor: LiminalCSTPath) -> Bool {
        ancestor.isAncestor(of: self)
    }

    public func isProperDescendant(of ancestor: LiminalCSTPath) -> Bool {
        ancestor.isProperAncestor(of: self)
    }

    public func commonAncestor(with other: LiminalCSTPath) -> LiminalCSTPath {
        var prefix: SyntaxNodePath = []
        for (lhs, rhs) in zip(rawValue, other.rawValue) {
            guard lhs == rhs else { break }
            prefix.append(lhs)
        }
        return LiminalCSTPath(prefix)
    }

    public func relativePath(from ancestor: LiminalCSTPath) -> SyntaxNodePath? {
        guard ancestor.isAncestor(of: self) else { return nil }
        return Array(rawValue.dropFirst(ancestor.rawValue.count))
    }

    /// Returns the immediate child index under `self` that contains
    /// `descendant`, or `nil` when `self` is not a proper ancestor.
    public func projectedChildIndex(containing descendant: LiminalCSTPath) -> UInt32? {
        guard isProperAncestor(of: descendant) else { return nil }
        return descendant.rawValue[rawValue.count]
    }

    public func route(to destination: LiminalCSTPath) -> LiminalCSTPathRoute {
        let commonAncestor = commonAncestor(with: destination)
        let stepsUp = rawValue.count - commonAncestor.rawValue.count
        let stepsDown = destination.relativePath(from: commonAncestor) ?? []
        return LiminalCSTPathRoute(
            source: self,
            destination: destination,
            commonAncestor: commonAncestor,
            stepsUp: stepsUp,
            stepsDown: stepsDown
        )
    }
}

/// Descriptive geometry between two CST paths.
///
/// This type intentionally does not define a paste slot. It only records how
/// to move from `source` up to `commonAncestor`, then down to `destination`.
public struct LiminalCSTPathRoute: Sendable, Hashable, Equatable {
    public let source: LiminalCSTPath
    public let destination: LiminalCSTPath
    public let commonAncestor: LiminalCSTPath
    public let stepsUp: Int
    public let stepsDown: SyntaxNodePath
}

public extension SyntaxNodeCursor where Lang == LiminalLanguage {
    var liminalCSTPath: LiminalCSTPath {
        LiminalCSTPath(childIndexPath())
    }
}

public extension SyntaxForest where Policy == LiminalCSTPolicy {
    var parentCSTPath: LiminalCSTPath {
        parent.withCursor { cursor in
            cursor.liminalCSTPath
        }
    }

    var anchorCSTPath: LiminalCSTPath {
        parentCSTPath.appending(UInt32(anchorChildIndex))
    }

    var headCSTPath: LiminalCSTPath {
        parentCSTPath.appending(UInt32(headChildIndex))
    }

    var firstCSTPath: LiminalCSTPath {
        parentCSTPath.appending(UInt32(firstChildIndex))
    }

    var lastCSTPath: LiminalCSTPath {
        parentCSTPath.appending(UInt32(lastChildIndex))
    }
}
