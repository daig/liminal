import CambiumCore
import Testing
@testable import Liminal

@Suite("CSTInspector")
@MainActor
struct CSTInspectorTests {

    private func makeRoot(_ source: String) throws -> RootSyntax {
        let session = LiminalEditorSession()
        try session.replaceSource(CambiumSource(source))
        return try #require(session.parseResult?.rootSyntax)
    }

    @Test("cursor 1:1 at byte 0")
    func cursorLineColumnInitial() throws {
        let source = "Hello\nworld\n"
        let root = try makeRoot(source)
        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(0),
            root: root,
            source: CambiumSource(source)
        )
        #expect(snapshot.cursor.line == 1)
        #expect(snapshot.cursor.column == 1)
    }

    @Test("cursor on line 2 after a newline")
    func cursorOnSecondLine() throws {
        let source = "ab\ncde\n"
        let root = try makeRoot(source)
        // Byte 4: 'c' on line 2 column 2 (after the "\n" at index 2)
        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(4),
            root: root,
            source: CambiumSource(source)
        )
        #expect(snapshot.cursor.line == 2)
        #expect(snapshot.cursor.column == 2)
    }
}
