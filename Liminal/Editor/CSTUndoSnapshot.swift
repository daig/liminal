import CambiumCore
import Foundation

/// Frozen state at a vim-transaction boundary. Captured at every
/// `applyOperator` / `paste` / visual-mode delete / insert-session
/// commit, plus once at document load. Restored wholesale on undo
/// (or redo).
///
/// The `tree` field is a `SharedSyntaxTree` (Cambium's persistent
/// green tree). Because green trees are structurally shared,
/// holding many snapshots over the life of a document is cheap —
/// the unchanged subtrees across snapshots share storage by
/// pointer-equality.
///
/// `source` is cached alongside the tree (it is `tree.source` in
/// principle) so the install path can replace the text view's
/// content without re-deriving the source from the tree.
public struct CSTUndoSnapshot: Sendable {
    public let tree: SharedSyntaxTree<LiminalLanguage>
    public let source: String
    public let cursor: Int
    public let marks: MarkRegistry
    public let timestamp: Date

    public init(
        tree: SharedSyntaxTree<LiminalLanguage>,
        source: String,
        cursor: Int,
        marks: MarkRegistry,
        timestamp: Date = Date()
    ) {
        self.tree = tree
        self.source = source
        self.cursor = cursor
        self.marks = marks
        self.timestamp = timestamp
    }
}

/// Implemented by the SwiftUI Coordinator. The document holds a
/// weak reference and calls into it from the undo path to push the
/// installed snapshot's source + cursor into the underlying NSTextView.
@MainActor
public protocol CSTSnapshotInstaller: AnyObject {
    func applyInstalledSnapshot(_ snap: CSTUndoSnapshot)
    /// The text view's current cursor offset, used by the document
    /// when committing an insert session triggered by ⌘Z.
    func currentCursorForUndo() -> Int
}
