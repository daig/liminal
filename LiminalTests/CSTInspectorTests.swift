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

    @Test("snapshot at byte 0 of a paragraph starts the breadcrumb at root")
    func breadcrumbStartsAtRoot() throws {
        let source = "Hello.\n"
        let root = try makeRoot(source)

        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(0),
            root: root,
            source: source
        )
        let firstKind = try #require(snapshot.breadcrumb.first?.kind)
        #expect(firstKind == .root)
    }

    @Test("snapshot inside a paragraph walks through the paragraph kind")
    func breadcrumbContainsParagraph() throws {
        let source = "Hello world.\n"
        let root = try makeRoot(source)

        // Offset 3 is inside "Hello".
        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(3),
            root: root,
            source: source
        )
        let kinds = snapshot.breadcrumb.map(\.kind)
        #expect(kinds.contains(.paragraph))
    }

    @Test("cursor 1:1 at byte 0")
    func cursorLineColumnInitial() throws {
        let source = "Hello\nworld\n"
        let root = try makeRoot(source)
        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(0),
            root: root,
            source: source
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
            source: source
        )
        #expect(snapshot.cursor.line == 2)
        #expect(snapshot.cursor.column == 2)
    }

    @Test("inspector exposes node details with non-empty path past root")
    func nodeDetailsPathNonEmpty() throws {
        let source = "## A heading line\n"
        let root = try makeRoot(source)
        // Offset 3 lands inside the heading.
        let snapshot = CSTInspector.makeSnapshot(
            byteOffset: TextSize(3),
            root: root,
            source: source
        )
        let node = try #require(snapshot.node)
        // Some non-root descendant should be the innermost.
        #expect(!node.path.isEmpty || node.kind != .root)
    }

    @Test("preview compresses whitespace and truncates long text")
    func previewFormatting() throws {
        let long = String(repeating: "x", count: 100)
        let preview = CSTPreview.format("  hello\n\nworld   \(long)")
        #expect(preview.hasPrefix("hello world"))
        #expect(preview.last == "…")
    }

    @Test("preview leaves short whitespace-free text alone")
    func previewShortText() throws {
        let preview = CSTPreview.format("hello world")
        #expect(preview == "hello world")
    }

    @Test("LiminalKind.displayName title-cases and splits camelCase")
    func displayNameTransform() {
        #expect(LiminalKind.paragraph.displayName == "Paragraph")
        #expect(LiminalKind.listItem.displayName == "List Item")
        #expect(LiminalKind.atxHeading.displayName == "Atx Heading")
        #expect(LiminalKind.thematicBreak.displayName == "Thematic Break")
    }

    @Test("refresh clears snapshot when root is nil")
    func refreshClearsOnNilRoot() {
        let inspector = CSTInspector()
        inspector.refresh(
            cursorByteOffset: nil,
            root: nil,
            source: ""
        )
        #expect(inspector.snapshot == nil)
    }
}
