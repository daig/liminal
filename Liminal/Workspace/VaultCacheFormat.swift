import CambiumCore
import Foundation

/// Errors thrown while decoding a vault cache file.
///
/// The cache is purely a cold-start optimization — every decode failure
/// is fully recoverable by falling back to a fresh vault scan, so callers
/// treat any thrown error as simply "no usable cache."
enum VaultCacheError: Error, Equatable {
    /// Input does not start with the `LMVCACHE` magic bytes.
    case badMagic
    /// The file's format version is not the one this build understands.
    case unsupportedFormatVersion(UInt32)
    /// The serialized language ID / version does not match the current
    /// `LiminalLanguage` — the grammar changed, so cached indexes built
    /// from old parses can't be trusted.
    case languageMismatch(
        expectedID: String,
        foundID: String,
        expectedVersion: UInt32,
        foundVersion: UInt32
    )
    /// The `DocumentIndex` / `DocumentReference` on-disk shape changed.
    case indexSchemaMismatch(expected: UInt32, found: UInt32)
    /// The decoder ran out of input mid-record.
    case truncatedInput
    /// A string-table entry was not valid UTF-8.
    case invalidUTF8
    /// A length / count field exceeded the representable range.
    case integerOverflow
    /// A record referenced a string-pool index that doesn't exist.
    case stringPoolIndexOutOfRange(UInt32)
    /// A reference record carried an unknown kind tag.
    case unknownReferenceKind(UInt8)
    /// Trailing bytes remained after the decoder finished the last record.
    case trailingBytes(Int)
}

/// In-memory shape of a decoded (or about-to-be-encoded) vault cache: one
/// entry per tracked `.lim` note, keyed by vault-relative path.
///
/// Absolute URLs are intentionally not stored — the loader reconstructs
/// them from the live vault root, so the cache file is portable and the
/// cache lives outside the vault tree (see `VaultCacheStore`).
struct VaultCacheSnapshot: Equatable {
    var entries: [VaultCacheEntry]
}

struct VaultCacheEntry: Equatable {
    /// Vault-relative path, e.g. `Folder/Note.lim`.
    var relativePath: String
    /// Display title (filename without extension). Redundant with the
    /// path today, but stored so the loader doesn't have to re-derive it
    /// and so a future non-URL-derived title has a slot.
    var title: String
    /// Disk modification time at the time the note was indexed.
    var fileMtime: Date
    /// Disk byte size at the time the note was indexed.
    var fileByteSize: UInt32
    /// FNV-1a 64-bit hash of the note's UTF-8 source at index time.
    /// Recorded for a future `verify-cache` diagnostic; never consulted
    /// on the cold-start hot path (which uses `(mtime, size)` only).
    var contentHash: UInt64
    /// The cached navigational index for the note.
    var index: DocumentIndex
}

/// Binary codec for the vault cache file. Little-endian throughout,
/// mirroring `CambiumSerialization`'s green-snapshot format conventions:
/// a fixed header, a deduplicated string pool, then a flat record list.
enum VaultCacheFormat {
    static let magic: [UInt8] = Array("LMVCACHE".utf8)
    static let formatVersion: UInt32 = 1
    /// Bump whenever the on-disk shape of `DocumentIndex` /
    /// `DocumentReference` / `DocumentSnippet` / `HeadingAnchor` /
    /// `BlockAnchor` changes. A mismatch rejects the whole cache.
    static let indexSchemaVersion: UInt32 = 1

    private static let referenceKindLink: UInt8 = 0
    private static let referenceKindEmbed: UInt8 = 1

