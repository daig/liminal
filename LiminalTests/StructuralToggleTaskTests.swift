import CambiumCore
import Testing
@testable import Liminal

/// Exercises `LiminalSourceDocument.structuralToggleTask` — the Phase 7
/// slice 3 semantic-action prototype that toggles a task checkbox by
/// rebuilding the enclosing list item via `GreenTreeBuilder` and
/// committing through the structural-replace primitive. No reparse, no
/// textual round-trip.
@Suite("StructuralToggleTask")
@MainActor
struct StructuralToggleTaskTests {

    @Test("unchecked task toggles to checked; source flips exactly the marker bytes")
    func toggleUnchecked() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [ ] task body\n")

        let parsed = try #require(document.session.parseResult)
        let location = try #require(
            StructureCursor.taskListItem(at: 6, in: parsed.rootSyntax)
        )
        #expect(location.state == .unchecked)

        #expect(document.structuralToggleTask(listItemHandle: location.listItemHandle))

        #expect(document.session.source == "- [x] task body\n")
    }

    @Test("checked task toggles to unchecked")
    func toggleChecked() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [x] done\n")

        let parsed = try #require(document.session.parseResult)
        let location = try #require(
            StructureCursor.taskListItem(at: 6, in: parsed.rootSyntax)
        )
        #expect(location.state == .checked)

        #expect(document.structuralToggleTask(listItemHandle: location.listItemHandle))

        #expect(document.session.source == "- [ ] done\n")
    }

    @Test("toggling twice round-trips back to original source")
    func toggleRoundTrip() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [ ] body\n")

        let original = document.session.source

        let parsed1 = try #require(document.session.parseResult)
        let location1 = try #require(
            StructureCursor.taskListItem(at: 6, in: parsed1.rootSyntax)
        )
        #expect(document.structuralToggleTask(listItemHandle: location1.listItemHandle))
        #expect(document.session.source != original)

        // Second toggle: re-find via the (now-stale-parseResult-but-valid-
        // currentTree) accessor. parseResult is nil after structural edit.
        let root2 = try #require(document.currentRootSyntax)
        let location2 = try #require(
            StructureCursor.taskListItem(at: 6, in: root2)
        )
        #expect(document.structuralToggleTask(listItemHandle: location2.listItemHandle))
        #expect(document.session.source == original)
    }

    @Test("inline content with emphasis/strong is preserved")
    func preservesInlineContent() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [ ] *italic* and **bold**\n")

        let parsed = try #require(document.session.parseResult)
        let location = try #require(
            StructureCursor.taskListItem(at: 10, in: parsed.rootSyntax)
        )

        #expect(document.structuralToggleTask(listItemHandle: location.listItemHandle))
        #expect(document.session.source == "- [x] *italic* and **bold**\n")
    }

    @Test("currentRootSyntax falls back to currentTree after structural edit")
    func currentRootSyntaxBridgesStructuralEdit() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [ ] body\n")

        let parsed = try #require(document.session.parseResult)
        let location = try #require(
            StructureCursor.taskListItem(at: 6, in: parsed.rootSyntax)
        )
        #expect(document.structuralToggleTask(listItemHandle: location.listItemHandle))

        // parseResult is nil after a structural edit — but currentRootSyntax
        // bridges to currentTree so consumers always have access.
        #expect(document.session.parseResult == nil)
        let root = try #require(document.currentRootSyntax)
        // Round-trip through the root's syntax: the tree's source should
        // match session.source (no source-tree divergence).
        let rootSource = root.syntax.withCursor { $0.makeString() }
        #expect(rootSource == document.session.source)
    }

    @Test("toggle preserves overall tree structure (still a list with one item)")
    func preservesTreeStructure() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource("- [ ] only\n")

        let parsed = try #require(document.session.parseResult)
        let location = try #require(
            StructureCursor.taskListItem(at: 6, in: parsed.rootSyntax)
        )
        #expect(document.structuralToggleTask(listItemHandle: location.listItemHandle))

        // Walk the new root and verify the document still has exactly one
        // document item — a list containing one task list item with
        // taskState == .checked.
        let root = try #require(document.currentRootSyntax)
        let items = root.documentItems
        #expect(items.count == 1)
        guard case .list(let list) = items.first else {
            Issue.record("expected first item to be a list")
            return
        }
        #expect(list.items.count == 1)
        let item = list.items[0]
        #expect(item.taskState == .checked)
    }
}
