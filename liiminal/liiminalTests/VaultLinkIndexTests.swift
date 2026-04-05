import XCTest
@testable import liiminal

final class VaultLinkIndexTests: XCTestCase {
    func testVaultLinkIndexResolvesAnchorsAndBacklinks() {
        let sourceNote = makeNote(
            relativePath: "Source.md",
            content: """
            [[Beta#Section]]
            [[Beta#^block-one]]
            [[Gamma]]
            """
        )
        let beta = makeNote(
            relativePath: "Beta.md",
            content: """
            # Section

            Paragraph ^block-one
            """
        )

        let index = VaultLinkIndex.build(notes: [sourceNote, beta])
        let outgoing = index.outgoing(for: sourceNote.id)

        XCTAssertEqual(outgoing.count, 3)

        XCTAssertEqual(
            outgoing[0].resolution,
            .resolved(.heading(beta.id, heading: "Section"))
        )
        XCTAssertEqual(
            outgoing[1].resolution,
            .resolved(.block(beta.id, blockID: "block-one"))
        )
        XCTAssertEqual(outgoing[2].resolution, .unresolved)

        let betaBacklinks = index.backlinks(for: beta.id)
        XCTAssertEqual(betaBacklinks.count, 2)
        XCTAssertTrue(betaBacklinks.allSatisfy { $0.sourceNoteID == sourceNote.id })
    }

    func testVaultLinkIndexKeepsDuplicateTitlesAmbiguousUnlessPathQualified() {
        let source = makeNote(
            relativePath: "Source.md",
            content: """
            [[Dup]]
            [[Folder A/Dup#Missing]]
            """
        )
        let dupA = makeNote(relativePath: "Folder A/Dup.md", content: "# Here")
        let dupB = makeNote(relativePath: "Folder B/Dup.md", content: "# Elsewhere")

        let index = VaultLinkIndex.build(notes: [source, dupA, dupB])
        let outgoing = index.outgoing(for: source.id)

        XCTAssertEqual(outgoing.count, 2)

        guard case .ambiguous(let ambiguousMatches) = outgoing[0].resolution else {
            return XCTFail("Expected ambiguous duplicate title resolution")
        }
        XCTAssertEqual(Set(ambiguousMatches), Set([dupA.id, dupB.id]))

        XCTAssertEqual(
            outgoing[1].resolution,
            .noteResolved(dupA.id, requestedAnchor: .heading("Missing"))
        )
    }

    private func makeNote(relativePath: String, content: String) -> Note {
        Note(
            url: URL(fileURLWithPath: "/tmp/liminal-tests/\(relativePath)"),
            relativePath: relativePath,
            content: content,
            lastModified: .distantPast
        )
    }
}
