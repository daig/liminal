import CambiumCore
import CambiumIncremental

/// Linear vim-style undo history. One per document.
///
/// Each entry is a transaction with a before tree, an after tree, and
/// byte-range patches that describe the changed regions on both sides.
/// The history deliberately does not register with AppKit's UndoManager:
/// `u` / redo walk this transaction list directly.
@MainActor
public final class CSTUndoHistory {
    public private(set) var rootSnapshot: CSTUndoSnapshot?
    public private(set) var transactions: [CSTUndoTransaction] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var currentSnapshot: CSTUndoSnapshot?

    private var insertSession: InsertSession?

    /// `nonisolated` so the document — which is constructed off the
    /// MainActor by SwiftUI's `DocumentGroup` — can hold one as a
    /// stored property. All mutating methods stay MainActor-bound.
    public nonisolated init() {}

    public var canUndo: Bool { currentIndex > 0 }
    public var canRedo: Bool { currentIndex < transactions.count }
    public var insertSessionActive: Bool { insertSession != nil }
    public var depth: Int { (rootSnapshot == nil ? 0 : 1) + transactions.count }

    public func reset(initial: CSTUndoSnapshot) {
        rootSnapshot = initial
        transactions = []
        currentIndex = 0
        currentSnapshot = initial
        insertSession = nil
    }

    @discardableResult
    public func recordTransaction(
        before: CSTUndoSnapshot,
        after: CSTUndoSnapshot,
        edits: [TextEdit]
    ) -> CSTUndoTransaction? {
        recordTransaction(
            before: before,
            after: after,
            patches: CSTUndoTextPatch.normalized(from: edits)
        )
    }

    @discardableResult
    public func recordTransaction(
        before: CSTUndoSnapshot,
        after: CSTUndoSnapshot,
        patches: [CSTUndoTextPatch]
    ) -> CSTUndoTransaction? {
        guard !patches.isEmpty else { return nil }
        let transaction = CSTUndoTransaction(
            before: before,
            after: after,
            patches: patches
        )
        if currentIndex < transactions.count {
            transactions.removeSubrange(currentIndex...)
        }
        transactions.append(transaction)
        currentIndex = transactions.count
        currentSnapshot = after
        return transaction
    }

    public func beginInsertSession(at entry: CSTUndoSnapshot) {
        guard insertSession == nil else { return }
        insertSession = InsertSession(entry: entry)
    }

    public func appendInsertEdits(_ edits: [TextEdit]) {
        guard !edits.isEmpty else { return }
        guard var session = insertSession else {
            preconditionFailure("Insert edits recorded outside an insert undo session")
        }
        session.append(contentsOf: edits)
        insertSession = session
    }

    @discardableResult
    public func commitInsertSession(after: CSTUndoSnapshot) -> CSTUndoTransaction? {
        guard let session = insertSession else { return nil }
        insertSession = nil
        return recordTransaction(
            before: session.entry,
            after: after,
            patches: session.patches
        )
    }

    public func discardInsertSession() {
        insertSession = nil
    }

    public func undoStep() -> CSTUndoNavigation? {
        guard canUndo else { return nil }
        let transaction = transactions[currentIndex - 1]
        currentIndex -= 1
        currentSnapshot = transaction.before
        return CSTUndoNavigation(
            transaction: transaction,
            direction: .undo,
            target: transaction.before
        )
    }

    public func redoStep() -> CSTUndoNavigation? {
        guard canRedo else { return nil }
        let transaction = transactions[currentIndex]
        currentIndex += 1
        currentSnapshot = transaction.after
        return CSTUndoNavigation(
            transaction: transaction,
            direction: .redo,
            target: transaction.after
        )
    }

    private struct InsertSession {
        let entry: CSTUndoSnapshot
        private var pieces: [Piece]

        init(entry: CSTUndoSnapshot) {
            self.entry = entry
            let length = Int(entry.tree.sourceLength.rawValue)
            self.pieces = length > 0 ? [.original(start: 0, length: length)] : []
        }

        mutating func append(contentsOf edits: [TextEdit]) {
            for edit in edits {
                apply(edit)
            }
        }

