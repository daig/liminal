import CambiumCore
import Combine
import Foundation

/// Computes and publishes `CSTInspectionSnapshot` whenever the cursor
/// moves or the document changes. The SwiftUI inspector pane observes
/// the snapshot and re-renders.
///
/// AppKit-free: the caller hands in a byte offset and a `RootSyntax`;
/// this class does the tree walk and the line/column math.
@MainActor
public final class CSTInspector: ObservableObject {
    @Published public private(set) var snapshot: CSTInspectionSnapshot?

    public nonisolated init() {}

    /// Build a fresh snapshot at `cursorByteOffset` against `root` /
    /// `source`. Clears the snapshot when the inputs aren't usable
    /// (no parse result yet, etc.).
    public func refresh(
        cursorByteOffset: Int?,
        root: RootSyntax?,
        source: String
    ) {
        guard let offset = cursorByteOffset, let root else {
            if snapshot != nil { snapshot = nil }
            return
        }
        let next = Self.makeSnapshot(
            byteOffset: TextSize(UInt32(max(0, offset))),
            root: root,
            source: source
        )
        guard next != snapshot else { return }
        snapshot = next
    }

    /// Pure builder — pulled out so tests can exercise it directly.
    public static func makeSnapshot(
        byteOffset: TextSize,
        root: RootSyntax,
        source: String
    ) -> CSTInspectionSnapshot {
        let position = makeCursorPosition(byteOffset: byteOffset, in: source)
        var breadcrumb: [CSTBreadcrumbStep] = []
        var details: CSTNodeDetails?

        root.syntax.withCursor { cursor in
            walk(cursor, offset: byteOffset, into: &breadcrumb)
            // The innermost cursor is the last breadcrumb step. To pull
            // path + greenHash + preview we re-walk to it via path
            // because `cursor` is borrowed and we can't keep a reference
            // around outside `withCursor`.
        }
        // Resolve details against the innermost node — find the path
        // from breadcrumb's structure (a sibling pass that captures path
        // info during descent would be more efficient, but this is cold
        // enough that the second walk is fine).
        if !breadcrumb.isEmpty {
            details = makeDetails(byteOffset: byteOffset, root: root)
        }
        return CSTInspectionSnapshot(
            cursor: position,
            breadcrumb: breadcrumb,
            node: details
        )
    }

    // MARK: - Tree walking

    private static func walk(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        offset: TextSize,
        into steps: inout [CSTBreadcrumbStep]
    ) {
        let kind = LiminalLanguage.kind(for: cursor.rawKind)
        steps.append(CSTBreadcrumbStep(
            kind: kind,
            displayName: kind.displayName,
            textRange: cursor.textRange
        ))
        var descended = false
        cursor.forEachChild { child in
            guard !descended else { return }
            let r = child.textRange
            let start = r.start.rawValue
            let end = start + r.length.rawValue
            if start <= offset.rawValue && offset.rawValue < end {
                descended = true
                walk(child, offset: offset, into: &steps)
            }
        }
    }

    private static func makeDetails(
        byteOffset: TextSize,
        root: RootSyntax
    ) -> CSTNodeDetails? {
        var details: CSTNodeDetails?
        root.syntax.withCursor { cursor in
            captureInnermost(cursor, offset: byteOffset, into: &details)
        }
        return details
    }

    private static func captureInnermost(
        _ cursor: borrowing SyntaxNodeCursor<LiminalLanguage>,
        offset: TextSize,
        into details: inout CSTNodeDetails?
    ) {
        var descended = false
        cursor.forEachChild { child in
            guard !descended else { return }
            let r = child.textRange
            let start = r.start.rawValue
            let end = start + r.length.rawValue
            if start <= offset.rawValue && offset.rawValue < end {
                descended = true
                captureInnermost(child, offset: offset, into: &details)
            }
        }
        guard !descended else { return }
        let kind = LiminalLanguage.kind(for: cursor.rawKind)
        details = CSTNodeDetails(
            kind: kind,
            displayName: kind.displayName,
            textRange: cursor.textRange,
            path: cursor.childIndexPath(),
            structuralHash: cursor.greenHash,
            preview: CSTPreview.format(cursor.makeString())
        )
    }

    // MARK: - Line / column

    /// Compute 1-based (line, column) from a UTF-8 byte offset in
    /// `source`. Tabs aren't expanded; column counts bytes within the
    /// line — fine for diagnostic display.
    private static func makeCursorPosition(
        byteOffset: TextSize,
        in source: String
    ) -> CSTCursorPosition {
        let utf8 = source.utf8
        let target = Int(byteOffset.rawValue)
        var line = 1
        var lastLineStart = 0
        var byteIndex = 0
        for byte in utf8 {
            if byteIndex >= target { break }
            if byte == 0x0A { // '\n'
                line += 1
                lastLineStart = byteIndex + 1
            }
            byteIndex += 1
        }
        let column = max(1, byteIndex - lastLineStart + 1)
        return CSTCursorPosition(
            byteOffset: byteOffset,
            line: line,
            column: column
        )
    }
}