    /// FNV-1a 64-bit hash. Cheap, dependency-free, deterministic —
    /// adequate for the "did this file's bytes change" check the cache
    /// records for diagnostics.
    static func contentHash(_ utf8: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: - Encode

    static func encode(_ snapshot: VaultCacheSnapshot, vaultRootHint: String) -> [UInt8] {
        var pool = StringPoolBuilder()
        var recordWriter = BinaryWriter()

        recordWriter.writeUInt32(UInt32(snapshot.entries.count))
        for entry in snapshot.entries {
            encodeEntry(entry, pool: &pool, into: &recordWriter)
        }

        var writer = BinaryWriter()
        writer.writeBytes(magic)
        writer.writeUInt32(formatVersion)
        writer.writeString(LiminalLanguage.serializationID)
        writer.writeUInt32(LiminalLanguage.serializationVersion)
        writer.writeUInt32(indexSchemaVersion)
        writer.writeString(vaultRootHint)

        writer.writeUInt32(UInt32(pool.strings.count))
        for string in pool.strings {
            writer.writeString(string)
        }

        writer.writeBytes(recordWriter.bytes)
        return writer.bytes
    }

    private static func encodeEntry(
        _ entry: VaultCacheEntry,
        pool: inout StringPoolBuilder,
        into writer: inout BinaryWriter
    ) {
        writer.writeUInt32(pool.intern(entry.relativePath))
        writer.writeUInt32(pool.intern(entry.title))
        writer.writeUInt64(mtimeBits(entry.fileMtime))
        writer.writeUInt32(entry.fileByteSize)
        writer.writeUInt64(entry.contentHash)

        let index = entry.index
        writer.writeUInt32(UInt32(index.blockOffsets.count))
        for offset in index.blockOffsets {
            writer.writeUInt32(offset.rawValue)
        }

        writer.writeUInt32(UInt32(index.headings.count))
        for heading in index.headings {
            writer.writeUInt32(pool.intern(heading.title))
            writer.writeUInt32(heading.sourceOffset.rawValue)
            writer.writeUInt8(UInt8(clamping: heading.level))
        }

        writer.writeUInt32(UInt32(index.blocks.count))
        for block in index.blocks {
            writer.writeUInt32(pool.intern(block.blockID))
            writer.writeUInt32(block.sourceOffset.rawValue)
        }

        writer.writeUInt32(UInt32(index.references.count))
        for reference in index.references {
            encodeReference(reference, pool: &pool, into: &writer)
        }
    }

    private static func encodeReference(
        _ reference: DocumentReference,
        pool: inout StringPoolBuilder,
        into writer: inout BinaryWriter
    ) {
        writer.writeUInt8(reference.kind == .embed ? referenceKindEmbed : referenceKindLink)
        writer.writeUInt32(pool.internOptional(reference.target.notePath))
        writer.writeUInt32(pool.internOptional(reference.target.heading))
        writer.writeUInt32(pool.internOptional(reference.target.blockID))
        writer.writeUInt32(pool.internOptional(reference.target.externalURI))
        writer.writeUInt32(pool.internOptional(reference.alias))

        writer.writeUInt32(reference.sourceRange.start.rawValue)
        writer.writeUInt32(reference.sourceRange.end.rawValue)

        if let targetRange = reference.targetRange {
            writer.writeUInt8(1)
            writer.writeUInt32(targetRange.start.rawValue)
            writer.writeUInt32(targetRange.end.rawValue)
        } else {
            writer.writeUInt8(0)
            writer.writeUInt32(0)
            writer.writeUInt32(0)
        }

        writer.writeUInt32(pool.intern(reference.snippet.text))
        writer.writeUInt32(reference.snippet.referenceOffset)
        writer.writeUInt32(reference.snippet.referenceLength)
    }

    // MARK: - Decode

    static func decode(_ bytes: [UInt8]) throws -> VaultCacheSnapshot {
        var reader = BinaryReader(bytes: bytes)

        let foundMagic = try reader.readBytes(magic.count)
        guard foundMagic == magic else {
            throw VaultCacheError.badMagic
        }
        let foundFormatVersion = try reader.readUInt32()
        guard foundFormatVersion == formatVersion else {
            throw VaultCacheError.unsupportedFormatVersion(foundFormatVersion)
        }
        let foundLanguageID = try reader.readString()
        let foundLanguageVersion = try reader.readUInt32()
        guard foundLanguageID == LiminalLanguage.serializationID,
              foundLanguageVersion == LiminalLanguage.serializationVersion
        else {
            throw VaultCacheError.languageMismatch(
                expectedID: LiminalLanguage.serializationID,
                foundID: foundLanguageID,
                expectedVersion: LiminalLanguage.serializationVersion,
                foundVersion: foundLanguageVersion
            )
        }
        let foundSchemaVersion = try reader.readUInt32()
        guard foundSchemaVersion == indexSchemaVersion else {
            throw VaultCacheError.indexSchemaMismatch(
                expected: indexSchemaVersion,
                found: foundSchemaVersion
            )
        }
        _ = try reader.readString() // vaultRootHint — debug only, not enforced.

        let poolCount = try reader.readUInt32()
        guard let poolCountInt = Int(exactly: poolCount) else {
            throw VaultCacheError.integerOverflow
        }
        var pool: [String] = []
        pool.reserveCapacity(poolCountInt)
        for _ in 0..<poolCountInt {
            pool.append(try reader.readString())
        }

        let recordCount = try reader.readUInt32()
        guard let recordCountInt = Int(exactly: recordCount) else {
            throw VaultCacheError.integerOverflow
        }
        var entries: [VaultCacheEntry] = []
        entries.reserveCapacity(recordCountInt)
        for _ in 0..<recordCountInt {
            entries.append(try decodeEntry(&reader, pool: pool))
        }

        guard reader.remaining == 0 else {
            throw VaultCacheError.trailingBytes(reader.remaining)
        }
        return VaultCacheSnapshot(entries: entries)
    }

    private static func decodeEntry(
        _ reader: inout BinaryReader,
        pool: [String]
    ) throws -> VaultCacheEntry {
        let relativePath = try string(at: reader.readUInt32(), pool: pool)
        let title = try string(at: reader.readUInt32(), pool: pool)
        let mtime = date(fromMtimeBits: try reader.readUInt64())
        let byteSize = try reader.readUInt32()
        let contentHash = try reader.readUInt64()

        let blockOffsetCount = try intCount(reader.readUInt32())
        var blockOffsets: [TextSize] = []
        blockOffsets.reserveCapacity(blockOffsetCount)
        for _ in 0..<blockOffsetCount {
            blockOffsets.append(TextSize(try reader.readUInt32()))
        }

        let headingCount = try intCount(reader.readUInt32())
        var headings: [HeadingAnchor] = []
        headings.reserveCapacity(headingCount)
        for _ in 0..<headingCount {
            let headingTitle = try string(at: reader.readUInt32(), pool: pool)
            let offset = TextSize(try reader.readUInt32())
            let level = Int(try reader.readUInt8())
            headings.append(HeadingAnchor(title: headingTitle, sourceOffset: offset, level: level))
        }

        let blockCount = try intCount(reader.readUInt32())
        var blocks: [BlockAnchor] = []
        blocks.reserveCapacity(blockCount)
        for _ in 0..<blockCount {
            let blockID = try string(at: reader.readUInt32(), pool: pool)
            let offset = TextSize(try reader.readUInt32())
            blocks.append(BlockAnchor(blockID: blockID, sourceOffset: offset))
        }

        let referenceCount = try intCount(reader.readUInt32())
        var references: [DocumentReference] = []
        references.reserveCapacity(referenceCount)
        for _ in 0..<referenceCount {
            references.append(try decodeReference(&reader, pool: pool))
        }

        return VaultCacheEntry(
            relativePath: relativePath,
            title: title,
            fileMtime: mtime,
            fileByteSize: byteSize,
            contentHash: contentHash,
            index: DocumentIndex(
                blockOffsets: blockOffsets,
                headings: headings,
                blocks: blocks,
                references: references
            )
        )
    }

    private static func decodeReference(
        _ reader: inout BinaryReader,
        pool: [String]
    ) throws -> DocumentReference {
        let kindTag = try reader.readUInt8()
        let kind: ReferenceKind
        switch kindTag {
        case referenceKindLink: kind = .link
        case referenceKindEmbed: kind = .embed
        default: throw VaultCacheError.unknownReferenceKind(kindTag)
        }

        let notePath = try optionalString(at: reader.readUInt32(), pool: pool)
        let heading = try optionalString(at: reader.readUInt32(), pool: pool)
        let blockID = try optionalString(at: reader.readUInt32(), pool: pool)
        let externalURI = try optionalString(at: reader.readUInt32(), pool: pool)
        let alias = try optionalString(at: reader.readUInt32(), pool: pool)

        let sourceStart = TextSize(try reader.readUInt32())
        let sourceEnd = TextSize(try reader.readUInt32())
        let sourceRange = TextRange(start: sourceStart, end: sourceEnd)

        let hasTargetRange = try reader.readUInt8() == 1
        let targetStart = TextSize(try reader.readUInt32())
        let targetEnd = TextSize(try reader.readUInt32())
        let targetRange = hasTargetRange
            ? TextRange(start: targetStart, end: targetEnd)
            : nil

        let snippetText = try string(at: reader.readUInt32(), pool: pool)
        let snippetOffset = try reader.readUInt32()
        let snippetLength = try reader.readUInt32()

        return DocumentReference(
            kind: kind,
            target: WikiTarget(
                notePath: notePath,
                heading: heading,
                blockID: blockID,
                externalURI: externalURI
            ),
            alias: alias,
            sourceRange: sourceRange,
            targetRange: targetRange,
            snippet: DocumentSnippet(
                text: snippetText,
                referenceOffset: snippetOffset,
                referenceLength: snippetLength
            )
        )
    }

    // MARK: - Helpers

    /// Store `fileMtime` as the raw bit pattern of its
    /// `timeIntervalSinceReferenceDate` — `Date`'s underlying storage —
    /// so it roundtrips bit-exactly. (Going through `timeIntervalSince1970`
    /// would apply a `±978307200.0` offset whose round-trip is not
    /// exactly invertible in floating point.) A fresh `FileManager` mtime
    /// then compares equal to its cached copy when the file is unchanged,
    /// and `Date.distantPast` roundtrips like any other date with no
    /// special sentinel.
    private static func mtimeBits(_ date: Date) -> UInt64 {
        date.timeIntervalSinceReferenceDate.bitPattern
    }

    private static func date(fromMtimeBits bits: UInt64) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
    }

