import CambiumCore
import CambiumIncremental
import Foundation

/// Frozen state at a vim-transaction boundary. Captured at every
/// `applyOperator` / `paste` / visual-mode delete / insert-session
/// commit, plus once at document load.
///
/// The `tree` field is a `SharedSyntaxTree` (Cambium's persistent
/// green tree). Because green trees are structurally shared,
/// holding many snapshots over the life of a document is cheap —
/// the unchanged subtrees across snapshots share storage by
/// pointer-equality.
public struct CSTUndoSnapshot: Sendable {
    public let tree: SharedSyntaxTree<LiminalLanguage>
    public let cursor: Int
    public let marks: MarkRegistry
    public let timestamp: Date

    public init(
        tree: SharedSyntaxTree<LiminalLanguage>,
        cursor: Int,
        marks: MarkRegistry,
        timestamp: Date = Date()
    ) {
        self.tree = tree
        self.cursor = cursor
        self.marks = marks
        self.timestamp = timestamp
    }
}

/// A source splice described in both sides of a transaction.
///
/// `beforeRange` is expressed in the transaction's before tree/source.
/// `afterRange` is the replacement region in the transaction's after
/// tree/source. Undo replaces `afterRange` with bytes sliced from
/// `beforeRange`; redo performs the inverse.
public struct CSTUndoTextPatch: Sendable, Hashable {
    public let beforeRange: CambiumCore.TextRange
    public let afterRange: CambiumCore.TextRange

    public init(beforeRange: CambiumCore.TextRange, afterRange: CambiumCore.TextRange) {
        self.beforeRange = beforeRange
        self.afterRange = afterRange
    }
}

public struct CSTUndoTransaction: Sendable {
    public let before: CSTUndoSnapshot
    public let after: CSTUndoSnapshot
    public let patches: [CSTUndoTextPatch]

    public init(
        before: CSTUndoSnapshot,
        after: CSTUndoSnapshot,
        patches: [CSTUndoTextPatch]
    ) {
        precondition(!patches.isEmpty, "Undo transaction must contain at least one text patch")
        self.before = before
        self.after = after
        self.patches = patches
    }
}

public enum CSTUndoDirection: Sendable {
    case undo
    case redo
}

public struct CSTUndoNavigation: Sendable {
    public let transaction: CSTUndoTransaction
    public let direction: CSTUndoDirection
    public let target: CSTUndoSnapshot

    public init(
        transaction: CSTUndoTransaction,
        direction: CSTUndoDirection,
        target: CSTUndoSnapshot
    ) {
        self.transaction = transaction
        self.direction = direction
        self.target = target
    }
}

public extension CSTUndoTextPatch {
    static func normalized(from edits: [TextEdit]) -> [CSTUndoTextPatch] {
        guard !edits.isEmpty else { return [] }

        let sorted = edits.sorted { lhs, rhs in
            lhs.range.start.rawValue < rhs.range.start.rawValue
        }
        for pair in zip(sorted, sorted.dropFirst()) {
            precondition(
                pair.0.range.end.rawValue <= pair.1.range.start.rawValue,
                "Undo patches require non-overlapping text edits"
            )
        }

        var accumulatedDelta = 0
        return sorted.map { edit in
            let oldStart = Int(edit.range.start.rawValue)
            let oldLength = Int(edit.range.length.rawValue)
            let newStart = oldStart + accumulatedDelta
            precondition(newStart >= 0, "Undo patch produced a negative after range")
            let newLength = edit.replacementUTF8.count
            let afterRange = CambiumCore.TextRange(
                start: TextSize(UInt32(newStart)),
                length: TextSize(UInt32(newLength))
            )
            accumulatedDelta += newLength - oldLength
            return CSTUndoTextPatch(beforeRange: edit.range, afterRange: afterRange)
        }
    }
}

public extension CSTUndoNavigation {
    var targetPatchRanges: [CambiumCore.TextRange] {
        switch direction {
        case .undo:
            transaction.patches.map(\.beforeRange)
        case .redo:
            transaction.patches.map(\.afterRange)
        }
    }

    var sourceEdits: [TextEdit] {
        switch direction {
        case .undo:
            transaction.patches.map { patch in
                TextEdit(
                    range: patch.afterRange,
                    replacement: transaction.before.tree.sourceSlice(patch.beforeRange)
                )
            }
        case .redo:
            transaction.patches.map { patch in
                TextEdit(
                    range: patch.beforeRange,
                    replacement: transaction.after.tree.sourceSlice(patch.afterRange)
                )
            }
        }
    }
}

public extension SharedSyntaxTree where Lang == LiminalLanguage {
    var sourceLength: TextSize {
        withRoot { root in
            root.textRange.length
        }
    }

    func sourceSlice(_ range: CambiumCore.TextRange) -> String {
        withRoot { root in
            root.withText { text in
                let bounds = CambiumCore.TextRange(
                    start: .zero,
                    length: TextSize(UInt32(text.utf8Count))
                )
                precondition(bounds.contains(range), "Undo patch range is outside the syntax tree text")
                return text.sliced(range).makeString()
            }
        }
    }

    func sourceText() -> String {
        withRoot { root in
            root.makeString()
        }
    }
}
