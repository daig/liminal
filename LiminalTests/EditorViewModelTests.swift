import AppKit
import CambiumCore
import CambiumIncremental
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Liminal

@Suite("EditorDocument")
struct EditorDocumentTests {

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
        let source = "héllo"
        let range = NSRange(location: 1, length: 1)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 1..<3)
    }

    @Test("utf16RangeToByteRange handles emoji (surrogate pair)")
    func utf16Emoji() {
        let source = "a😀b"
        let range = NSRange(location: 1, length: 2)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 1..<5)
    }

    @Test("utf16RangeToByteRange handles CJK characters")
    func utf16CJK() {
        let source = "你好world"
        let range = NSRange(location: 0, length: 2)
        let byteRange = LiminalTextView.utf16RangeToByteRange(range, in: source)
        #expect(byteRange == 0..<6)
    }

    @Test("utf16RangeToByteRange returns nil for ranges inside a surrogate pair")
    func utf16InsideSurrogate() {
        let source = "a😀b"
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

    // MARK: - LiminalSourceDocument

    @Test("new document starts empty")
    @MainActor
    func newDocumentIsEmpty() {
        let document = LiminalSourceDocument()
        #expect(document.session.source == CambiumSource(""))
        #expect(document.diagnosticsCount == 0)
    }

    @Test("snapshot returns the current source")
    @MainActor
    func snapshotReturnsSource() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource(CambiumSource("# Hello\n"))
        let snapshot = try document.snapshot(contentType: .liminalMarkup)
        #expect(snapshot == "# Hello\n")
    }

    @Test("applyTextEdits updates session and published counters")
    @MainActor
    func applyTextEditsUpdatesDocument() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource(CambiumSource("Hello\n"))
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(0)), length: TextSize(UInt32(5))),
            replacement: "World"
        )
        document.applyTextEdits([edit])

        #expect(document.session.source == CambiumSource("World\n"))
        #expect(document.diagnosticsCount == document.session.parseResult?.diagnostics.count ?? -1)
    }

    @Test("document re-publishes reuseSummary after edits")
    @MainActor
    func documentSyncsReuseSummary() throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource(CambiumSource("A\n\nB\n\nC\n"))
        let edit = TextEdit(
            range: TextRange(start: TextSize(UInt32(3)), length: TextSize(UInt32(1))),
            replacement: "B2"
        )
        document.applyTextEdits([edit])

        #expect(document.reuseSummary.acceptedReuses >= 2)
    }
}
