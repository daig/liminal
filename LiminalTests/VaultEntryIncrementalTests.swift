import CambiumCore
import Foundation
import Testing
@testable import Liminal

/// The incremental `VaultLinkIndex.applying(...)` paths must produce a
/// result that is `Equatable`-identical to a from-scratch
/// `VaultLinkIndex.build(...)` over the same final note/index set. These
/// tests pin that equivalence for each shape of change: add, remove,
/// content edit without an anchor change, content edit with an anchor
/// change, and duplicate-title (ambiguity) transitions.
@Suite("VaultLinkIndex incremental updates")
struct VaultLinkIndexIncrementalTests {
    private func meta(_ relativePath: String) -> LiminalNoteMetadata {
        LiminalNoteMetadata(
            url: URL(fileURLWithPath: "/v/\(relativePath)"),
            relativePath: relativePath
        )
    }

    private func ref(
        _ target: String,
        at start: UInt32,
        length: UInt32 = 8,
        kind: ReferenceKind = .link
    ) -> DocumentReference {
        DocumentReference(
            kind: kind,
            target: WikiTarget.parse(target),
            sourceRange: LiminalSourceRange(
                start: TextSize(start),
                length: TextSize(length)
            )
        )
    }

    @Test("incremental adds match a from-scratch batch build")
    func incrementalAddMatchesBatch() {
        let a = meta("A.lim")
        let b = meta("B.lim")
        let c = meta("Folder/C.lim")
        let aIndex = DocumentIndex(references: [ref("B", at: 0), ref("C", at: 10)])
        let bIndex = DocumentIndex(
            headings: [HeadingAnchor(title: "Section", sourceOffset: 0)],
            references: [ref("C", at: 0)]
        )
        let cIndex = DocumentIndex.empty

        var incremental = VaultLinkIndex.empty
        incremental = incremental.applying(documentChange: a.id, metadata: a, index: aIndex)
        incremental = incremental.applying(documentChange: b.id, metadata: b, index: bIndex)
        incremental = incremental.applying(documentChange: c.id, metadata: c, index: cIndex)

        let batch = VaultLinkIndex.build(
            notes: [a, b, c],
            documentIndexes: [a.id: aIndex, b.id: bIndex, c.id: cIndex]
        )
        #expect(incremental == batch)
    }

    @Test("adding a note resolves referrers that previously dangled")
    func addingNoteResolvesDanglingReferrers() {
        let a = meta("A.lim")
        let b = meta("B.lim")
        let aIndex = DocumentIndex(references: [ref("B", at: 0)])

        // A alone: its [[B]] reference is unresolved.
        var incremental = VaultLinkIndex.empty
        incremental = incremental.applying(documentChange: a.id, metadata: a, index: aIndex)
        #expect(incremental.outgoing(for: a.id).first?.resolution == .unresolved)

        // Adding B must retroactively resolve A's reference.
        incremental = incremental.applying(documentChange: b.id, metadata: b, index: .empty)
        #expect(incremental.outgoing(for: a.id).first?.resolution == .resolved(.note(b.id)))

        let batch = VaultLinkIndex.build(
            notes: [a, b],
            documentIndexes: [a.id: aIndex, b.id: .empty]
        )
        #expect(incremental == batch)
    }

    @Test("incremental removal matches a batch build of the remaining set")
    func incrementalRemovalMatchesBatch() {
        let a = meta("A.lim")
        let b = meta("B.lim")
        let c = meta("C.lim")
        let aIndex = DocumentIndex(references: [ref("B", at: 0), ref("C", at: 10)])
        let bIndex = DocumentIndex(references: [ref("A", at: 0)])
        let cIndex = DocumentIndex.empty

        var incremental = VaultLinkIndex.build(
            notes: [a, b, c],
            documentIndexes: [a.id: aIndex, b.id: bIndex, c.id: cIndex]
        )
        incremental = incremental.applying(removalOf: b.id)

        // A's [[B]] reference must now dangle; A's [[C]] stays resolved.
        let aOutgoing = incremental.outgoing(for: a.id)
        #expect(aOutgoing.contains { $0.target.notePath == "B" && $0.resolution == .unresolved })
        #expect(aOutgoing.contains { $0.target.notePath == "C" && $0.resolution == .resolved(.note(c.id)) })

        let batch = VaultLinkIndex.build(
            notes: [a, c],
            documentIndexes: [a.id: aIndex, c.id: cIndex]
        )
        #expect(incremental == batch)
    }

