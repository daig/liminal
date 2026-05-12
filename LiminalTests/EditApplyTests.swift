import CambiumBuilder
import CambiumCore
import CambiumIncremental
import Testing
@testable import Liminal

@Suite("EditApply")
struct EditApplyTests {

    // MARK: - applyTextEdits

    @Test("applyTextEdits with empty edits returns source unchanged")
    func emptyEditsIsNoOp() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        let result = try session.applyTextEdits([])
        #expect(session.source == "Hello\n")
        #expect(result.sourceText == "Hello\n")
    }

    @Test("applyTextEdits replaces bytes at given range")
    func singleEditReplacesRange() throws {
        let session = LiminalEditorSession(source: "Hello World\n")
        let edit = TextEdit(
            range: makeByteRange(start: 0, length: 5),
            replacement: "Greetings"
        )
        let result = try session.applyTextEdits([edit])
        #expect(session.source == "Greetings World\n")
        #expect(result.sourceText == "Greetings World\n")
    }

    @Test("applyTextEdits applies non-overlapping edits regardless of input order")
    func multiEditOrdering() throws {
        let session = LiminalEditorSession(source: "abcdefg\n")
        let edit1 = TextEdit(
            range: makeByteRange(start: 0, length: 1),
            replacement: "X"
        )
        let edit2 = TextEdit(
            range: makeByteRange(start: 4, length: 1),
            replacement: "Y"
        )
        let result = try session.applyTextEdits([edit1, edit2])
        #expect(session.source == "XbcdYfg\n")
        #expect(result.sourceText == "XbcdYfg\n")
    }

    @Test("applyTextEdits applies edits supplied in descending order too")
    func multiEditDescendingInputOrder() throws {
        let session = LiminalEditorSession(source: "abcdefg\n")
        let edit1 = TextEdit(
            range: makeByteRange(start: 4, length: 1),
            replacement: "Y"
        )
        let edit2 = TextEdit(
            range: makeByteRange(start: 0, length: 1),
            replacement: "X"
        )
        let result = try session.applyTextEdits([edit1, edit2])
        #expect(result.sourceText == "XbcdYfg\n")
    }

    @Test("applyTextEdits preserves UTF-8 around multibyte characters")
    func utf8Safety() throws {
        let session = LiminalEditorSession(source: "héllo\n")
        let edit = TextEdit(
            range: makeByteRange(start: 0, length: 1),
            replacement: "H"
        )
        let result = try session.applyTextEdits([edit])
        #expect(session.source == "Héllo\n")
        #expect(result.sourceText == "Héllo\n")
    }

    @Test("applyTextEdits replaces a multibyte character cleanly")
    func utf8ReplacesMultibyte() throws {
        let session = LiminalEditorSession(source: "héllo\n")
        let edit = TextEdit(
            range: makeByteRange(start: 1, length: 2),
            replacement: "e"
        )
        let result = try session.applyTextEdits([edit])
        #expect(session.source == "hello\n")
        #expect(result.sourceText == "hello\n")
    }

    @Test("applyTextEdits rejects overlapping edits")
    func rejectsOverlapping() throws {
        let session = LiminalEditorSession(source: "abcdef\n")
        let edit1 = TextEdit(
            range: makeByteRange(start: 0, length: 3),
            replacement: "X"
        )
        let edit2 = TextEdit(
            range: makeByteRange(start: 2, length: 2),
            replacement: "Y"
        )
        #expect(throws: LiminalEditError.overlappingEdits) {
            try session.applyTextEdits([edit1, edit2])
        }
    }

    @Test("applyTextEdits rejects edits whose range exceeds source bytes")
    func rejectsOutOfRange() throws {
        let session = LiminalEditorSession(source: "ab\n")
        let edit = TextEdit(
            range: makeByteRange(start: 5, length: 1),
            replacement: "X"
        )
        #expect(throws: (any Error).self) {
            try session.applyTextEdits([edit])
        }
    }

    // MARK: - replaceSubtree

    @Test("replaceSubtree swaps a paragraph and updates source")
    func replaceSubtreeHappyPath() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        let parsed = try session.parse()
        guard case .paragraph(let paragraph) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let replacement = try makeParagraphSnapshot(text: "World", newline: "\n")
        let result = try session.replaceSubtree(paragraph.syntax, with: replacement)

        #expect(result.sourceText == "World\n")
        #expect(session.source == "World\n")
    }

    @Test("replaceSubtree returns a witness whose old/new subtrees differ")
    func replaceSubtreeWitnessDifferent() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        let parsed = try session.parse()
        guard case .paragraph(let paragraph) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let replacement = try makeParagraphSnapshot(text: "Bye", newline: "\n")
        let result = try session.replaceSubtree(paragraph.syntax, with: replacement)

        #expect(result.witness.oldSubtree.identity != result.witness.newSubtree.identity)
    }

    @Test("replaceSubtree clears parseResult since diagnostics are stale")
    func replaceSubtreeClearsParseResult() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        try session.parse()
        #expect(session.parseResult != nil)

        let parsed = try #require(session.parseResult)
        guard case .paragraph(let paragraph) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let replacement = try makeParagraphSnapshot(text: "Bye", newline: "\n")
        _ = try session.replaceSubtree(paragraph.syntax, with: replacement)

        #expect(session.parseResult == nil)
    }

    @Test("replaceSubtree before parse throws noParsedTree")
    func replaceSubtreeRequiresPriorParse() throws {
        let donor = try LiminalParser().parse("Hello\n")
        guard case .paragraph(let para) = donor.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }

        let session = LiminalEditorSession(source: "")
        let replacement = try makeParagraphSnapshot(text: "World", newline: "\n")
        #expect(throws: LiminalEditError.noParsedTree) {
            try session.replaceSubtree(para.syntax, with: replacement)
        }
    }

    // MARK: - Composition

    @Test("textual edit, structural edit, textual edit compose on one session")
    func mixedCompose() throws {
        let session = LiminalEditorSession(source: "Hello World\n")

        let edit1 = TextEdit(
            range: makeByteRange(start: 0, length: 5),
            replacement: "Greetings"
        )
        _ = try session.applyTextEdits([edit1])
        #expect(session.source == "Greetings World\n")

        let parsed = try session.parse()
        guard case .paragraph(let para) = parsed.rootSyntax.documentItems.first else {
            Issue.record("expected paragraph after textual edit")
            return
        }
        let replacement = try makeParagraphSnapshot(text: "Hi", newline: "\n")
        _ = try session.replaceSubtree(para.syntax, with: replacement)
        #expect(session.source == "Hi\n")

        let edit2 = TextEdit(
            range: makeByteRange(start: 0, length: 2),
            replacement: "Bye"
        )
        _ = try session.applyTextEdits([edit2])
        #expect(session.source == "Bye\n")
    }
}

// MARK: - Test helpers

private func makeByteRange(start: UInt32, length: UInt32) -> TextRange {
    TextRange(
        start: TextSize(start),
        length: TextSize(length)
    )
}

private func makeParagraphSnapshot(
    text: String,
    newline: String
) throws -> GreenTreeSnapshot<LiminalLanguage> {
    var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
    builder.startNode(.paragraph)
    builder.startNode(.inlineContent)
    try builder.token(.inlineText, text: text)
    try builder.finishNode()
    try builder.token(.newline, text: newline)
    try builder.finishNode()
    let build = try builder.finish()
    return build.snapshot
}

