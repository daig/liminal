import Foundation
import Testing
@testable import Liminal

@Suite("Workspace Linking")
struct WorkspaceLinkingTests {
    @Test(
        "wiki target parser preserves note and anchor components",
        arguments: [
            WikiTargetExpectation(
                description: "note only",
                raw: "Folder/Note",
                notePath: "Folder/Note",
                heading: nil,
                blockID: nil,
                rendered: "Folder/Note",
                isLocalOnly: false,
                hasAnchor: false
            ),
            WikiTargetExpectation(
                description: "note heading",
                raw: "Folder/Note#Heading",
                notePath: "Folder/Note",
                heading: "Heading",
                blockID: nil,
                rendered: "Folder/Note#Heading",
                isLocalOnly: false,
                hasAnchor: true
            ),
            WikiTargetExpectation(
                description: "local heading",
                raw: "#Heading",
                notePath: nil,
                heading: "Heading",
                blockID: nil,
                rendered: "#Heading",
                isLocalOnly: true,
                hasAnchor: true
            ),
            WikiTargetExpectation(
                description: "local block",
                raw: "#^block-id",
                notePath: nil,
                heading: nil,
                blockID: "block-id",
                rendered: "#^block-id",
                isLocalOnly: true,
                hasAnchor: true
            ),
            WikiTargetExpectation(
                description: "trims whitespace",
                raw: "  Folder/Note# Heading  ",
                notePath: "Folder/Note",
                heading: "Heading",
                blockID: nil,
                rendered: "Folder/Note#Heading",
                isLocalOnly: false,
                hasAnchor: true
            )
        ]
    )
    func wikiTargetParserPreservesComponents(_ expectation: WikiTargetExpectation) {
        let target = WikiTarget.parse(expectation.raw)

        #expect(target.notePath == expectation.notePath)
        #expect(target.heading == expectation.heading)
        #expect(target.blockID == expectation.blockID)
        #expect(target.rawTargetString == expectation.rendered)
        #expect(target.isLocalOnly == expectation.isLocalOnly)
        #expect(target.hasAnchor == expectation.hasAnchor)
    }

    @Test("wiki target initializer normalizes block IDs with or without caret")
    func wikiTargetInitializerNormalizesBlockIDsWithOrWithoutCaret() {
        let withCaret = WikiTarget(notePath: " Note ", blockID: " ^Block-ID ")
        let withoutCaret = WikiTarget(blockID: "block-id")

        #expect(withCaret.notePath == "Note")
        #expect(withCaret.blockID == "Block-ID")
        #expect(withCaret.rawTargetString == "Note#^Block-ID")
        #expect(withoutCaret.blockID == "block-id")
        #expect(withoutCaret.rawTargetString == "#^block-id")
    }

    @Test(
        "note lookup keys normalize markdown paths",
        arguments: [
            NormalizerExpectation(description: "plain note", raw: "Note", normalized: "note"),
            NormalizerExpectation(description: "mixed case path", raw: "Folder/Sub Note", normalized: "folder/sub note"),
            NormalizerExpectation(description: "markdown suffix", raw: "Folder/Note.md", normalized: "folder/note"),
            NormalizerExpectation(description: "backslashes", raw: "Folder\\Note.md", normalized: "folder/note"),
            NormalizerExpectation(description: "outer slashes and whitespace", raw: "  /Folder//Note.md/  ", normalized: "folder/note"),
            NormalizerExpectation(description: "empty path", raw: "  /  ", normalized: "")
        ]
    )
    func noteLookupKeysNormalizeMarkdownPaths(_ expectation: NormalizerExpectation) {
        #expect(WikiLinkNormalizer.noteLookupKey(expectation.raw) == expectation.normalized)
    }

    @Test(
        "heading lookup keys collapse whitespace and case",
        arguments: [
            NormalizerExpectation(description: "mixed case", raw: "Section Title", normalized: "section title"),
            NormalizerExpectation(description: "extra spaces", raw: "  Many   Spaces\nHere  ", normalized: "many spaces here"),
            NormalizerExpectation(description: "empty heading", raw: " \n ", normalized: "")
        ]
    )
    func headingLookupKeysCollapseWhitespaceAndCase(_ expectation: NormalizerExpectation) {
        #expect(WikiLinkNormalizer.headingLookupKey(expectation.raw) == expectation.normalized)
    }

    @Test(
        "block lookup keys trim whitespace and case",
        arguments: [
            NormalizerExpectation(description: "mixed case", raw: "Block-ID", normalized: "block-id"),
            NormalizerExpectation(description: "outer whitespace", raw: "  Block-ID  ", normalized: "block-id"),
            NormalizerExpectation(description: "empty block", raw: " \n ", normalized: "")
        ]
    )
    func blockLookupKeysTrimWhitespaceAndCase(_ expectation: NormalizerExpectation) {
        #expect(WikiLinkNormalizer.blockLookupKey(expectation.raw) == expectation.normalized)
    }

