import Foundation
import Testing
@testable import Liminal

@Suite("Workspace Linking")
struct WorkspaceLinkingTests {
    @Test(
        "wiki target parser preserves note and anchor components",
        arguments: [
            WikiTargetExpectation(
                description: "note heading",
                raw: "Folder/Note#Heading",
                notePath: "Folder/Note",
                heading: "Heading",
                blockID: nil,
                rendered: "Folder/Note#Heading"
            ),
            WikiTargetExpectation(
                description: "local block",
                raw: "#^block-id",
                notePath: nil,
                heading: nil,
                blockID: "block-id",
                rendered: "#^block-id"
            )
        ]
    )
    func wikiTargetParserPreservesComponents(_ expectation: WikiTargetExpectation) {
        let target = WikiTarget.parse(expectation.raw)

        #expect(target.notePath == expectation.notePath)
        #expect(target.heading == expectation.heading)
        #expect(target.blockID == expectation.blockID)
        #expect(target.rawTargetString == expectation.rendered)
    }

    @Test("document index maps a source offset to its containing block and reference")
    func documentIndexMapsSourceOffsetToContainingBlock() throws {
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

        let reference = try #require(index.reference(containing: 30))

        #expect(reference.target.notePath == "Target")
        #expect(index.blockOffset(for: .sourceOffset(30)) == 24)
    }

    @Test("vault link index resolves anchors and backlinks from explicit indexes")
    func vaultLinkIndexResolvesAnchorsAndBacklinksFromExplicitIndexes() {
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
        let outgoingResolutions = index.outgoing(for: sourceNote.id).map(\.resolution)

        #expect(outgoingResolutions == [
            .resolved(.heading(beta.id, heading: "Section")),
            .resolved(.block(beta.id, blockID: "block-one")),
            .unresolved
        ])
        #expect(index.backlinks(for: beta.id).count == 2)
    }

    @Test("duplicate titles stay ambiguous unless path-qualified")
    func duplicateTitlesStayAmbiguousUnlessPathQualified() {
        let source = makeNote(relativePath: "Source.md")
        let dupA = makeNote(relativePath: "Folder A/Dup.md")
        let dupB = makeNote(relativePath: "Folder B/Dup.md")
        let index = VaultLinkIndex.build(notes: [source, dupA, dupB])

        #expect(index.resolve(target: WikiTarget.parse("Dup"), from: source.id) == .ambiguous([dupA.id, dupB.id]))
        #expect(index.resolve(target: WikiTarget.parse("Folder A/Dup#Missing"), from: source.id) == .noteResolved(dupA.id, requestedAnchor: .heading("Missing")))
    }

    @Test(
        "link activation decisions follow reference resolution",
        arguments: [
            LinkActivationExpectation(
                description: "open resolved note",
                target: WikiTarget.parse("Note"),
                resolution: .resolved(.note(URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"))),
                decision: .open(noteID: URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"), anchor: nil)
            ),
            LinkActivationExpectation(
                description: "create unresolved note",
                target: WikiTarget.parse("Missing"),
                resolution: .unresolved,
                decision: .createNote(relativePath: "Missing")
            )
        ]
    )
    func linkActivationDecisionsFollowResolution(_ expectation: LinkActivationExpectation) {
        #expect(
            LinkActivationPolicy.decision(
                for: expectation.target,
                resolution: expectation.resolution
            ) == expectation.decision
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

struct WikiTargetExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var raw: String
    var notePath: String?
    var heading: String?
    var blockID: String?
    var rendered: String

    var testDescription: String {
        description
    }
}

struct LinkActivationExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var target: WikiTarget
    var resolution: ReferenceResolution
    var decision: LinkActivationDecision

    var testDescription: String {
        description
    }
}