        var patches: [CSTUndoTextPatch] {
            let beforeLength = Int(entry.tree.sourceLength.rawValue)
            let afterLength = pieces.reduce(0) { $0 + $1.length }
            let prefix = unchangedPrefixLength()
            let suffix = unchangedSuffixLength(
                beforeLength: beforeLength,
                afterLength: afterLength,
                prefix: prefix
            )
            let beforeStart = prefix
            let beforeEnd = beforeLength - suffix
            let afterStart = prefix
            let afterEnd = afterLength - suffix
            precondition(beforeEnd >= beforeStart, "Insert-session before patch range inverted")
            precondition(afterEnd >= afterStart, "Insert-session after patch range inverted")
            guard beforeEnd > beforeStart || afterEnd > afterStart else { return [] }
            return [
                CSTUndoTextPatch(
                    beforeRange: TextRange(
                        start: TextSize(UInt32(beforeStart)),
                        length: TextSize(UInt32(beforeEnd - beforeStart))
                    ),
                    afterRange: TextRange(
                        start: TextSize(UInt32(afterStart)),
                        length: TextSize(UInt32(afterEnd - afterStart))
                    )
                )
            ]
        }

        private mutating func apply(_ edit: TextEdit) {
            let start = Int(edit.range.start.rawValue)
            let end = Int(edit.range.end.rawValue)
            precondition(start <= end, "Insert-session edit range inverted")
            precondition(end <= currentLength, "Insert-session edit range out of bounds")
            let startIndex = split(at: start)
            let endIndex = split(at: end)
            pieces.removeSubrange(startIndex..<endIndex)
            if !edit.replacementUTF8.isEmpty {
                pieces.insert(
                    .inserted(length: edit.replacementUTF8.count),
                    at: startIndex
                )
            }
            coalesce()
        }

        private var currentLength: Int {
            pieces.reduce(0) { $0 + $1.length }
        }

        private mutating func split(at offset: Int) -> Int {
            precondition(offset >= 0 && offset <= currentLength, "Split offset out of bounds")
            var position = 0
            var index = pieces.startIndex
            while index < pieces.endIndex {
                let piece = pieces[index]
                let next = position + piece.length
                if offset == position {
                    return index
                }
                if offset == next {
                    return pieces.index(after: index)
                }
                if offset < next {
                    let leftLength = offset - position
                    let rightLength = next - offset
                    let replacement: [Piece]
                    switch piece {
                    case .original(let start, _):
                        replacement = [
                            .original(start: start, length: leftLength),
                            .original(start: start + leftLength, length: rightLength)
                        ]
                    case .inserted:
                        replacement = [
                            .inserted(length: leftLength),
                            .inserted(length: rightLength)
                        ]
                    }
                    pieces.replaceSubrange(index...index, with: replacement)
                    return pieces.index(after: index)
                }
                position = next
                index = pieces.index(after: index)
            }
            return pieces.endIndex
        }

        private mutating func coalesce() {
            guard !pieces.isEmpty else { return }
            var merged: [Piece] = []
            for piece in pieces where piece.length > 0 {
                if let last = merged.last, let combined = last.combined(with: piece) {
                    merged[merged.count - 1] = combined
                } else {
                    merged.append(piece)
                }
            }
            pieces = merged
        }

        private func unchangedPrefixLength() -> Int {
            var expectedStart = 0
            var prefix = 0
            for piece in pieces {
                guard case .original(let start, let length) = piece,
                      start == expectedStart
                else { break }
                prefix += length
                expectedStart += length
            }
            return prefix
        }

        private func unchangedSuffixLength(
            beforeLength: Int,
            afterLength: Int,
            prefix: Int
        ) -> Int {
            var expectedEnd = beforeLength
            var suffix = 0
            for piece in pieces.reversed() {
                guard case .original(let start, let length) = piece,
                      start + length == expectedEnd
                else { break }
                suffix += length
                expectedEnd = start
            }
            return min(suffix, beforeLength - prefix, afterLength - prefix)
        }
    }

    private enum Piece {
        case original(start: Int, length: Int)
        case inserted(length: Int)

        var length: Int {
            switch self {
            case .original(_, let length), .inserted(let length):
                length
            }
        }

        func combined(with other: Piece) -> Piece? {
            switch (self, other) {
            case (.original(let lhsStart, let lhsLength), .original(let rhsStart, let rhsLength))
                where lhsStart + lhsLength == rhsStart:
                .original(start: lhsStart, length: lhsLength + rhsLength)
            case (.inserted(let lhsLength), .inserted(let rhsLength)):
                .inserted(length: lhsLength + rhsLength)
            default:
                nil
            }
        }
    }
}
