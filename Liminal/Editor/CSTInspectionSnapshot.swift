import CambiumCore
import Foundation

/// One step in the breadcrumb chain from root to the cursor's
/// innermost containing node.
public struct CSTBreadcrumbStep: Sendable, Equatable, Hashable {
    public let kind: LiminalKind
    public let displayName: String
    public let textRange: CambiumCore.TextRange

    public init(kind: LiminalKind, displayName: String, textRange: CambiumCore.TextRange) {
        self.kind = kind
        self.displayName = displayName
        self.textRange = textRange
    }
}

/// Detail info about the innermost CST node containing the cursor.
/// Mostly diagnostic — the inspector pane displays these directly so
/// they're shaped for human consumption.
public struct CSTNodeDetails: Sendable, Equatable, Hashable {
    public let kind: LiminalKind
    public let displayName: String
    public let textRange: CambiumCore.TextRange
    /// Child-or-token indices from root to this node (Cambium's
    /// `SyntaxNodeCursor.childIndexPath()`). Useful for cross-tree
    /// stable identity when paired with a fingerprint.
    public let path: [UInt32]
    /// Cambium's content-addressed `greenHash` for this subtree.
    public let structuralHash: UInt64
    /// A short, single-line preview of the node's source text. Multi-line
    /// content is condensed; long content is truncated with an ellipsis.
    public let preview: String
}

/// Cursor position in source coordinates plus a friendlier line/column
/// pair computed from the source string.
public struct CSTCursorPosition: Sendable, Equatable, Hashable {
    public let byteOffset: TextSize
    public let line: Int        // 1-based
    public let column: Int      // 1-based
}

/// Snapshot of the editor's CST context at the cursor's current
/// position. Computed by `CSTInspector` and consumed read-only by the
/// SwiftUI inspector pane.
public struct CSTInspectionSnapshot: Sendable, Equatable, Hashable {
    public let cursor: CSTCursorPosition
    public let breadcrumb: [CSTBreadcrumbStep]
    public let node: CSTNodeDetails?
}

public extension LiminalKind {
    /// Title-cased, space-separated name suitable for the inspector
    /// pane. `paragraph` → "Paragraph", `listItem` → "List Item",
    /// `atxHeading` → "Atx Heading".
    var displayName: String {
        let raw = String(describing: self)
        guard !raw.isEmpty else { return raw }
        var result = ""
        result.reserveCapacity(raw.count + 4)
        for (i, ch) in raw.enumerated() {
            if i == 0 {
                result.append(Character(ch.uppercased()))
            } else if ch.isUppercase {
                result.append(" ")
                result.append(ch)
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

/// Compress source text for inline display: collapse runs of whitespace
/// (including newlines) into a single space, trim, and truncate.
enum CSTPreview {
    static let maxLength: Int = 60

    static func format(_ raw: String, max maxLen: Int = maxLength) -> String {
        var compacted = ""
        compacted.reserveCapacity(raw.count)
        var lastWasWhitespace = false
        for ch in raw {
            if ch.isWhitespace {
                if !lastWasWhitespace, !compacted.isEmpty {
                    compacted.append(" ")
                }
                lastWasWhitespace = true
            } else {
                compacted.append(ch)
                lastWasWhitespace = false
            }
        }
        let trimmed = compacted.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= maxLen {
            return trimmed
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLen)
        return String(trimmed[..<endIndex]) + "…"
    }
}