    @Test("content edit with no anchor change matches a batch build")
    func contentEditNoAnchorChangeMatchesBatch() {
        let a = meta("A.lim")
        let b = meta("B.lim")
        let before = DocumentIndex(references: [ref("B", at: 0)])
        // A second reference to B is added; B's headings/blocks unchanged.
        let after = DocumentIndex(references: [ref("B", at: 0), ref("B", at: 30)])

        var incremental = VaultLinkIndex.build(
            notes: [a, b],
            documentIndexes: [a.id: before, b.id: .empty]
        )
        incremental = incremental.applying(documentChange: a.id, metadata: a, index: after)

        let batch = VaultLinkIndex.build(
            notes: [a, b],
            documentIndexes: [a.id: after, b.id: .empty]
        )
        #expect(incremental == batch)
        #expect(incremental.backlinks(for: b.id).count == 2)
    }

    @Test("content edit that changes anchors re-resolves incoming references")
    func contentEditAnchorChangeMatchesBatch() {
        let a = meta("A.lim")
        let b = meta("B.lim")
        // A targets B#Section.
        let aIndex = DocumentIndex(references: [ref("B#Section", at: 0, length: 13)])
        // B starts with no headings, then gains "Section".
        let bBefore = DocumentIndex.empty
        let bAfter = DocumentIndex(headings: [HeadingAnchor(title: "Section", sourceOffset: 0)])

        var incremental = VaultLinkIndex.build(
            notes: [a, b],
            documentIndexes: [a.id: aIndex, b.id: bBefore]
        )
        // Before the edit, the anchor is missing: note-resolved only.
        #expect(
            incremental.outgoing(for: a.id).first?.resolution
                == .noteResolved(b.id, requestedAnchor: .heading("Section"))
        )

        incremental = incremental.applying(documentChange: b.id, metadata: b, index: bAfter)
        // After B gains the heading, A's reference fully resolves.
        #expect(
            incremental.outgoing(for: a.id).first?.resolution
                == .resolved(.heading(b.id, heading: "Section"))
        )

        let batch = VaultLinkIndex.build(
            notes: [a, b],
            documentIndexes: [a.id: aIndex, b.id: bAfter]
        )
        #expect(incremental == batch)
    }

    @Test("duplicate-title add then remove tracks ambiguity like a batch build")
    func duplicateTitleAmbiguityMatchesBatch() {
        let dupA = LiminalNoteMetadata(
            url: URL(fileURLWithPath: "/v/x/Dup.lim"),
            relativePath: "x/Dup.lim"
        )
        let dupB = LiminalNoteMetadata(
            url: URL(fileURLWithPath: "/v/y/Dup.lim"),
            relativePath: "y/Dup.lim"
        )
        let src = meta("Src.lim")
        let srcIndex = DocumentIndex(references: [ref("Dup", at: 0)])

        // src + dupA: the bare [[Dup]] resolves uniquely.
        var incremental = VaultLinkIndex.build(
            notes: [src, dupA],
            documentIndexes: [src.id: srcIndex]
        )
        #expect(incremental.outgoing(for: src.id).first?.resolution == .resolved(.note(dupA.id)))

        // Adding dupB makes [[Dup]] ambiguous.
        incremental = incremental.applying(documentChange: dupB.id, metadata: dupB, index: .empty)
        let batchBoth = VaultLinkIndex.build(
            notes: [src, dupA, dupB],
            documentIndexes: [src.id: srcIndex]
        )
        #expect(incremental == batchBoth)
        if case .ambiguous = incremental.outgoing(for: src.id).first?.resolution {} else {
            Issue.record("expected [[Dup]] to be ambiguous with two duplicate-title notes")
        }

        // Removing dupA collapses back to a unique resolution.
        incremental = incremental.applying(removalOf: dupA.id)
        let batchAfterRemove = VaultLinkIndex.build(
            notes: [src, dupB],
            documentIndexes: [src.id: srcIndex]
        )
        #expect(incremental == batchAfterRemove)
        #expect(incremental.outgoing(for: src.id).first?.resolution == .resolved(.note(dupB.id)))
    }
}
