import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("BacklinkPresentation")
struct BacklinkPresentationTests {
    @Test("source label uses vault-relative path with .lim stripped")
    func sourceLabelStripsExtension() {
        let url = URL(fileURLWithPath: "/v/sub/Note.lim")
        let note = LiminalNote(url: url, relativePath: "sub/Note.lim")
        let ref = makeRef(sourceURL: url, start: 0)

        let label = BacklinkPresentation.sourceDisplayLabel(
            for: ref,
            notes: [url: note]
        )
        #expect(label == "sub/Note")
    }

    @Test("source label falls back to filename without extension when note is missing")
    func sourceLabelFallback() {
        let url = URL(fileURLWithPath: "/v/Orphan.lim")
        let ref = makeRef(sourceURL: url, start: 0)

        let label = BacklinkPresentation.sourceDisplayLabel(
            for: ref,
            notes: [:]
        )
        #expect(label == "Orphan")
    }

    @Test("sort orders backlinks alphabetically by source path then by source-range start")
    func sortOrder() {
        let alphaURL = URL(fileURLWithPath: "/v/Alpha.lim")
        let bravoURL = URL(fileURLWithPath: "/v/Bravo.lim")
        let charlieURL = URL(fileURLWithPath: "/v/Charlie.lim")

        let notes: [URL: LiminalNote] = [
            alphaURL: LiminalNote(url: alphaURL, relativePath: "Alpha.lim"),
            bravoURL: LiminalNote(url: bravoURL, relativePath: "Bravo.lim"),
            charlieURL: LiminalNote(url: charlieURL, relativePath: "Charlie.lim")
        ]

        // Two refs from Bravo (different offsets); one from Alpha;
        // one from Charlie. Expected: Alpha, Bravo@10, Bravo@40, Charlie.
        let refs = [
            makeRef(sourceURL: charlieURL, start: 5),
            makeRef(sourceURL: bravoURL, start: 40),
            makeRef(sourceURL: bravoURL, start: 10),
            makeRef(sourceURL: alphaURL, start: 25)
        ]

        let sorted = BacklinkPresentation.sorted(refs, notes: notes)
        let order = sorted.map { ($0.sourceNoteID.lastPathComponent, $0.sourceRange.start.rawValue) }
        #expect(order.map(\.0) == ["Alpha.lim", "Bravo.lim", "Bravo.lim", "Charlie.lim"])
        #expect(order.map(\.1) == [25, 10, 40, 5])
    }

    @Test("sort uses case-insensitive path compare")
    func sortCaseInsensitive() {
        let urlA = URL(fileURLWithPath: "/v/aaa.lim")
        let urlB = URL(fileURLWithPath: "/v/BBB.lim")
        let notes = [
            urlA: LiminalNote(url: urlA, relativePath: "aaa.lim"),
            urlB: LiminalNote(url: urlB, relativePath: "BBB.lim")
        ]
        let refs = [
            makeRef(sourceURL: urlB, start: 0),
            makeRef(sourceURL: urlA, start: 0)
        ]
        let sorted = BacklinkPresentation.sorted(refs, notes: notes)
        // "aaa" sorts before "BBB" only with case-insensitive compare.
        #expect(sorted.first?.sourceNoteID == urlA)
    }

    @Test("subfolder paths sort before higher-level files when relative paths put folder first")
    func subfolderPaths() {
        let topURL = URL(fileURLWithPath: "/v/Zoo.lim")
        let subURL = URL(fileURLWithPath: "/v/folder/Aardvark.lim")
        let notes = [
            topURL: LiminalNote(url: topURL, relativePath: "Zoo.lim"),
            subURL: LiminalNote(url: subURL, relativePath: "folder/Aardvark.lim")
        ]
        let refs = [
            makeRef(sourceURL: topURL, start: 0),
            makeRef(sourceURL: subURL, start: 0)
        ]
        let sorted = BacklinkPresentation.sorted(refs, notes: notes)
        // "folder/Aardvark" < "Zoo" alphabetically.
        #expect(sorted.first?.sourceNoteID == subURL)
    }

    private func makeRef(sourceURL: URL, start: UInt32) -> ResolvedReference {
        ResolvedReference(
            sourceNoteID: sourceURL,
            kind: .link,
            target: WikiTarget.parse("Target"),
            alias: nil,
            sourceRange: LiminalSourceRange(
                start: TextSize(start),
                length: TextSize(10)
            ),
            sourceSnippet: "snippet",
            resolution: .resolved(.note(URL(fileURLWithPath: "/v/Target.lim")))
        )
    }
}
