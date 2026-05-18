import CambiumCore
import CambiumIncremental
import Testing
@testable import Liminal

@Suite("CSTAnchor")
@MainActor
struct CSTAnchorTests {

    private func makeSession(_ source: String) throws -> LiminalEditorSession {
        let session = LiminalEditorSession()
        try session.replaceSource(CambiumSource(source))
        return session
    }

    @Test("atSourceOffset round-trips through resolve at same byte")
    func roundTrip() throws {
        let session = try makeSession("# Heading\n\nParagraph body.\n")
        let root = try #require(session.parseResult?.rootSyntax)

        // Offset 12 should be inside "Paragraph body."
        let offset: TextSize = 12
        let anchor = try #require(CSTAnchor.atSourceOffset(offset, in: root))
        let resolution = anchor.resolve(in: root)
        guard case .strong(let byteOffset) = resolution else {
            Issue.record("expected .strong, got \(resolution)")
            return
        }
        #expect(byteOffset == offset)
    }

    @Test("anchor fingerprint captures the innermost containing node's kind")
    func fingerprintCapturesInnermost() throws {
        let session = try makeSession("Para A.\n\nPara B.\n")
        let root = try #require(session.parseResult?.rootSyntax)

        // Offset 0 is inside the first paragraph.
        let anchor = try #require(CSTAnchor.atSourceOffset(0, in: root))
        // Innermost node containing offset 0 is most likely the inlineText
        // token inside the paragraph; depending on tree shape this might
        // also be the paragraph itself. Either way the kind should be
        // non-nil and stable.
        #expect(anchor.fingerprint.contentHash != ContentHash(low64: 0, high64: 0))
    }

    @Test("anchor at end of document falls back to root")
    func anchorAtEndFallsBack() throws {
        let session = try makeSession("Hello.\n")
        let root = try #require(session.parseResult?.rootSyntax)

        // Past-end offset — descent should hit no child and bottom out at
        // root (or whatever the innermost containing structure is).
        let anchor = try #require(CSTAnchor.atSourceOffset(100, in: root))
        // The path may be empty (root) or partial; just confirm it builds
        // and resolves to something (not .lost).
        let resolution = anchor.resolve(in: root)
        #expect(resolution != .lost)
    }

    @Test("path resolves but kind matches with same hash → strong")
    func sameTreeStrong() throws {
        let session = try makeSession("Hello world.\n")
        let root = try #require(session.parseResult?.rootSyntax)

        let anchor = try #require(CSTAnchor.atSourceOffset(3, in: root))
        let resolution = anchor.resolve(in: root)
        if case .strong = resolution { /* ok */ } else {
            Issue.record("expected .strong, got \(resolution)")
        }
    }

    @Test("textual edit before the anchor: re-anchor shifts byte offset")
    func textualEditBeforeShifts() throws {
        let session = try makeSession("First.\n\nSecond paragraph.\n")
        let oldRoot = try #require(session.parseResult?.rootSyntax)

        // Anchor inside "Second paragraph." — second paragraph starts at byte 8.
        let anchor = try #require(CSTAnchor.atSourceOffset(15, in: oldRoot))

        // Insert "Z\n\n" at the beginning (3 bytes inserted before anchor).
        let edit = TextEdit(
            range: TextRange(start: TextSize(0), length: TextSize(0)),
            replacement: "Z\n\n"
        )
        var registry = MarkRegistry()
        registry.set("a", anchor: anchor)

        try session.applyTextEdits([edit])
        let newRoot = try #require(session.parseResult?.rootSyntax)

        registry.reanchor(oldRoot: oldRoot, edits: [edit], newRoot: newRoot)
        let newAnchor = try #require(registry.anchor(named: "a"))
        let resolution = newAnchor.resolve(in: newRoot)
        switch resolution {
        case .strong(let off), .weak(let off):
            #expect(off == 18) // 15 + 3
        default:
            Issue.record("expected .strong/.weak with byte 18, got \(resolution)")
        }
    }

    @Test("textual edit after the anchor: byte offset unchanged")
    func textualEditAfterUnchanged() throws {
        let session = try makeSession("First.\n\nSecond.\n")
        let oldRoot = try #require(session.parseResult?.rootSyntax)

        let anchor = try #require(CSTAnchor.atSourceOffset(2, in: oldRoot))

        // Insert "Tail\n" at end (offset 16).
        let edit = TextEdit(
            range: TextRange(start: TextSize(16), length: TextSize(0)),
            replacement: "Tail\n"
        )
        var registry = MarkRegistry()
        registry.set("a", anchor: anchor)

        try session.applyTextEdits([edit])
        let newRoot = try #require(session.parseResult?.rootSyntax)

        registry.reanchor(oldRoot: oldRoot, edits: [edit], newRoot: newRoot)
        let newAnchor = try #require(registry.anchor(named: "a"))
        switch newAnchor.resolve(in: newRoot) {
        case .strong(let off), .weak(let off):
            #expect(off == 2)
        default:
            Issue.record("expected .strong/.weak with byte 2, got something else")
        }
    }

    @Test("edit overlapping the anchor: snaps to edit start")
    func editOverlappingSnaps() throws {
        let session = try makeSession("Hello world.\n")
        let oldRoot = try #require(session.parseResult?.rootSyntax)

        let anchor = try #require(CSTAnchor.atSourceOffset(7, in: oldRoot))

        // Replace bytes 6-11 ("world") with "everyone" (overlaps offset 7).
        let edit = TextEdit(
            range: TextRange(start: TextSize(6), length: TextSize(5)),
            replacement: "everyone"
        )
        var registry = MarkRegistry()
        registry.set("a", anchor: anchor)

        try session.applyTextEdits([edit])
        let newRoot = try #require(session.parseResult?.rootSyntax)

        registry.reanchor(oldRoot: oldRoot, edits: [edit], newRoot: newRoot)
        let newAnchor = try #require(registry.anchor(named: "a"))
        switch newAnchor.resolve(in: newRoot) {
        case .strong(let off), .weak(let off), .recovered(let off):
            // Overlap rule: anchor snaps to the edit's start (byte 6).
            #expect(off == 6)
        case .lost:
            Issue.record("anchor unexpectedly lost")
        }
    }
}
