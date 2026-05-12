import CambiumCore
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

    @Test(
        "Phase 4.5 wiki target parser recognises external URI schemes",
        arguments: [
            ("https://example.org", true),
            ("http://example.org/path?q=1#frag", true),
            ("mailto:user@example.org", true),
            ("ftp://ftp.example.org", true),
            ("data:image/png;base64,abc", true),
            ("file:///tmp/foo", true),
            ("Folder/Note", false),
            ("Folder/Note#Heading", false),
            ("Note#^block-id", false),
            ("./relative-path", false),
            ("", false)
        ]
    )
    func phase45WikiTargetParserRecognisesExternalSchemes(_ inputs: (String, Bool)) {
        let (raw, expectedExternal) = inputs
        let target = WikiTarget.parse(raw)
        #expect(target.isExternal == expectedExternal,
                "expected isExternal=\(expectedExternal) for \(raw.debugDescription)")
        if expectedExternal {
            #expect(target.externalURI == raw)
            #expect(target.notePath == nil)
            #expect(target.heading == nil)
            #expect(target.blockID == nil)
            #expect(target.rawTargetString == raw)
        }
    }

    @Test("Phase 4.5 external targets route to openExternal regardless of resolution")
    func phase45ExternalTargetsRouteToOpenExternal() throws {
        let target = WikiTarget.parse("https://example.org/page")
        let url = try #require(URL(string: "https://example.org/page"))

        for resolution: ReferenceResolution in [
            .resolved(.note(URL(fileURLWithPath: "/tmp/note.md"))),
            .noteResolved(URL(fileURLWithPath: "/tmp/note.md"), requestedAnchor: .heading("X")),
            .unresolved,
            .ambiguous([URL(fileURLWithPath: "/tmp/a.md")])
        ] {
            let decision = LinkActivationPolicy.decision(for: target, resolution: resolution)
            #expect(decision == .openExternal(url),
                    "external target should win over resolution \(resolution)")
        }
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

    @Test("document index returns innermost containing reference")
    func documentIndexReturnsInnermostContainingReference() throws {
        let parent = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Parent"),
            sourceRange: LiminalSourceRange(start: 0, length: 20)
        )
        let child = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Child"),
            sourceRange: LiminalSourceRange(start: 5, length: 4)
        )
        let nestedIndex = DocumentIndex(references: [parent, child])

        #expect(nestedIndex.reference(containing: 6) == child)

        let firstTie = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("First"),
            sourceRange: LiminalSourceRange(start: 30, length: 5)
        )
        let secondTie = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Second"),
            sourceRange: LiminalSourceRange(start: 30, length: 5)
        )
        let tieIndex = DocumentIndex(references: [firstTie, secondTie])

        #expect(tieIndex.reference(containing: 32) == firstTie)
    }

    @Test("document index builds headings and wiki references from Slice 1 CST")
    func documentIndexBuildsHeadingsAndWikiReferencesFromSlice1CST() throws {
        let source = "# Section Title\n\nParagraph [[Target#Heading|Alias]] and ![[Embed#^block|payload]].\n![[BlockEmbed|raw payload]]\n"
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        #expect(index.blockOffsets == [0, 17, 83])
        #expect(index.headings == [
            HeadingAnchor(title: "Section Title", sourceOffset: 0)
        ])
        #expect(index.references.count == 3)

        #expect(index.references[0].kind == .link)
        #expect(index.references[0].target.rawTargetString == "Target#Heading")
        #expect(index.references[0].alias == "Alias")
        #expect(index.references[0].sourceRange == LiminalSourceRange(start: 27, length: 24))

        #expect(index.references[1].kind == .embed)
        #expect(index.references[1].target.rawTargetString == "Embed#^block")
        #expect(index.references[1].alias == "payload")

        #expect(index.references[2].kind == .embed)
        #expect(index.references[2].target.rawTargetString == "BlockEmbed")
        #expect(index.references[2].alias == "raw payload")
    }

    @Test("document index builds block anchors from Slice 3 suffixes")
    func documentIndexBuildsBlockAnchorsFromSlice3Suffixes() throws {
        let source = """
        # Section ^heading-block

        Paragraph [[Target]] ^para-block

        :::Callout
        Nested paragraph ^nested-block
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)
        let paragraphOffset = try sourceRange(of: "Paragraph", in: source).start
        let nestedParagraphOffset = try sourceRange(of: "Nested paragraph", in: source).start

        #expect(index.blocks == [
            BlockAnchor(blockID: "heading-block", sourceOffset: 0),
            BlockAnchor(blockID: "para-block", sourceOffset: paragraphOffset),
            BlockAnchor(blockID: "nested-block", sourceOffset: nestedParagraphOffset)
        ])
        #expect(index.blockOffset(for: .block("HEADING-BLOCK")) == 0)
        #expect(index.blockOffset(for: .block("para-block")) == paragraphOffset)
        #expect(index.references.map(\.target.rawTargetString) == ["Target"])
    }

    @Test("document index walks Slice 4 list and blockquote containers")
    func documentIndexWalksSlice4ListAndBlockquoteContainers() throws {
        let source = """
        - Item [[List Target]] ^list-item
          - Nested [[Nested Target]]

        > Quote [[Quote Target]]
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)
        let listItemOffset = try sourceRange(of: "- Item", in: source).start

        #expect(index.blocks == [
            BlockAnchor(blockID: "list-item", sourceOffset: listItemOffset)
        ])
        #expect(index.references.map(\.target.rawTargetString).sorted() == [
            "List Target",
            "Nested Target",
            "Quote Target"
        ])
        #expect(index.blockOffsets.count == 2)
    }

    @Test("document index stores target token ranges while preserving containment ranges")
    func documentIndexStoresTargetTokenRangesWhilePreservingContainmentRanges() throws {
        let source = "See [[Target|Alias]].\n"
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)
        let reference = try #require(index.references.first)

        #expect(reference.target.rawTargetString == "Target")
        #expect(reference.alias == "Alias")
        let targetRange = try sourceRange(of: "Target", in: source)
        let constructRange = try sourceRange(of: "[[Target|Alias]]", in: source)
        #expect(reference.targetRange == targetRange)
        #expect(reference.sourceRange == constructRange)

        for marker in ["[[", "Target", "|", "Alias", "]]"] {
            let offset = try sourceRange(of: marker, in: source).start
            #expect(index.reference(containing: offset) == reference)
        }
        #expect(index.reference(containing: reference.sourceRange.end) == nil)
    }

    @Test("target ranges propagate through vault link indexes")
    func targetRangesPropagateThroughVaultLinkIndexes() throws {
        let sourceNote = makeNote(relativePath: "Source.md", content: "See [[Target]].\n")
        let targetNote = makeNote(relativePath: "Target.md")
        let sourceIndex = try DocumentIndex.build(from: LiminalParser().parse(sourceNote.content))

        let index = VaultLinkIndex.build(
            notes: [sourceNote, targetNote],
            documentIndexes: [sourceNote.id: sourceIndex]
        )
        let reference = try #require(index.outgoing(for: sourceNote.id).first)

        #expect(reference.target.rawTargetString == "Target")
        let targetRange = try sourceRange(of: "Target", in: sourceNote.content)
        #expect(reference.targetRange == targetRange)
    }

    @Test("document index walks references in value declarations and typed-block bodies")
    func documentIndexWalksReferencesInValueDeclarationsAndTypedBlockBodies() throws {
        let source = """
        @Person#ada{
          bio: @[See [[Bio Note]] for details]
        }

        :::Callout
        Body with [[Linked Note]] inside.
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        let targets = index.references.map(\.target.rawTargetString).sorted()
        #expect(targets == ["Bio Note", "Linked Note"])
        // Both top-level items contribute to block offsets: the value
        // declaration and the typed block.
        #expect(index.blockOffsets.count == 2)
    }

    @Test("document index walks references in template bodies but not schema text")
    func documentIndexWalksReferencesInTemplateBodiesButNotSchemaText() throws {
        let source = """
        :::schema prelude
        type Hidden : value = { target: [[Ignored]] }
        :::
        :::template Card(person: Person) -> blocks
        See [[Template Target]]
        :::if{test: person.bio}
        Bio [[Nested Target]]
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        #expect(index.references.map(\.target.rawTargetString).sorted() == [
            "Nested Target",
            "Template Target"
        ])
        #expect(index.blockOffsets.count == 2)
    }

    @Test("only top-level headings populate the heading anchor space")
    func onlyTopLevelHeadingsPopulateTheHeadingAnchorSpace() throws {
        let source = """
        # Top-Level Heading

        :::Callout
        # Heading Inside Typed Block
        Body text.
        :::

        @Card{
          body: @{
            # Heading Inside Block Literal
            Inner paragraph.
          }
        }
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        #expect(index.headings.map(\.title) == ["Top-Level Heading"])
        // Top-level items still contribute block offsets: heading,
        // typed block, value declaration.
        #expect(index.blockOffsets.count == 3)
    }

    @Test("Phase 4.5 indexer emits references for structured embed targets and their fallback content")
    func phase45IndexerEmitsStructuredEmbedAndFallbackReferences() throws {
        // `!{Type}[fallback](target)` — the navigation reference is the
        // parenthesised target, not the type qname. Pre-4.5 the indexer
        // walked only the fallback content; the target token was
        // ignored. Now it emits a kind-.embed reference for the target
        // and still walks the fallback for wikilinks inside.
        #expect(
            try indexedTargets(in: "Paragraph !{Image}[Cover](cover.png)\n") == [
                "cover.png"
            ]
        )
        #expect(
            try indexedTargets(in: "Paragraph !{Image}[See [[Other]] for context](cover.png)\n") == [
                "cover.png",
                "Other"
            ]
        )
        #expect(
            try indexedTargets(in: "!{Image}[Cover](cover.png)\n") == [
                "cover.png"
            ]
        )
        #expect(
            try indexedTargets(in: "!{Image}[See [[Other]] for context](cover.png)\n") == [
                "cover.png",
                "Other"
            ]
        )
    }

    @Test("document index walks Slice 5 rich inline containers but skips raw payloads")
    func documentIndexWalksSlice5RichInlineContainersButSkipsRawPayloads() throws {
        let source = #"*[[Emphasis]]* **[[Strong]]** ~~[[Strike]]~~ ==[[Highlight]]== ^[[[Foot]]] %% [[Ignored Comment]] %% \([[Ignored Math]]\)"#
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        #expect(index.references.map(\.target.rawTargetString).sorted() == [
            "Emphasis",
            "Foot",
            "Highlight",
            "Strike",
            "Strong"
        ])
    }

    @Test("document index walks Slice 6 table cells but skips raw HTML payloads")
    func documentIndexWalksSlice6TableCellsButSkipsRawHTMLPayloads() throws {
        let source = """
        | [[Head]] | Embed |
        | --- | --- |
        | [[Cell]] | ![[Embed]] |
        :::HtmlBlock
        [[Ignored HTML]]
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        #expect(index.references.map(\.target.rawTargetString).sorted() == [
            "Cell",
            "Embed",
            "Head"
        ])
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

    @Test("Phase 4.5 indexer emits markdown link references with kind .link")
    func phase45IndexerEmitsMarkdownLinkReferences() throws {
        let source = "See [Site](https://example.org) and [Note](Folder/Note#Section).\n"
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        let links = index.references.filter { $0.kind == .link }
        #expect(links.count == 2)

        let external = try #require(links.first { $0.target.isExternal })
        #expect(external.target.externalURI == "https://example.org")
        #expect(external.alias == "Site")

        let vault = try #require(links.first { !$0.target.isExternal })
        #expect(vault.target.notePath == "Folder/Note")
        #expect(vault.target.heading == "Section")
        #expect(vault.alias == "Note")
    }

    @Test("Phase 4.5 indexer emits markdown image references with kind .embed")
    func phase45IndexerEmitsMarkdownImageReferences() throws {
        let source = "Header ![Alt text](cover.png) and ![Remote](https://example.org/img.png).\n"
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)

        let embeds = index.references.filter { $0.kind == .embed }
        #expect(embeds.map(\.target.rawTargetString).sorted() == [
            "cover.png",
            "https://example.org/img.png"
        ])
        // External image still resolves to external for activation.
        let remote = try #require(embeds.first { $0.target.isExternal })
        #expect(remote.alias == "Remote")
    }

    @Test("Phase 4.5 indexer drops references with empty destinations")
    func phase45IndexerDropsEmptyDestinationReferences() throws {
        let source = "Empty link [label]() and image ![alt]().\n"
        let parsed = try LiminalParser().parse(source)
        let index = DocumentIndex.build(from: parsed)
        #expect(index.references.isEmpty)
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

    private func indexedTargets(in source: String) throws -> [String] {
        let index = try DocumentIndex.build(from: LiminalParser().parse(source))
        return index.references.map(\.target.rawTargetString)
    }
}

private func sourceRange(of needle: String, in source: String) throws -> LiminalSourceRange {
    let range = try #require(source.range(of: needle))
    let start = source[..<range.lowerBound].utf8.count
    return LiminalSourceRange(
        start: TextSize(UInt32(start)),
        length: TextSize(UInt32(needle.utf8.count))
    )
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