    private static func string(at id: UInt32, pool: [String]) throws -> String {
        guard let index = Int(exactly: id), pool.indices.contains(index) else {
            throw VaultCacheError.stringPoolIndexOutOfRange(id)
        }
        return pool[index]
    }

    /// String-pool index `0` is the reserved empty-string / nil slot — a
    /// `0` here decodes to `nil`. `WikiTarget` cleanup and alias trimming
    /// guarantee real values are never the empty string, so this is
    /// unambiguous.
    private static func optionalString(at id: UInt32, pool: [String]) throws -> String? {
        guard id != 0 else { return nil }
        let value = try string(at: id, pool: pool)
        return value.isEmpty ? nil : value
    }

    private static func intCount(_ value: UInt32) throws -> Int {
        guard let count = Int(exactly: value) else {
            throw VaultCacheError.integerOverflow
        }
        return count
    }
}

/// Deduplicating string interner used during encode. Index `0` is
/// permanently the empty string, which doubles as the nil sentinel for
/// optional fields (see `VaultCacheFormat.optionalString`).
private struct StringPoolBuilder {
    private(set) var strings: [String] = [""]
    private var ids: [String: UInt32] = ["": 0]

    mutating func intern(_ string: String) -> UInt32 {
        if let id = ids[string] { return id }
        let id = UInt32(strings.count)
        strings.append(string)
        ids[string] = id
        return id
    }

