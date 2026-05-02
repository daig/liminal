import XCTest
import LiminalWorkspace

final class LiminalWorkspaceTests: XCTestCase {
    func testWikiTargetParsesNoteHeadingAndBlockTargets() {
        let heading = WikiTarget.parse("Folder/Note#Heading")
        XCTAssertEqual(heading.notePath, "Folder/Note")
        XCTAssertEqual(heading.heading, "Heading")
        XCTAssertNil(heading.blockID)
        XCTAssertEqual(heading.rawTargetString, "Folder/Note#Heading")

        let block = WikiTarget.parse("#^block-id")
        XCTAssertNil(block.notePath)
        XCTAssertNil(block.heading)
        XCTAssertEqual(block.blockID, "block-id")
        XCTAssertEqual(block.rawTargetString, "#^block-id")
    }

    func testDocumentIndexMapsSourceOffsetToContainingBlock() {
        let index = DocumentIndex(
            blockOffsets: [0, 10, 24],
            references: [
                DocumentReference(
                    kind: .link,
                    target: WikiTarget.parse("Target"),
                    sourceRange: LiminalSourceRange(start: 28, length: 10)
                )
            ]
        )

        let reference = index.reference(containing: 30)

        XCTAssertEqual(reference?.target.notePath, "Target")
        XCTAssertEqual(index.blockOffset(for: .sourceOffset(30)), 24)
    }

    func testVaultLinkIndexResolvesAnchorsAndBacklinksFromExplicitIndexes() {
        let sourceNote = makeNote(
            relativePath: "Source.md",
            content: "[[Beta#Section]]\n[[Beta#^block-one]]\n[[Gamma]]\n"
        )
        let beta = makeNote(
            relativePath: "Beta.md",
            content: "# Section\n\nParagraph ^block-one\n"
        )
        let sourceIndex = DocumentIndex(
            references: [
                DocumentReference(
                    kind: .link,
                    target: WikiTarget.parse("Beta#Section"),
                    sourceRange: LiminalSourceRange(start: 0, length: 16)
                ),
                DocumentReference(
                    kind: .link,
                    target: WikiTarget.parse("Beta#^block-one"),
                    sourceRange: LiminalSourceRange(start: 17, length: 20)
                ),
                DocumentReference(
                    kind: .link,
                    target: WikiTarget.parse("Gamma"),
                    sourceRange: LiminalSourceRange(start: 38, length: 9)
                )
            ]
        )
        let betaIndex = DocumentIndex(
            headings: [HeadingAnchor(title: "Section", sourceOffset: 0)],
            blocks: [BlockAnchor(blockID: "block-one", sourceOffset: 11)]
        )

        let index = VaultLinkIndex.build(
            notes: [sourceNote, beta],
            documentIndexes: [
                sourceNote.id: sourceIndex,
                beta.id: betaIndex
            ]
        )
        let outgoing = index.outgoing(for: sourceNote.id)

        XCTAssertEqual(outgoing.count, 3)
        XCTAssertEqual(outgoing[0].resolution, .resolved(.heading(beta.id, heading: "Section")))
        XCTAssertEqual(outgoing[1].resolution, .resolved(.block(beta.id, blockID: "block-one")))
        XCTAssertEqual(outgoing[2].resolution, .unresolved)
        XCTAssertEqual(index.backlinks(for: beta.id).count, 2)
    }

    func testVaultLinkIndexKeepsDuplicateTitlesAmbiguousUnlessPathQualified() {
        let source = makeNote(relativePath: "Source.md")
        let dupA = makeNote(relativePath: "Folder A/Dup.md")
        let dupB = makeNote(relativePath: "Folder B/Dup.md")
        let index = VaultLinkIndex.build(notes: [source, dupA, dupB])

        XCTAssertEqual(index.resolve(target: WikiTarget.parse("Dup"), from: source.id), .ambiguous([dupA.id, dupB.id]))
        XCTAssertEqual(
            index.resolve(target: WikiTarget.parse("Folder A/Dup#Missing"), from: source.id),
            .noteResolved(dupA.id, requestedAnchor: .heading("Missing"))
        )
    }

    func testLinkActivationPolicyMatchesResolutionShape() {
        let noteID = URL(fileURLWithPath: "/tmp/liminal-tests/Note.md")

        XCTAssertEqual(
            LinkActivationPolicy.decision(
                for: WikiTarget.parse("Note"),
                resolution: .resolved(.note(noteID))
            ),
            .open(noteID: noteID, anchor: nil)
        )
        XCTAssertEqual(
            LinkActivationPolicy.decision(
                for: WikiTarget.parse("Missing"),
                resolution: .unresolved
            ),
            .createNote(relativePath: "Missing")
        )
    }

    private func makeNote(relativePath: String, content: String = "") -> LiminalNote {
        LiminalNote(
            url: URL(fileURLWithPath: "/tmp/liminal-tests/\(relativePath)"),
            relativePath: relativePath,
            content: content,
            lastModified: .distantPast
        )
    }
}
