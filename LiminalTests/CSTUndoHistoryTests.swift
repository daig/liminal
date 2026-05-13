import CambiumCore
import CambiumIncremental
import Foundation
import Testing
@testable import Liminal

@Suite("CSTUndoHistory")
@MainActor
struct CSTUndoHistoryTests {

    // MARK: - Snapshot fixtures

    private func makeSnapshot(
        _ source: String,
        cursor: Int = 0,
        marks: MarkRegistry = MarkRegistry()
    ) throws -> CSTUndoSnapshot {
        let session = LiminalEditorSession(source: source)
        let parsed = try session.parse()
        return CSTUndoSnapshot(
            tree: parsed.tree,
            source: source,
            cursor: cursor,
            marks: marks
        )
    }

    // MARK: - Empty / reset

    @Test("a fresh history is empty: depth 0, no undo or redo")
    func empty() {
        let h = CSTUndoHistory()
        #expect(h.depth == 0)
        #expect(h.canUndo == false)
        #expect(h.canRedo == false)
        #expect(h.insertSessionActive == false)
    }

    @Test("reset(initial:) installs one snapshot at index 0")
    func resetInitial() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("hello"))
        #expect(h.depth == 1)
        #expect(h.currentIndex == 0)
        #expect(h.canUndo == false)
        #expect(h.canRedo == false)
    }

    @Test("reset(initial:) mid-history clears prior snapshots")
    func resetClears() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        h.snapshot(try makeSnapshot("abc"))
        #expect(h.depth == 3)
        h.reset(initial: try makeSnapshot("fresh"))
        #expect(h.depth == 1)
        #expect(h.currentIndex == 0)
        #expect(h.snapshots[0].source == "fresh")
    }

    // MARK: - Snapshot append

    @Test("snapshot appends a new transaction; canUndo becomes true")
    func snapshotAppend() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        #expect(h.depth == 2)
        #expect(h.currentIndex == 1)
        #expect(h.canUndo == true)
        #expect(h.canRedo == false)
    }

    @Test("snapshot with same source as the current is a no-op (drop)")
    func snapshotNoOp() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("a"))   // identical source
        #expect(h.depth == 1, "redundant snapshot should not be appended")
    }

    @Test("snapshot after undo truncates forward history")
    func snapshotTruncatesForward() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        h.snapshot(try makeSnapshot("abc"))
        _ = h.undo()                // back to "ab"
        _ = h.undo()                // back to "a"
        #expect(h.canRedo == true)
        h.snapshot(try makeSnapshot("aZ"))   // new branch from "a"
        #expect(h.depth == 2, "forward history (ab, abc) should be discarded")
        #expect(h.canRedo == false)
        #expect(h.snapshots[1].source == "aZ")
    }

    // MARK: - Undo / redo

    @Test("undo from index 1 returns snapshot[0] and decrements")
    func undoOnce() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        let snap = h.undo()
        #expect(snap?.source == "a")
        #expect(h.currentIndex == 0)
        #expect(h.canUndo == false)
        #expect(h.canRedo == true)
    }

    @Test("undo at oldest returns nil and doesn't move")
    func undoAtOldest() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        let snap = h.undo()
        #expect(snap == nil)
        #expect(h.currentIndex == 0)
    }

    @Test("redo at newest returns nil and doesn't move")
    func redoAtNewest() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        let snap = h.redo()
        #expect(snap == nil)
        #expect(h.currentIndex == 1)
    }

    @Test("redo after undo returns the just-undone snapshot")
    func redoRoundTrip() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        _ = h.undo()
        let snap = h.redo()
        #expect(snap?.source == "ab")
        #expect(h.currentIndex == 1)
    }

    @Test("undo(count: N) walks back N steps and clamps at 0")
    func undoMultiStep() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        h.snapshot(try makeSnapshot("abc"))
        h.snapshot(try makeSnapshot("abcd"))
        let snap = h.undo(count: 10)
        #expect(snap?.source == "a")
        #expect(h.currentIndex == 0)
    }

    @Test("redo(count: N) walks forward N steps and clamps at tip")
    func redoMultiStep() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.snapshot(try makeSnapshot("ab"))
        h.snapshot(try makeSnapshot("abc"))
        _ = h.undo(count: 2)        // back to "a"
        let snap = h.redo(count: 10)
        #expect(snap?.source == "abc")
        #expect(h.currentIndex == 2)
    }

    // MARK: - Insert sessions

    @Test("an insert session that adds text appends one snapshot")
    func insertSessionEdits() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.beginInsertSession(at: try makeSnapshot("a"))
        #expect(h.insertSessionActive == true)
        h.commitInsertSession(commit: try makeSnapshot("aXYZ"))
        #expect(h.insertSessionActive == false)
        #expect(h.depth == 2)
        #expect(h.snapshots[1].source == "aXYZ")
    }

    @Test("an insert session with no edits is dropped (no snapshot appended)")
    func insertSessionNoOp() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.beginInsertSession(at: try makeSnapshot("a"))
        h.commitInsertSession(commit: try makeSnapshot("a")) // no typing
        #expect(h.depth == 1, "empty insert session should not snapshot")
        #expect(h.insertSessionActive == false)
    }

    @Test("commit without begin is a silent no-op (no snapshot)")
    func commitWithoutBegin() throws {
        let h = CSTUndoHistory()
        h.reset(initial: try makeSnapshot("a"))
        h.commitInsertSession(commit: try makeSnapshot("axyz"))
        #expect(h.depth == 1, "commit without begin is ignored")
    }

    // MARK: - Cursor + marks roundtrip

    // MARK: - Session install round-trip (anchor identity)

    @Test("installSnapshot restores the snapshot tree without reparsing")
    func installSnapshotRoundTrip() throws {
        // Parse "abc" → snapshot the tree.
        let session = LiminalEditorSession(source: "abc")
        let parsed = try session.parse()
        let snapshotTree = parsed.tree

        // Apply a text edit so currentTree advances to a new tree.
        let edit = TextEdit(
            range: TextRange(start: TextSize(3), length: TextSize(0)),
            replacement: "def"
        )
        _ = try session.applyTextEdits([edit])
        #expect(session.source == "abcdef")
        // Sanity: the tree changed.
        let advancedTreeID = session.currentTree?.treeID
        #expect(advancedTreeID != snapshotTree.treeID)

        // Install the snapshot — currentTree should now be pointer-equal
        // (treeID-equal) to the snapshot.
        session.installSnapshot(tree: snapshotTree, source: "abc")
        #expect(session.source == "abc")
        #expect(session.currentTree?.treeID == snapshotTree.treeID,
                "installed tree must preserve treeID — that's the point")
    }

    @Test("snapshots preserve cursor and marks across undo/redo")
    func snapshotsCarryCursorAndMarks() throws {
        let h = CSTUndoHistory()
        var marks0 = MarkRegistry()
        let session = LiminalEditorSession(source: "abc")
        let parsed0 = try session.parse()
        let anchorA = try #require(
            CSTAnchor.atSourceOffset(TextSize(2), in: parsed0.rootSyntax)
        )
        marks0.set("a", anchor: anchorA)
        h.reset(initial: CSTUndoSnapshot(
            tree: parsed0.tree, source: "abc",
            cursor: 1, marks: marks0
        ))
        h.snapshot(try makeSnapshot("abcd", cursor: 3))
        let undone = h.undo()
        #expect(undone?.source == "abc")
        #expect(undone?.cursor == 1)
        #expect(undone?.marks.anchor(named: "a") != nil,
                "mark restored across undo")
    }
}
