import CambiumCore
import Testing
@testable import Liminal

@Suite("StructureCursor")
struct StructureCursorTests {

    // MARK: - Sibling motion

    @Test("nextSibling moves from start of first paragraph to start of second")
    func nextSiblingForward() throws {
        let source = "First\n\nSecond\n\nThird\n"
        let parsed = try LiminalParser().parse(source)
        // Cursor at byte 0 (start of "First")
        let next = StructureCursor.nextSibling(of: 0, in: parsed.rootSyntax)
        #expect(next != nil)
        if let next {
            // Should be the start of "Second" — past "First\n" + blank line
            #expect(next > 0)
            let prefix = source.prefix(next)
            #expect(prefix.contains("First"))
            #expect(!prefix.contains("Second"))
        }
    }

    @Test("previousSibling moves from third paragraph to second")
    func previousSiblingBackward() throws {
        let source = "First\n\nSecond\n\nThird\n"
        let parsed = try LiminalParser().parse(source)
        // Cursor inside "Third" — find its byte offset
        let thirdOffset = source.utf8.distance(
            from: source.utf8.startIndex,
            to: source.range(of: "Third")!.lowerBound.samePosition(in: source.utf8)!
        )
        let prev = StructureCursor.previousSibling(of: thirdOffset, in: parsed.rootSyntax)
        #expect(prev != nil)
        if let prev {
            #expect(prev < thirdOffset)
        }
    }

    @Test("nextSibling returns nil at the last sibling")
    func nextSiblingAtEnd() throws {
        let source = "Only\n"
        let parsed = try LiminalParser().parse(source)
        let next = StructureCursor.nextSibling(of: 0, in: parsed.rootSyntax)
        // Single paragraph, no next sibling.
        #expect(next == nil)
    }

    @Test("siblings skip blank lines")
    func siblingsSkipBlankLines() throws {
        let source = "A\n\n\n\nB\n"
        let parsed = try LiminalParser().parse(source)
        let next = StructureCursor.nextSibling(of: 0, in: parsed.rootSyntax)
        // Should land at "B" — blank lines aren't counted as siblings.
        #expect(next != nil)
        if let next {
            let bIndex = source.utf8.distance(
                from: source.utf8.startIndex,
                to: source.range(of: "B")!.lowerBound.samePosition(in: source.utf8)!
            )
            #expect(next == bIndex)
        }
    }

    // MARK: - Task list item detection

    @Test("taskListItem finds unchecked task")
    func taskUnchecked() throws {
        let source = "- [ ] do something\n"
        let parsed = try LiminalParser().parse(source)
        let cursorOffset = source.utf8.distance(
            from: source.utf8.startIndex,
            to: source.range(of: "do")!.lowerBound.samePosition(in: source.utf8)!
        )
        let location = StructureCursor.taskListItem(at: cursorOffset, in: parsed.rootSyntax)
        #expect(location != nil)
        #expect(location?.state == .unchecked)
    }

    @Test("taskListItem finds checked task")
    func taskChecked() throws {
        let source = "- [x] done\n"
        let parsed = try LiminalParser().parse(source)
        let cursorOffset = source.utf8.distance(
            from: source.utf8.startIndex,
            to: source.range(of: "done")!.lowerBound.samePosition(in: source.utf8)!
        )
        let location = StructureCursor.taskListItem(at: cursorOffset, in: parsed.rootSyntax)
        #expect(location != nil)
        #expect(location?.state == .checked)
    }

    @Test("taskListItem returns nil for a plain list item without a task marker")
    func nonTaskListItem() throws {
        let source = "- just a bullet\n"
        let parsed = try LiminalParser().parse(source)
        let cursorOffset = source.utf8.distance(
            from: source.utf8.startIndex,
            to: source.range(of: "just")!.lowerBound.samePosition(in: source.utf8)!
        )
        let location = StructureCursor.taskListItem(at: cursorOffset, in: parsed.rootSyntax)
        #expect(location == nil)
    }

    @Test("taskListItem returns nil outside any list")
    func notInList() throws {
        let source = "Plain paragraph.\n"
        let parsed = try LiminalParser().parse(source)
        let location = StructureCursor.taskListItem(at: 0, in: parsed.rootSyntax)
        #expect(location == nil)
    }
}
