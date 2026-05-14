import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("CmdClickHandler")
@MainActor
struct CmdClickActivationTests {
    @Test("returns nil when no reference contains the click point")
    func noReferenceUnderClick() {
        let docURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let docIndex = DocumentIndex()
        let vault = VaultLinkIndex.empty
        #expect(CmdClickHandler.decision(
            atByteOffset: 5,
            documentURL: docURL,
            documentIndex: docIndex,
            vaultLinkIndex: vault
        ) == nil)
    }

    @Test("external URI flows through .openExternal regardless of vault")
    func externalURI() {
        let docURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let externalRef = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("https://example.com"),
            sourceRange: LiminalSourceRange(start: 0, length: 19)
        )
        let docIndex = DocumentIndex(references: [externalRef])
        let result = CmdClickHandler.decision(
            atByteOffset: 5,
            documentURL: docURL,
            documentIndex: docIndex,
            vaultLinkIndex: .empty
        )
        #expect(result?.decision == .openExternal(URL(string: "https://example.com")!))
    }

    @Test("within-doc heading anchor resolves to .open(self, .heading)")
    func withinDocHeading() {
        let docURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("#Goals"),
            sourceRange: LiminalSourceRange(start: 0, length: 9)
        )
        let docIndex = DocumentIndex(
            headings: [HeadingAnchor(title: "Goals", sourceOffset: 100)],
            references: [ref]
        )
        let note = LiminalNoteMetadata(
            url: docURL,
            relativePath: "Source.lim"
        )
        let vault = VaultLinkIndex.build(
            notes: [note],
            documentIndexes: [docURL: docIndex]
        )
        let result = CmdClickHandler.decision(
            atByteOffset: 4,
            documentURL: docURL,
            documentIndex: docIndex,
            vaultLinkIndex: vault
        )
        #expect(result?.decision == .open(noteID: docURL, anchor: .heading("Goals")))
    }

    @Test("within-doc block anchor resolves to .open(self, .block)")
    func withinDocBlock() {
        let docURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("#^para-1"),
            sourceRange: LiminalSourceRange(start: 0, length: 11)
        )
        let docIndex = DocumentIndex(
            blocks: [BlockAnchor(blockID: "para-1", sourceOffset: 50)],
            references: [ref]
        )
        let note = LiminalNoteMetadata(
            url: docURL,
            relativePath: "Source.lim"
        )
        let vault = VaultLinkIndex.build(
            notes: [note],
            documentIndexes: [docURL: docIndex]
        )
        let result = CmdClickHandler.decision(
            atByteOffset: 5,
            documentURL: docURL,
            documentIndex: docIndex,
            vaultLinkIndex: vault
        )
        #expect(result?.decision == .open(noteID: docURL, anchor: .block("para-1")))
    }

    @Test("cross-doc resolved wikilink → .open(other-doc, anchor)")
    func crossDocResolved() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let targetURL = URL(fileURLWithPath: "/tmp/v/Target.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Target"),
            sourceRange: LiminalSourceRange(start: 0, length: 10)
        )
        let sourceIndex = DocumentIndex(references: [ref])
        let sourceNote = LiminalNoteMetadata(url: sourceURL, relativePath: "Source.lim")
        let targetNote = LiminalNoteMetadata(url: targetURL, relativePath: "Target.lim")
        let vault = VaultLinkIndex.build(
            notes: [sourceNote, targetNote],
            documentIndexes: [sourceURL: sourceIndex, targetURL: .empty]
        )
        let result = CmdClickHandler.decision(
            atByteOffset: 5,
            documentURL: sourceURL,
            documentIndex: sourceIndex,
            vaultLinkIndex: vault
        )
        #expect(result?.decision == .open(noteID: targetURL, anchor: nil))
    }

    @Test("unresolved wikilink with notePath → .createNote")
    func unresolvedCreatesNote() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Missing"),
            sourceRange: LiminalSourceRange(start: 0, length: 11)
        )
        let sourceIndex = DocumentIndex(references: [ref])
        let sourceNote = LiminalNoteMetadata(url: sourceURL, relativePath: "Source.lim")
        let vault = VaultLinkIndex.build(
            notes: [sourceNote],
            documentIndexes: [sourceURL: sourceIndex]
        )
        let result = CmdClickHandler.decision(
            atByteOffset: 5,
            documentURL: sourceURL,
            documentIndex: sourceIndex,
            vaultLinkIndex: vault
        )
        #expect(result?.decision == .createNote(relativePath: "Missing"))
    }

    @Test("ambiguous wikilink → .showAmbiguous([candidates])")
    func ambiguousShowsCandidates() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let dupAURL = URL(fileURLWithPath: "/tmp/v/folder-a/Dup.lim")
        let dupBURL = URL(fileURLWithPath: "/tmp/v/folder-b/Dup.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Dup"),
            sourceRange: LiminalSourceRange(start: 0, length: 7)
        )
        let sourceIndex = DocumentIndex(references: [ref])
        let sourceNote = LiminalNoteMetadata(url: sourceURL, relativePath: "Source.lim")
        let dupA = LiminalNoteMetadata(url: dupAURL, relativePath: "folder-a/Dup.lim")
        let dupB = LiminalNoteMetadata(url: dupBURL, relativePath: "folder-b/Dup.lim")
        let vault = VaultLinkIndex.build(
            notes: [sourceNote, dupA, dupB],
            documentIndexes: [sourceURL: sourceIndex]
        )
        let result = CmdClickHandler.decision(
            atByteOffset: 3,
            documentURL: sourceURL,
            documentIndex: sourceIndex,
            vaultLinkIndex: vault
        )
        let expectedCandidates = [dupAURL, dupBURL].sorted { $0.absoluteString < $1.absoluteString }
        #expect(result?.decision == .showAmbiguous(expectedCandidates))
    }

    @Test("innermost reference wins when constructs nest")
    func innermostWins() {
        let docURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        // Outer construct spans 0..30; inner wikilink spans 10..20.
        // A click at byte 15 must resolve to the inner.
        let outer = DocumentReference(
            kind: .embed,
            target: WikiTarget.parse("Outer"),
            sourceRange: LiminalSourceRange(start: 0, length: 30)
        )
        let inner = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Inner"),
            sourceRange: LiminalSourceRange(start: 10, length: 10)
        )
        let docIndex = DocumentIndex(references: [outer, inner])
        let result = CmdClickHandler.decision(
            atByteOffset: 15,
            documentURL: docURL,
            documentIndex: docIndex,
            vaultLinkIndex: .empty
        )
        // Inner is unresolved → createNote("Inner"), not "Outer".
        #expect(result?.reference.target.notePath == "Inner")
        #expect(result?.decision == .createNote(relativePath: "Inner"))
    }
}
