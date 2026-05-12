import AppKit
import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("HoverPreview slice computation")
struct HoverPreviewSliceTests {
    @Test("slice starts at the anchor's line, never above it")
    func sliceStartsAtAnchorLine() {
        let content = "line one\nline two\nline three\nline four\n"
        // Anchor in the middle of "line two" (byte 12 — "n" of "two").
        let (start, end) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: 12
        )
        let slice = HoverPreviewController.sliceContent(content, byteStart: start, byteEnd: end)
        // Start of "line two" is byte 9 — slice begins there, NOT at byte 0.
        #expect(start == 9)
        #expect(slice.hasPrefix("line two"))
        // Doesn't include "line one\n" content.
        #expect(!slice.contains("line one"))
    }

    @Test("slice respects maxLines cap")
    func sliceRespectsMaxLines() {
        let lines = (0..<20).map { "L\($0)" }
        let content = lines.joined(separator: "\n") + "\n"
        let (start, end) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: 0,
            maxLines: 5
        )
        let slice = HoverPreviewController.sliceContent(content, byteStart: start, byteEnd: end)
        // 5 newlines worth of content = 5 lines.
        let newlineCount = slice.utf8.filter { $0 == 0x0A }.count
        #expect(newlineCount == 5)
        #expect(slice.hasPrefix("L0\n"))
        #expect(start == 0)
    }

    @Test("slice respects maxBytes cap as a safety against pathological lines")
    func sliceRespectsMaxBytes() {
        // One ~5KB line followed by short ones.
        let longLine = String(repeating: "x", count: 5000)
        let content = longLine + "\nshort\n"
        let (start, end) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: 0,
            maxLines: 12,
            maxBytes: 1024
        )
        #expect(start == 0)
        #expect(end - start <= 1024)
    }

    @Test("anchor at start of file: slice begins at 0")
    func anchorAtStart() {
        let content = "one\ntwo\nthree\nfour\n"
        let (start, _) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: 0,
            maxBytes: 100
        )
        #expect(start == 0)
    }

    @Test("anchor near end of file: slice ends at end of file")
    func anchorAtEnd() {
        let content = "one\ntwo\nthree\nfour\n"
        let (_, end) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: content.utf8.count - 2,
            maxBytes: 100
        )
        #expect(end == content.utf8.count)
    }

    @Test("empty content returns (0, 0)")
    func emptyContent() {
        let (start, end) = HoverPreviewController.computeSliceRange(
            in: "",
            anchorByteOffset: 0,
            maxBytes: 100
        )
        #expect(start == 0)
        #expect(end == 0)
    }

    @Test("anchor past end is clamped")
    func anchorPastEnd() {
        let content = "one\ntwo\n"
        let (start, end) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: 999,
            maxBytes: 100
        )
        #expect(start <= content.utf8.count)
        #expect(end == content.utf8.count)
    }

    @Test("sliceContent extracts UTF-8 bytes safely")
    func sliceContentUTF8() {
        let content = "café résumé"  // multi-byte chars
        let bytes = Array(content.utf8)
        let slice = HoverPreviewController.sliceContent(
            content,
            byteStart: 0,
            byteEnd: bytes.count
        )
        #expect(slice == content)
    }
}

@Suite("HoverPreview title formatting")
struct HoverPreviewTitleTests {
    private static let url = URL(fileURLWithPath: "/tmp/v/Other.lim")

    @Test("no anchor: title is filename without extension")
    func noAnchor() {
        let target = HoverTarget(targetURL: Self.url, anchor: nil)
        #expect(HoverPreviewController.title(for: target) == "Other")
    }

    @Test("heading anchor: title shows › #Heading")
    func headingAnchor() {
        let target = HoverTarget(targetURL: Self.url, anchor: .heading("Goals"))
        #expect(HoverPreviewController.title(for: target) == "Other › #Goals")
    }

    @Test("block anchor: title shows › ^block-id")
    func blockAnchor() {
        let target = HoverTarget(targetURL: Self.url, anchor: .block("para-1"))
        #expect(HoverPreviewController.title(for: target) == "Other › ^para-1")
    }

    @Test("anchorMissing flag adds a notice")
    func anchorMissingNotice() {
        let target = HoverTarget(
            targetURL: Self.url,
            anchor: .heading("Gone"),
            anchorMissing: true
        )
        #expect(HoverPreviewController.title(for: target).contains("anchor not found"))
    }

    @Test("source-offset anchor falls back to filename only")
    func sourceOffsetAnchor() {
        let target = HoverTarget(
            targetURL: Self.url,
            anchor: .sourceOffset(TextSize(0))
        )
        #expect(HoverPreviewController.title(for: target) == "Other")
    }
}

