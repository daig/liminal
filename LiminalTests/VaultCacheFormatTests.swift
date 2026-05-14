import CambiumCore
import Foundation
import Testing
@testable import Liminal

/// The vault cache is a pure cold-start optimization, so its codec must
/// be strict: a clean encode/decode roundtrip when valid, and a thrown
/// error (never a silently wrong snapshot) for anything corrupt or
/// version-mismatched. These tests pin both halves of that contract.
@Suite("VaultCacheFormat")
struct VaultCacheFormatTests {
    // MARK: Fixtures

    /// A snapshot exercising every field: multiple entries, headings,
    /// block anchors, references with vault + external + anchored
    /// targets, present and absent target ranges, aliases, and snippets.
    private func sampleSnapshot() -> VaultCacheSnapshot {
        let vaultRef = DocumentReference(
            kind: .link,
            target: WikiTarget(notePath: "Other", heading: "Section"),
            alias: "see here",
            sourceRange: TextRange(start: TextSize(4), length: TextSize(20)),
            targetRange: TextRange(start: TextSize(6), length: TextSize(5)),
            snippet: DocumentSnippet(
                text: "context [[Other#Section]] more context",
                referenceOffset: 8,
                referenceLength: 17
            )
        )
        let externalRef = DocumentReference(
            kind: .embed,
            target: WikiTarget(externalURI: "https://example.org/x"),
            alias: nil,
            sourceRange: TextRange(start: TextSize(40), length: TextSize(25)),
            targetRange: nil,
            snippet: .empty
        )
        let blockRef = DocumentReference(
            kind: .link,
            target: WikiTarget(notePath: "Notes/Deep", blockID: "para-7"),
            alias: nil,
            sourceRange: TextRange(start: TextSize(70), length: TextSize(18)),
            targetRange: TextRange(start: TextSize(72), length: TextSize(10)),
            snippet: DocumentSnippet(text: "tail [[Notes/Deep#^para-7]]", referenceOffset: 5, referenceLength: 22)
        )

        let source = VaultCacheEntry(
            relativePath: "Source.lim",
            title: "Source",
            fileMtime: Date(timeIntervalSince1970: 1_700_000_000),
            fileByteSize: 412,
            contentHash: VaultCacheFormat.contentHash(Array("source bytes".utf8)),
            index: DocumentIndex(
                blockOffsets: [TextSize(0), TextSize(30), TextSize(66)],
                headings: [
                    HeadingAnchor(title: "Top", sourceOffset: TextSize(0), level: 1),
                    HeadingAnchor(title: "Sub", sourceOffset: TextSize(30), level: 2)
                ],
                blocks: [BlockAnchor(blockID: "intro", sourceOffset: TextSize(30))],
                references: [vaultRef, externalRef, blockRef]
            )
        )
        let target = VaultCacheEntry(
            relativePath: "Folder/Other.lim",
            title: "Other",
            fileMtime: Date(timeIntervalSince1970: 1_699_000_500),
            fileByteSize: 88,
            contentHash: VaultCacheFormat.contentHash(Array("other".utf8)),
            index: DocumentIndex(
                headings: [HeadingAnchor(title: "Section", sourceOffset: TextSize(0), level: 1)]
            )
        )
        // An entry with a distant-past mtime exercises the "unknown" sentinel.
        let untracked = VaultCacheEntry(
            relativePath: "New.lim",
            title: "New",
            fileMtime: .distantPast,
            fileByteSize: 0,
            contentHash: 0,
            index: .empty
        )

        return VaultCacheSnapshot(entries: [source, target, untracked])
    }

    // MARK: Roundtrip

    @Test("encode then decode reproduces the snapshot exactly")
    func roundtripPreservesSnapshot() throws {
        let snapshot = sampleSnapshot()
        let bytes = VaultCacheFormat.encode(snapshot, vaultRootHint: "/Users/dai/Vault")
        let decoded = try VaultCacheFormat.decode(bytes)
        #expect(decoded == snapshot)
    }

    @Test("empty snapshot roundtrips")
    func roundtripEmptySnapshot() throws {
        let snapshot = VaultCacheSnapshot(entries: [])
        let bytes = VaultCacheFormat.encode(snapshot, vaultRootHint: "/v")
        #expect(try VaultCacheFormat.decode(bytes) == snapshot)
    }

    @Test("decoded reference fields survive intact, including the optional/nil split")
    func roundtripPreservesReferenceFields() throws {
        let snapshot = sampleSnapshot()
        let decoded = try VaultCacheFormat.decode(
            VaultCacheFormat.encode(snapshot, vaultRootHint: "/v")
        )
        let references = try #require(decoded.entries.first).index.references
        #expect(references.count == 3)

        let vault = references[0]
        #expect(vault.kind == .link)
        #expect(vault.target.notePath == "Other")
        #expect(vault.target.heading == "Section")
        #expect(vault.target.blockID == nil)
        #expect(vault.target.externalURI == nil)
        #expect(vault.alias == "see here")
        #expect(vault.targetRange == TextRange(start: TextSize(6), length: TextSize(5)))
        #expect(vault.snippet.referenceOffset == 8)
        #expect(vault.snippet.referenceLength == 17)

        let external = references[1]
        #expect(external.kind == .embed)
        #expect(external.target.externalURI == "https://example.org/x")
        #expect(external.target.notePath == nil)
        #expect(external.alias == nil)
        #expect(external.targetRange == nil)
        #expect(external.snippet == .empty)

        let block = references[2]
        #expect(block.target.notePath == "Notes/Deep")
        #expect(block.target.blockID == "para-7")
        #expect(block.target.heading == nil)
    }

