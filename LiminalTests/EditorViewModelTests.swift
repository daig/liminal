import AppKit
import CambiumCore
import CambiumIncremental
import Foundation
import Testing
@testable import Liminal

@Suite("EditorViewModel")
struct EditorViewModelTests {

    // MARK: - utf16RangeToByteRange

    @Test("utf16RangeToByteRange round-trips ASCII")
    func utf16ASCII() {
        let source = "Hello, World!"
        let range = NSRange(location: 7, length: 5)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 7..<12)
    }

    @Test("utf16RangeToByteRange handles accented characters")
    func utf16Accented() {
        // "héllo" — 'é' is U+00E9, 2 bytes in UTF-8, 1 unit in UTF-16.
        let source = "héllo"
        // UTF-16 range covering just 'é' (location 1, length 1).
        let range = NSRange(location: 1, length: 1)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        // 'h' is 1 byte; 'é' is 2 bytes.
        #expect(byteRange == 1..<3)
    }

    @Test("utf16RangeToByteRange handles emoji (surrogate pair)")
    func utf16Emoji() {
        // "a😀b" — emoji is U+1F600, 4 bytes UTF-8, 2 units UTF-16 (surrogate pair).
        let source = "a😀b"
        // UTF-16 range covering the entire emoji (location 1, length 2).
        let range = NSRange(location: 1, length: 2)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        // 'a' is 1 byte; '😀' is 4 bytes.
        #expect(byteRange == 1..<5)
    }

    @Test("utf16RangeToByteRange handles CJK characters")
    func utf16CJK() {
        // "你好" — each CJK char is U+4F60/U+597D, 3 bytes UTF-8, 1 unit UTF-16.
        let source = "你好world"
        let range = NSRange(location: 0, length: 2)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 0..<6)
    }

    @Test("utf16RangeToByteRange returns nil for ranges inside a surrogate pair")
    func utf16InsideSurrogate() {
        let source = "a😀b"
        // Range starting in the middle of the surrogate pair.
        let range = NSRange(location: 2, length: 1)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == nil)
    }

    @Test("utf16RangeToByteRange returns nil for out-of-bounds range")
    func utf16OutOfBounds() {
        let source = "abc"
        let range = NSRange(location: 5, length: 1)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == nil)
    }

    @Test("utf16RangeToByteRange empty range at end of string")
    func utf16EmptyAtEnd() {
        let source = "abc"
        let range = NSRange(location: 3, length: 0)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 3..<3)
    }

    // MARK: - LiminalSourceDocument round-trip

    @Test("LiminalSourceDocument round-trips UTF-8 data")
    @MainActor
    func sourceDocumentRoundTrip() throws {
        let source = "# Title\n\nBody\n"
        let data = Data(source.utf8)

        let document = LiminalSourceDocument()
        try document.read(from: data, ofType: "sub.dev.liminal.markup")

        #expect(document.editorSession.source == source)

        let written = try document.data(ofType: "sub.dev.liminal.markup")
        #expect(written == data)
    }

    @Test("LiminalSourceDocument rejects non-UTF-8 data")
    @MainActor
    func sourceDocumentRejectsInvalidUTF8() throws {
        let invalid = Data([0xFF, 0xFE, 0xFD])
        let document = LiminalSourceDocument()
        #expect(throws: CocoaError.self) {
            try document.read(from: invalid, ofType: "sub.dev.liminal.markup")
        }
    }

    // MARK: - LiminalEditorViewModel

    @Test("ViewModel reflects session state after applyTextEdits")
    @MainActor
    func viewModelReflectsStateAfterApply() throws {
        let session = LiminalEditorSession(source: "Hello\n")
        try session.parse()

        let viewModel = LiminalEditorViewModel(session: session)
        #expect(viewModel.diagnosticsCount == 0)

        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(0)), length: TextSize(UInt32(5))),
            replacement: "World"
        )
        viewModel.applyTextEdits([edit])

        #expect(session.source == "World\n")
        #expect(viewModel.diagnosticsCount == session.parseResult?.diagnostics.count ?? 0)
    }

    @Test("ViewModel syncs reuseSummary from session")
    @MainActor
    func viewModelSyncsReuseSummary() throws {
        let session = LiminalEditorSession(source: "A\n\nB\n\nC\n")
        try session.parse()

        let viewModel = LiminalEditorViewModel(session: session)

        // Edit just "B" in the middle paragraph; A and C should be reused.
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        viewModel.applyTextEdits([edit])

        #expect(viewModel.reuseSummary.acceptedReuses >= 2)
    }

    @Test("ViewModel replaceSource updates session and counters")
    @MainActor
    func viewModelReplaceSourceUpdates() {
        let session = LiminalEditorSession()
        let viewModel = LiminalEditorViewModel(session: session)

        viewModel.replaceSource("# Hello\n")
        #expect(session.source == "# Hello\n")
        #expect(viewModel.diagnosticsCount == 0)
    }
}
