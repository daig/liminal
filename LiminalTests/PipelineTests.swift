import Testing
@testable import Liminal

@Suite("Pipeline")
struct PipelineTests {
    @Test("parse, lower, and print preserves source through the Cambium tree")
    func parseLowerPrintPreservesSourceThroughCambiumTree() throws {
        let source = "# Typed documents\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let printed = LiminalPrinter().print(document)

        #expect(printed == source)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("editor session owns the parse session boundary")
    func editorSessionOwnsParseSessionBoundary() throws {
        let session = LiminalEditorSession(source: "hello")
        let parsed = try session.parse()
        let document = try session.lowerCurrentDocument()

        #expect(parsed.sourceText == "hello")
        #expect(document.sourceText == "hello")
    }

    @Test("render document reads semantic document state without owning source")
    func renderDocumentUsesSemanticDocumentWithoutOwningSource() throws {
        let parsed = try LiminalParser().parse("preview")
        let document = LiminalLowerer().lower(parsed)
        let renderDocument = RenderDocument(document: document)

        #expect(renderDocument.sourceText == "preview")
        #expect(renderDocument.blocks.isEmpty)
    }
}