    /// Intern an optional value: `nil` (or an unexpected empty string)
    /// maps to index `0`, the nil sentinel.
    mutating func internOptional(_ string: String?) -> UInt32 {
        guard let string, !string.isEmpty else { return 0 }
        return intern(string)
    }
}

/// Minimal little-endian byte writer — mirrors the (file-private) shape
/// in `CambiumSerialization`'s `GreenSnapshotSerialization.swift`.
private struct BinaryWriter {
    private(set) var bytes: [UInt8] = []

    mutating func writeBytes(_ value: [UInt8]) {
        bytes.append(contentsOf: value)
    }

    mutating func writeUInt8(_ value: UInt8) {
        bytes.append(value)
    }

    mutating func writeUInt32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func writeUInt64(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func writeString(_ value: String) {
        let data = Array(value.utf8)
        writeUInt32(UInt32(data.count))
        bytes.append(contentsOf: data)
    }
}

/// Minimal little-endian byte reader with bounds checking on every read —
/// any truncation throws `VaultCacheError.truncatedInput`.
private struct BinaryReader {
    private let bytes: [UInt8]
    private var offset: Int = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var remaining: Int {
        bytes.count - offset
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard remaining >= count else { throw VaultCacheError.truncatedInput }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func readUInt8() throws -> UInt8 {
        guard remaining >= 1 else { throw VaultCacheError.truncatedInput }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        guard remaining >= 4 else { throw VaultCacheError.truncatedInput }
        let value = UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
        offset += 4
        return value
    }

    mutating func readUInt64() throws -> UInt64 {
        guard remaining >= 8 else { throw VaultCacheError.truncatedInput }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << UInt64(index * 8)
        }
        offset += 8
        return value
    }

    mutating func readString() throws -> String {
        let count = try intCount(readUInt32())
        guard remaining >= count else { throw VaultCacheError.truncatedInput }
        let slice = bytes[offset..<(offset + count)]
        offset += count
        guard let string = String(bytes: slice, encoding: .utf8) else {
            throw VaultCacheError.invalidUTF8
        }
        return string
    }

    private func intCount(_ value: UInt32) throws -> Int {
        guard let count = Int(exactly: value) else {
            throw VaultCacheError.integerOverflow
        }
        return count
    }
}