@Suite("HoverPreview target resolution")
struct HoverPreviewTargetTests {
    @Test("external URI: returns nil (no preview for external links)")
    func externalReturnsNil() {
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("https://example.com"),
            sourceRange: LiminalSourceRange(start: 0, length: 19)
        )
        let url = URL(fileURLWithPath: "/tmp/v/Source.lim")
        #expect(HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: url,
            in: .empty
        ) == nil)
    }

    @Test("resolved cross-doc returns target with anchor")
    func crossDocResolved() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let targetURL = URL(fileURLWithPath: "/tmp/v/Target.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Target"),
            sourceRange: LiminalSourceRange(start: 0, length: 10)
        )
        let sourceNote = LiminalNote(url: sourceURL, relativePath: "Source.lim")
        let targetNote = LiminalNote(url: targetURL, relativePath: "Target.lim")
        let vault = VaultLinkIndex.build(
            notes: [sourceNote, targetNote],
            documentIndexes: [
                sourceURL: DocumentIndex(references: [ref]),
                targetURL: .empty
            ]
        )
        let result = HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: sourceURL,
            in: vault
        )
        #expect(result?.targetURL == targetURL)
        #expect(result?.anchor == nil)
        #expect(result?.anchorMissing == false)
    }

    @Test("noteResolved: target carries anchorMissing = true")
    func noteResolvedFlagsMissing() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let targetURL = URL(fileURLWithPath: "/tmp/v/Target.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Target#Missing"),
            sourceRange: LiminalSourceRange(start: 0, length: 18)
        )
        let sourceNote = LiminalNote(url: sourceURL, relativePath: "Source.lim")
        let targetNote = LiminalNote(url: targetURL, relativePath: "Target.lim")
        let vault = VaultLinkIndex.build(
            notes: [sourceNote, targetNote],
            documentIndexes: [
                sourceURL: DocumentIndex(references: [ref]),
                targetURL: .empty  // no headings
            ]
        )
        let result = HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: sourceURL,
            in: vault
        )
        #expect(result?.targetURL == targetURL)
        #expect(result?.anchor == .heading("Missing"))
        #expect(result?.anchorMissing == true)
    }

    @Test("unresolved wikilink: returns nil (no preview to create-from)")
    func unresolvedReturnsNil() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Missing"),
            sourceRange: LiminalSourceRange(start: 0, length: 11)
        )
        let vault = VaultLinkIndex.build(
            notes: [LiminalNote(url: sourceURL, relativePath: "Source.lim")],
            documentIndexes: [sourceURL: DocumentIndex(references: [ref])]
        )
        #expect(HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: sourceURL,
            in: vault
        ) == nil)
    }

    @Test("ambiguous wikilink: returns nil (no single doc to preview)")
    func ambiguousReturnsNil() {
        let sourceURL = URL(fileURLWithPath: "/tmp/v/Source.lim")
        let dupAURL = URL(fileURLWithPath: "/tmp/v/A/Dup.lim")
        let dupBURL = URL(fileURLWithPath: "/tmp/v/B/Dup.lim")
        let ref = DocumentReference(
            kind: .link,
            target: WikiTarget.parse("Dup"),
            sourceRange: LiminalSourceRange(start: 0, length: 7)
        )
        let vault = VaultLinkIndex.build(
            notes: [
                LiminalNote(url: sourceURL, relativePath: "Source.lim"),
                LiminalNote(url: dupAURL, relativePath: "A/Dup.lim"),
                LiminalNote(url: dupBURL, relativePath: "B/Dup.lim")
            ],
            documentIndexes: [sourceURL: DocumentIndex(references: [ref])]
        )
        #expect(HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: sourceURL,
            in: vault
        ) == nil)
    }

    @Test("within-doc heading anchor: target is current URL with heading anchor")
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
        let vault = VaultLinkIndex.build(
            notes: [LiminalNote(url: docURL, relativePath: "Source.lim")],
            documentIndexes: [docURL: docIndex]
        )
        let result = HoverPreviewController.hoverTarget(
            for: ref,
            currentURL: docURL,
            in: vault
        )
        #expect(result?.targetURL == docURL)
        #expect(result?.anchor == .heading("Goals"))
        #expect(result?.anchorMissing == false)
    }
}

@Suite("HoverPreview attributed-string assembly")
struct HoverPreviewAttributedTests {
    @Test("default attributes cover the entire slice")
    func defaultAttributesCover() {
        let slice = "hello world"
        let attr = HoverPreviewController.buildAttributedString(
            sliceText: slice,
            sliceByteStart: 0,
            spans: [],
            theme: .default
        )
        #expect(attr.length == (slice as NSString).length)
        // First character has *some* attribute (font / color from default).
        let attrs = attr.attributes(at: 0, effectiveRange: nil)
        #expect(!attrs.isEmpty)
    }

    @Test("spans whose byte ranges fall outside the slice are dropped")
    func outOfSliceSpansDropped() {
        let slice = "abcdef"
        // Span at byte 100 - 110, slice starts at 0 - well outside.
        let outOfRangeSpan = HighlightSpan(
            range: TextRange(start: TextSize(100), length: TextSize(10)),
            category: .typeName,
            modifiers: []
        )
        let attr = HoverPreviewController.buildAttributedString(
            sliceText: slice,
            sliceByteStart: 0,
            spans: [outOfRangeSpan],
            theme: .default
        )
        // Should still have default-attribute coverage; no crash.
        #expect(attr.length == (slice as NSString).length)
    }

    @Test("span byte ranges are translated to slice-local UTF-16 ranges")
    func spanRangeTranslation() {
        // Source has 20 bytes; slice covers bytes [10, 16) = 6 bytes.
        // A span at absolute bytes [12, 14) should map to slice-local
        // utf16 location 2, length 2.
        let slice = "abcdef"  // simulates the sliced content
        let span = HighlightSpan(
            range: TextRange(start: TextSize(12), length: TextSize(2)),
            category: .typeName,
            modifiers: []
        )
        let attr = HoverPreviewController.buildAttributedString(
            sliceText: slice,
            sliceByteStart: 10,
            spans: [span],
            theme: .default
        )
        // Attributes at location 2 should differ from defaults at
        // location 0 (because typeName has a distinct color).
        let defaultAttrs = attr.attributes(at: 0, effectiveRange: nil)
        let spanAttrs = attr.attributes(at: 2, effectiveRange: nil)
        // At minimum, the foreground color should have changed.
        let defaultFg = defaultAttrs[.foregroundColor] as? NSColor
        let spanFg = spanAttrs[.foregroundColor] as? NSColor
        #expect(defaultFg != spanFg)
    }
}