    @Test("distant-past mtime roundtrips through the unknown sentinel")
    func roundtripDistantPastMtime() throws {
        let snapshot = sampleSnapshot()
        let decoded = try VaultCacheFormat.decode(
            VaultCacheFormat.encode(snapshot, vaultRootHint: "/v")
        )
        let untracked = try #require(decoded.entries.first { $0.relativePath == "New.lim" })
        #expect(untracked.fileMtime == .distantPast)
    }

    @Test("repeated strings across entries roundtrip correctly via the string pool")
    func roundtripDeduplicatedStrings() throws {
        // Two entries sharing a heading title and a snippet exercise the
        // interning path; correctness after roundtrip is the contract.
        let sharedSnippet = DocumentSnippet(text: "the same shared context", referenceOffset: 4, referenceLength: 4)
        func entry(_ path: String) -> VaultCacheEntry {
            VaultCacheEntry(
                relativePath: path,
                title: path,
                fileMtime: Date(timeIntervalSince1970: 1_700_000_000),
                fileByteSize: 10,
                contentHash: 1,
                index: DocumentIndex(
                    headings: [HeadingAnchor(title: "Shared Title", sourceOffset: TextSize(0))],
                    references: [
                        DocumentReference(
                            kind: .link,
                            target: WikiTarget(notePath: "Common"),
                            sourceRange: TextRange(start: TextSize(0), length: TextSize(4)),
                            snippet: sharedSnippet
                        )
                    ]
                )
            )
        }
        let snapshot = VaultCacheSnapshot(entries: [entry("A.lim"), entry("B.lim")])
        let decoded = try VaultCacheFormat.decode(
            VaultCacheFormat.encode(snapshot, vaultRootHint: "/v")
        )
        #expect(decoded == snapshot)
    }

    // MARK: Rejection paths

    @Test("a non-cache byte stream is rejected with badMagic")
    func badMagicRejected() {
        let notACache = Array("definitely not a cache file".utf8)
        #expect(throws: VaultCacheError.badMagic) {
            try VaultCacheFormat.decode(notACache)
        }
    }

    @Test("truncated input is rejected, not silently half-decoded")
    func truncatedInputRejected() throws {
        let bytes = VaultCacheFormat.encode(sampleSnapshot(), vaultRootHint: "/v")
        // Drop the final 20 bytes — mid record-list.
        let truncated = Array(bytes.dropLast(20))
        #expect(throws: VaultCacheError.truncatedInput) {
            try VaultCacheFormat.decode(truncated)
        }
    }

    @Test("trailing bytes after the last record are rejected")
    func trailingBytesRejected() throws {
        var bytes = VaultCacheFormat.encode(sampleSnapshot(), vaultRootHint: "/v")
        bytes.append(contentsOf: [0xAA, 0xBB, 0xCC])
        #expect(throws: VaultCacheError.trailingBytes(3)) {
            try VaultCacheFormat.decode(bytes)
        }
    }

    @Test("a future format version is rejected")
    func formatVersionMismatchRejected() throws {
        var bytes = VaultCacheFormat.encode(sampleSnapshot(), vaultRootHint: "/v")
        // formatVersion is the UInt32 immediately after the 8-byte magic.
        overwriteUInt32(in: &bytes, at: 8, with: 999)
        #expect(throws: VaultCacheError.unsupportedFormatVersion(999)) {
            try VaultCacheFormat.decode(bytes)
        }
    }

    @Test("a language-version mismatch is rejected")
    func languageVersionMismatchRejected() throws {
        var bytes = VaultCacheFormat.encode(sampleSnapshot(), vaultRootHint: "/v")
        // Header layout: magic[8] formatVersion[4] languageID(len[4]+bytes)
        // languageVersion[4] indexSchemaVersion[4] ...
        let langIDLen = LiminalLanguage.serializationID.utf8.count
        let languageVersionOffset = 8 + 4 + 4 + langIDLen
        overwriteUInt32(in: &bytes, at: languageVersionOffset, with: 0xDEAD)
        #expect(throws: (any Error).self) {
            try VaultCacheFormat.decode(bytes)
        }
    }

    @Test("an index-schema-version mismatch is rejected")
    func indexSchemaMismatchRejected() throws {
        var bytes = VaultCacheFormat.encode(sampleSnapshot(), vaultRootHint: "/v")
        let langIDLen = LiminalLanguage.serializationID.utf8.count
        let indexSchemaOffset = 8 + 4 + 4 + langIDLen + 4
        let bogus: UInt32 = VaultCacheFormat.indexSchemaVersion &+ 1
        overwriteUInt32(in: &bytes, at: indexSchemaOffset, with: bogus)
        #expect(throws: VaultCacheError.indexSchemaMismatch(
            expected: VaultCacheFormat.indexSchemaVersion,
            found: bogus
        )) {
            try VaultCacheFormat.decode(bytes)
        }
    }

    // MARK: - Helpers

    /// Overwrite the little-endian `UInt32` at `offset` in `bytes`.
    private func overwriteUInt32(in bytes: inout [UInt8], at offset: Int, with value: UInt32) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
