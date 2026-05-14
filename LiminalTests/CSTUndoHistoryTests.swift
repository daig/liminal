import CambiumCore
import CambiumIncremental
import Testing
@testable import Liminal

@Suite("CSTUndoHistory")
@MainActor
struct CSTUndoHistoryTests {

    private func makeSnapshot(
        _ source: String,
        cursor: Int = 0,
        marks: MarkRegistry = MarkRegistry()
    ) throws -> CSTUndoSnapshot {
        let session = LiminalEditorSession(source: source)
        let parsed = try session.parse()
        return CSTUndoSnapshot(
            tree: parsed.tree,
            cursor: cursor,
            marks: marks
        )
    }

    private func edit(
        start: UInt32,
        length: UInt32,
        replacement: String
    ) -> TextEdit {
        TextEdit(
            range: TextRange(
                start: TextSize(start),
                length: TextSize(length)
            ),
            replacement: replacement
        )
    }

    private func apply(_ edits: [TextEdit], to source: String) throws -> String {
        try LiminalEditorSession.applyingEdits(edits, to: source)
    }

    @Test("a fresh history is empty")
    func empty() {
        let h = CSTUndoHistory()
        #expect(h.depth == 0)
        #expect(h.canUndo == false)
        #expect(h.canRedo == false)
        #expect(h.insertSessionActive == false)
    }

    @Test("reset(initial:) installs the root snapshot")
    func resetInitial() throws {
        let h = CSTUndoHistory()
        let root = try makeSnapshot("hello")
        h.reset(initial: root)
        #expect(h.depth == 1)
        #expect(h.currentIndex == 0)
        #expect(h.currentSnapshot?.tree.treeID == root.tree.treeID)
        #expect(h.canUndo == false)
        #expect(h.canRedo == false)
    }

    @Test("recordTransaction appends one transaction")
    func recordTransaction() throws {
        let h = CSTUndoHistory()
        let before = try makeSnapshot("abc", cursor: 1)
        let after = try makeSnapshot("abXc", cursor: 3)
        h.reset(initial: before)

        let tx = h.recordTransaction(
            before: before,
            after: after,
            edits: [edit(start: 2, length: 0, replacement: "X")]
        )

        #expect(tx != nil)
        #expect(h.depth == 2)
        #expect(h.currentIndex == 1)
        #expect(h.canUndo == true)
        #expect(h.canRedo == false)
    }

    @Test("recordTransaction with no edits is dropped")
    func recordTransactionNoOp() throws {
        let h = CSTUndoHistory()
        let before = try makeSnapshot("abc")
        h.reset(initial: before)

        let tx = h.recordTransaction(
            before: before,
            after: try makeSnapshot("abc"),
            edits: []
        )

        #expect(tx == nil)
        #expect(h.depth == 1)
    }

    @Test("undo and redo expose surgical source edits")
    func undoRedoSourceEdits() throws {
        let h = CSTUndoHistory()
        let before = try makeSnapshot("abc", cursor: 1)
        let after = try makeSnapshot("abXc", cursor: 3)
        h.reset(initial: before)
        h.recordTransaction(
            before: before,
            after: after,
            edits: [edit(start: 2, length: 0, replacement: "X")]
        )

        let undo = try #require(h.undoStep())
        #expect(undo.direction == .undo)
        #expect(try apply(undo.sourceEdits, to: "abXc") == "abc")
        #expect(undo.target.cursor == 1)
        #expect(h.currentIndex == 0)
        #expect(h.canRedo == true)

        let redo = try #require(h.redoStep())
        #expect(redo.direction == .redo)
        #expect(try apply(redo.sourceEdits, to: "abc") == "abXc")
        #expect(redo.target.cursor == 3)
        #expect(h.currentIndex == 1)
    }

    @Test("recording after undo truncates forward history")
    func recordAfterUndoTruncatesForward() throws {
        let h = CSTUndoHistory()
        let root = try makeSnapshot("a")
        let ab = try makeSnapshot("ab")
        let abc = try makeSnapshot("abc")
        h.reset(initial: root)
        h.recordTransaction(
            before: root,
            after: ab,
            edits: [edit(start: 1, length: 0, replacement: "b")]
        )
        h.recordTransaction(
            before: ab,
            after: abc,
            edits: [edit(start: 2, length: 0, replacement: "c")]
        )

        _ = h.undoStep()
        _ = h.undoStep()
        #expect(h.canRedo == true)

        let ax = try makeSnapshot("aX")
        h.recordTransaction(
            before: root,
            after: ax,
            edits: [edit(start: 1, length: 0, replacement: "X")]
        )

        #expect(h.depth == 2)
        #expect(h.canRedo == false)
        #expect(h.currentSnapshot?.tree.sourceText() == "aX")
    }

    @Test("insert session accumulates edits into one transaction")
    func insertSessionEdits() throws {
        let h = CSTUndoHistory()
        let before = try makeSnapshot("a", cursor: 1)
        let after = try makeSnapshot("aXYZ", cursor: 4)
        h.reset(initial: before)
        h.beginInsertSession(at: before)
        h.appendInsertEdits([
            edit(start: 1, length: 0, replacement: "X"),
            edit(start: 2, length: 0, replacement: "Y"),
            edit(start: 3, length: 0, replacement: "Z")
        ])

        let tx = h.commitInsertSession(after: after)

        #expect(tx != nil)
        #expect(h.insertSessionActive == false)
        #expect(h.depth == 2)
        #expect(h.transactions[0].patches.count == 1)
        let undo = try #require(h.undoStep())
        #expect(try apply(undo.sourceEdits, to: "aXYZ") == "a")
    }

    @Test("commit without begin is ignored")
    func commitWithoutBegin() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        let tx = h.commitInsertSession(after: try makeSnapshot("axyz"))
        #expect(tx == nil)
        #expect(h.depth == 1)
    }

    @Test("installSnapshot restores the snapshot tree without reparsing")
    func installSnapshotRoundTrip() throws {
        let session = LiminalEditorSession(source: "abc")
        let parsed = try session.parse()
        let snapshotTree = parsed.tree

        _ = try session.applyTextEdits([
            edit(start: 3, length: 0, replacement: "def")
        ])
        #expect(session.source == "abcdef")
        #expect(session.currentTree?.treeID != snapshotTree.treeID)

        try session.applySourceEditsWithoutParsing([
            edit(start: 3, length: 3, replacement: "")
        ])
        session.installSnapshot(tree: snapshotTree)

        #expect(session.source == "abc")
        #expect(session.currentTree?.treeID == snapshotTree.treeID)
    }

    @Test("snapshots preserve cursor and marks across undo")
    func snapshotsCarryCursorAndMarks() throws {
        let h = CSTUndoHistory()
        var marks0 = MarkRegistry()
        let session = LiminalEditorSession(source: "abc")
        let parsed0 = try session.parse()
        let anchorA = try #require(
            CSTAnchor.atSourceOffset(TextSize(2), in: parsed0.rootSyntax)
        )
        marks0.set("a", anchor: anchorA)
        let before = CSTUndoSnapshot(
            tree: parsed0.tree,
            cursor: 1,
            marks: marks0
        )
        h.reset(initial: before)
        h.recordTransaction(
            before: before,
            after: try makeSnapshot("abcd", cursor: 3),
            edits: [edit(start: 3, length: 0, replacement: "d")]
        )

        let undone = try #require(h.undoStep())
        #expect(undone.target.cursor == 1)
        #expect(undone.target.marks.anchor(named: "a") != nil)
    }
}
