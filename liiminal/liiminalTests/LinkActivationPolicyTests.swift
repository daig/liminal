import XCTest
@testable import liiminal

final class LinkActivationPolicyTests: XCTestCase {
    func testResolvedReferenceOpensDestinationAnchor() {
        let noteID = URL(fileURLWithPath: "/tmp/Target.md")
        let reference = makeReference(
            target: WikiTarget(notePath: "Target", heading: "Section"),
            resolution: .resolved(.heading(noteID, heading: "Section"))
        )

        XCTAssertEqual(
            LinkActivationPolicy.decision(for: reference),
            .open(noteID: noteID, anchor: .heading("Section"))
        )
    }

    func testMissingAnchorStillOpensResolvedNote() {
        let noteID = URL(fileURLWithPath: "/tmp/Target.md")
        let reference = makeReference(
            target: WikiTarget(notePath: "Target", heading: "Missing"),
            resolution: .noteResolved(noteID, requestedAnchor: .heading("Missing"))
        )

        XCTAssertEqual(
            LinkActivationPolicy.decision(for: reference),
            .open(noteID: noteID, anchor: nil)
        )
    }

    func testUnresolvedNamedReferenceCreatesNote() {
        XCTAssertEqual(
            LinkActivationPolicy.decision(
                for: WikiTarget(notePath: "Folder/New Note"),
                resolution: .unresolved
            ),
            .createNote(relativePath: "Folder/New Note")
        )
    }

    func testUnresolvedLocalAnchorDoesNothing() {
        XCTAssertEqual(
            LinkActivationPolicy.decision(
                for: WikiTarget(heading: "Local Heading"),
                resolution: .unresolved
            ),
            .noAction
        )
    }

    func testAmbiguousReferenceSurfacesCandidates() {
        let first = URL(fileURLWithPath: "/tmp/A.md")
        let second = URL(fileURLWithPath: "/tmp/B.md")

        XCTAssertEqual(
            LinkActivationPolicy.decision(
                for: WikiTarget(notePath: "Dup"),
                resolution: .ambiguous([first, second])
            ),
            .showAmbiguous([first, second])
        )
    }

    func testBacklinkOpensSourceOffset() {
        let sourceNoteID = URL(fileURLWithPath: "/tmp/Source.md")
        let reference = makeReference(
            sourceNoteID: sourceNoteID,
            target: WikiTarget(notePath: "Target"),
            sourceSpan: SourceSpan(location: 42, length: 10),
            resolution: .resolved(.note(URL(fileURLWithPath: "/tmp/Target.md")))
        )

        XCTAssertEqual(
            LinkActivationPolicy.decision(forBacklink: reference),
            .open(noteID: sourceNoteID, anchor: .sourceOffset(42))
        )
    }

    private func makeReference(
        sourceNoteID: URL = URL(fileURLWithPath: "/tmp/Source.md"),
        target: WikiTarget,
        sourceSpan: SourceSpan = SourceSpan(location: 0, length: 8),
        resolution: ReferenceResolution
    ) -> ResolvedReference {
        ResolvedReference(
            sourceNoteID: sourceNoteID,
            kind: .link,
            target: target,
            alias: nil,
            sourceSpan: sourceSpan,
            sourceSnippet: "[[Target]]",
            resolution: resolution
        )
    }
}
