import Foundation

struct VimUndoTransaction {
    let sequenceNumber: Int
    let timestamp: Date
    let edits: [VimTextEdit]
    let beforeCursorPosition: Int
    let afterCursorPosition: Int
}

struct VimUndoNavigationResult {
    let text: String
    let cursorPosition: Int
}

private struct VimUndoNode {
    let id: Int
    let parentID: Int?
    var childIDs: [Int]
    let transaction: VimUndoTransaction?
    let cursorPosition: Int
}

private struct VimActiveInsertSession {
    let startedAt: Date
    let beforeCursorPosition: Int
    var edits: [VimTextEdit]
}

final class VimUndoHistory {
    private var nodes: [Int: VimUndoNode]
    private var currentNodeID: Int
    private var activeBranchTipID: Int
    private var nextNodeID: Int = 1
    private var nextSequenceNumber: Int = 1
    private var currentTextStorage: String
    private var activeInsertSession: VimActiveInsertSession?

    init(rootText: String) {
        let rootNode = VimUndoNode(
            id: 0,
            parentID: nil,
            childIDs: [],
            transaction: nil,
            cursorPosition: 0
        )

        nodes = [rootNode.id: rootNode]
        currentNodeID = rootNode.id
        activeBranchTipID = rootNode.id
        currentTextStorage = rootText
    }

    var currentText: String {
        currentTextStorage
    }

    var hasActiveInsertSession: Bool {
        activeInsertSession != nil
    }

    func beginInsertSession(beforeCursorPosition: Int) {
        guard activeInsertSession == nil else { return }

        activeInsertSession = VimActiveInsertSession(
            startedAt: Date(),
            beforeCursorPosition: clampedCursor(beforeCursorPosition, for: currentTextStorage),
            edits: []
        )
    }

    func appendEditToActiveInsertSession(_ edit: VimTextEdit) {
        guard !isNoOp(edit) else { return }
        guard var activeInsertSession else { return }

        currentTextStorage = applying(edit, to: currentTextStorage)
        activeInsertSession.edits.append(edit)
        self.activeInsertSession = activeInsertSession
    }

    func commitInsertSession(finalCursorPosition: Int) {
        guard let activeInsertSession else { return }
        self.activeInsertSession = nil

        guard !activeInsertSession.edits.isEmpty else { return }

        let transaction = makeTransaction(
            edits: activeInsertSession.edits,
            beforeCursorPosition: activeInsertSession.beforeCursorPosition,
            afterCursorPosition: clampedCursor(finalCursorPosition, for: currentTextStorage),
            timestamp: activeInsertSession.startedAt
        )
        appendNode(for: transaction)
    }

    func commitImmediateEdits(
        _ edits: [VimTextEdit],
        beforeCursorPosition: Int,
        afterCursorPosition: Int
    ) {
        let meaningfulEdits = edits.filter { !isNoOp($0) }
        guard !meaningfulEdits.isEmpty else { return }
        let beforeText = currentTextStorage

        for edit in meaningfulEdits {
            currentTextStorage = applying(edit, to: currentTextStorage)
        }

        let transaction = makeTransaction(
            edits: meaningfulEdits,
            beforeCursorPosition: beforeCursorPosition,
            afterCursorPosition: afterCursorPosition,
            beforeText: beforeText
        )
        appendNode(for: transaction)
    }

    func undo(count: Int) -> VimUndoNavigationResult? {
        var remaining = max(count, 1)
        var changed = false

        while remaining > 0 {
            let currentNode = nodes[currentNodeID]
            guard
                let currentNode,
                let parentID = currentNode.parentID,
                let transaction = currentNode.transaction
            else {
                break
            }

            applyInverse(transaction)
            currentNodeID = parentID
            remaining -= 1
            changed = true
        }

        guard changed else { return nil }
        return navigationResult()
    }

    func redo(count: Int) -> VimUndoNavigationResult? {
        var remaining = max(count, 1)
        var changed = false

        while remaining > 0 {
            guard
                let childID = nextNodeOnActiveBranch(),
                let childNode = nodes[childID],
                let transaction = childNode.transaction
            else {
                break
            }

            applyForward(transaction)
            currentNodeID = childID
            remaining -= 1
            changed = true
        }

        guard changed else { return nil }
        return navigationResult()
    }

    private func appendNode(for transaction: VimUndoTransaction) {
        let parentID = currentNodeID
        let nodeID = nextNodeID
        nextNodeID += 1

        var parentNode = nodes[parentID]!
        parentNode.childIDs.append(nodeID)
        nodes[parentID] = parentNode

        let node = VimUndoNode(
            id: nodeID,
            parentID: parentID,
            childIDs: [],
            transaction: transaction,
            cursorPosition: clampedCursor(
                transaction.afterCursorPosition,
                for: currentTextStorage
            )
        )

        nodes[nodeID] = node
        currentNodeID = nodeID
        activeBranchTipID = nodeID
    }

    private func makeTransaction(
        edits: [VimTextEdit],
        beforeCursorPosition: Int,
        afterCursorPosition: Int,
        beforeText: String? = nil,
        timestamp: Date = Date()
    ) -> VimUndoTransaction {
        defer { nextSequenceNumber += 1 }

        return VimUndoTransaction(
            sequenceNumber: nextSequenceNumber,
            timestamp: timestamp,
            edits: edits,
            beforeCursorPosition: clampedCursor(
                beforeCursorPosition,
                for: beforeText ?? currentTextStorage
            ),
            afterCursorPosition: clampedCursor(afterCursorPosition, for: currentTextStorage)
        )
    }

    private func applyForward(_ transaction: VimUndoTransaction) {
        for edit in transaction.edits {
            currentTextStorage = applying(edit, to: currentTextStorage)
        }
    }

    private func applyInverse(_ transaction: VimUndoTransaction) {
        for edit in transaction.edits.reversed() {
            let inverseEdit = VimTextEdit(
                location: edit.location,
                removedText: edit.insertedText,
                insertedText: edit.removedText
            )
            currentTextStorage = applying(inverseEdit, to: currentTextStorage)
        }
    }

    private func nextNodeOnActiveBranch() -> Int? {
        guard currentNodeID != activeBranchTipID else { return nil }

        var walkerID = activeBranchTipID
        while let parentID = nodes[walkerID]?.parentID {
            if parentID == currentNodeID {
                return walkerID
            }
            walkerID = parentID
        }

        return nil
    }

    private func navigationResult() -> VimUndoNavigationResult {
        let cursorPosition = nodes[currentNodeID]?.cursorPosition ?? 0
        return VimUndoNavigationResult(
            text: currentTextStorage,
            cursorPosition: cursorPosition
        )
    }

    private func applying(_ edit: VimTextEdit, to text: String) -> String {
        let mutableText = NSMutableString(string: text)
        let replacedLength = (edit.removedText as NSString).length
        mutableText.replaceCharacters(
            in: NSRange(location: edit.location, length: replacedLength),
            with: edit.insertedText
        )
        return mutableText as String
    }

    private func isNoOp(_ edit: VimTextEdit) -> Bool {
        edit.removedText == edit.insertedText
    }

    private func clampedCursor(_ cursorPosition: Int, for text: String) -> Int {
        let length = (text as NSString).length
        guard length > 0 else { return 0 }
        return max(0, min(cursorPosition, length - 1))
    }
}