    @Test("document index maps source offsets to containing blocks and references")
    func documentIndexMapsSourceOffsetsToContainingBlocksAndReferences() throws {
        let index = DocumentIndex(
            blockOffsets: [10, 20, 35],
            headings: [HeadingAnchor(title: "Section Title", sourceOffset: 20)],
            blocks: [BlockAnchor(blockID: "Block-ID", sourceOffset: 35)],
            references: [
                DocumentReference(
                    kind: .link,
                    target: WikiTarget.parse("Target"),
                    sourceRange: LiminalSourceRange(start: 20, length: 5)
                )
            ]
        )

        let reference = try #require(index.reference(containing: 20))

        #expect(reference.target.notePath == "Target")
        #expect(index.reference(containing: 19) == nil)
        #expect(index.reference(containing: 24) == reference)
        #expect(index.reference(containing: 25) == nil)

        #expect(index.blockOffset(for: .sourceOffset(0)) == nil)
        #expect(index.blockOffset(for: .sourceOffset(10)) == 10)
        #expect(index.blockOffset(for: .sourceOffset(19)) == 10)
        #expect(index.blockOffset(for: .sourceOffset(20)) == 20)
        #expect(index.blockOffset(for: .sourceOffset(100)) == 35)
        #expect(index.blockOffset(for: .heading(" section   title ")) == 20)
        #expect(index.blockOffset(for: .block("block-id")) == 35)
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
                    alias: "Alias",
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
        let outgoingResolutions = outgoing.map(\.resolution)

        #expect(outgoingResolutions == [
            .resolved(.heading(beta.id, heading: "Section")),
            .resolved(.block(beta.id, blockID: "block-one")),
            .unresolved
        ])
        #expect(outgoing.first?.target.rawTargetString == "Beta#Section")
        #expect(outgoing.first?.alias == "Alias")
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
                description: "open resolved heading",
                target: WikiTarget.parse("Note#Section"),
                resolution: .resolved(.heading(URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"), heading: "Section")),
                decision: .open(
                    noteID: URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"),
                    anchor: .heading("Section")
                )
            ),
            LinkActivationExpectation(
                description: "open resolved block",
                target: WikiTarget.parse("Note#^block-id"),
                resolution: .resolved(.block(URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"), blockID: "block-id")),
                decision: .open(
                    noteID: URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"),
                    anchor: .block("block-id")
                )
            ),
            LinkActivationExpectation(
                description: "open note for missing anchor",
                target: WikiTarget.parse("Note#Missing"),
                resolution: .noteResolved(
                    URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"),
                    requestedAnchor: .heading("Missing")
                ),
                decision: .open(noteID: URL(fileURLWithPath: "/tmp/liminal-tests/Note.md"), anchor: nil)
            ),
            LinkActivationExpectation(
                description: "create unresolved note",
                target: WikiTarget.parse("Missing"),
                resolution: .unresolved,
                decision: .createNote(relativePath: "Missing")
            ),
            LinkActivationExpectation(
                description: "ignore unresolved local anchor",
                target: WikiTarget.parse("#Local Heading"),
                resolution: .unresolved,
                decision: .noAction
            ),
            LinkActivationExpectation(
                description: "surface ambiguous candidates",
                target: WikiTarget.parse("Dup"),
                resolution: .ambiguous([
                    URL(fileURLWithPath: "/tmp/liminal-tests/A/Dup.md"),
                    URL(fileURLWithPath: "/tmp/liminal-tests/B/Dup.md")
                ]),
                decision: .showAmbiguous([
                    URL(fileURLWithPath: "/tmp/liminal-tests/A/Dup.md"),
                    URL(fileURLWithPath: "/tmp/liminal-tests/B/Dup.md")
                ])
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

    @Test("backlink activation opens the source note at the reference offset")
    func backlinkActivationOpensSourceNoteAtReferenceOffset() {
        let reference = makeReference(
            sourceNoteID: URL(fileURLWithPath: "/tmp/liminal-tests/Source.md"),
            sourceRange: LiminalSourceRange(start: 42, length: 10),
            resolution: .resolved(.note(URL(fileURLWithPath: "/tmp/liminal-tests/Target.md")))
        )

        #expect(
            LinkActivationPolicy.decision(forBacklink: reference) == .open(
                noteID: URL(fileURLWithPath: "/tmp/liminal-tests/Source.md"),
                anchor: .sourceOffset(42)
            )
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

    private func makeReference(
        sourceNoteID: URL = URL(fileURLWithPath: "/tmp/liminal-tests/Source.md"),
        target: WikiTarget = WikiTarget.parse("Target"),
        sourceRange: LiminalSourceRange = LiminalSourceRange(start: 0, length: 8),
        resolution: ReferenceResolution
    ) -> ResolvedReference {
        ResolvedReference(
            sourceNoteID: sourceNoteID,
            kind: .link,
            target: target,
            alias: nil,
            sourceRange: sourceRange,
            sourceSnippet: "[[Target]]",
            resolution: resolution
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
    var isLocalOnly: Bool
    var hasAnchor: Bool

    var testDescription: String {
        description
    }
}

struct NormalizerExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var raw: String
    var normalized: String

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
