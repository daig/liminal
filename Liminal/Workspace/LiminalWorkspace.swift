import CambiumCore
import Foundation

public typealias LiminalSourceRange = CambiumCore.TextRange

/// Hot-tier (in-memory) record for a vault note.
///
/// Holds only the small, derived bits the navigator / link index / backlinks
/// panel need: identity, display name, and the disk-state fingerprint
/// (`fileMtime`, `fileByteSize`) used to drive cold-start cache validation
/// and watcher reparse decisions.
///
/// Source bytes are intentionally not held here. Open documents own their
/// own buffer via `LiminalSourceDocument.session.source`; closed notes are
/// re-read from disk only on demand (e.g., reparse). Pre-computed snippets
/// for backlink display live on each `DocumentReference` rather than being
/// reconstructed from full content at lookup time.
public struct LiminalNoteMetadata: Identifiable, Hashable, Sendable {
    public let id: URL
    public let relativePath: String
    public var title: String
    /// Disk modification time at the last read or successful write-through.
    /// For open documents with unsaved edits this stays pinned to the
    /// on-disk value so the watcher can still detect external changes.
    public var fileMtime: Date
    /// Disk byte size at the last read or successful write-through.
    public var fileByteSize: UInt32
    /// FNV-1a hash of the note's UTF-8 source as last read from (or
    /// written to) disk. Travels alongside `fileMtime` / `fileByteSize`
    /// as the warm-tier cache fingerprint; recorded for a future
    /// `verify-cache` diagnostic but not consulted on the cold-start hot
    /// path, which uses `(mtime, size)` only.
    public var contentHash: UInt64

    public var filename: String { id.lastPathComponent }

    public var relativePathWithoutExtension: String {
        (relativePath as NSString).deletingPathExtension
    }

    public init(
        url: URL,
        relativePath: String,
        fileMtime: Date = .distantPast,
        fileByteSize: UInt32 = 0,
        contentHash: UInt64 = 0
    ) {
        self.id = url
        self.relativePath = relativePath
        self.title = url.deletingPathExtension().lastPathComponent
        self.fileMtime = fileMtime
        self.fileByteSize = fileByteSize
        self.contentHash = contentHash
    }
}

public struct LiminalVault: Identifiable, Hashable, Sendable {
    public let id: URL
    public var name: String
    public var notes: [LiminalNoteMetadata]

    public var url: URL { id }

    public init(url: URL, notes: [LiminalNoteMetadata] = []) {
        self.id = url
        self.name = url.lastPathComponent
        self.notes = notes
    }
}

/// Pre-computed backlink-context slice for one `DocumentReference`.
///
/// `text` is up to ~100 UTF-8 bytes of context around the reference (default
/// ±36 bytes on each side, newlines collapsed to spaces, ASCII whitespace
/// trimmed without crossing the reference boundary). `referenceOffset` /
/// `referenceLength` locate the link span inside `text` so a UI can
/// highlight it without re-finding it in the surrounding text.
///
/// Built once at parse time by `DocumentIndexBuilder` while the source bytes
/// are in hand; persisted in the warm-tier vault cache alongside the
/// `DocumentReference` so the backlinks panel can render closed-note
/// context without reading any source files.
public struct DocumentSnippet: Equatable, Hashable, Sendable {
    public var text: String
    public var referenceOffset: UInt32
    public var referenceLength: UInt32

    public static let empty = DocumentSnippet(text: "", referenceOffset: 0, referenceLength: 0)

    public init(text: String, referenceOffset: UInt32, referenceLength: UInt32) {
        self.text = text
        self.referenceOffset = referenceOffset
        self.referenceLength = referenceLength
    }
}

public struct HeadingAnchor: Equatable, Hashable, Sendable {
    public let title: String
    public let normalizedKey: String
    public let sourceOffset: TextSize
    /// ATX heading depth (1 for `#`, 2 for `##`, etc.). Outline /
    /// navigator UIs indent by this. Clamped to 1...6 to match the
    /// useful CommonMark range; the parser itself accepts longer
    /// runs and the underlying token preserves them, but anything
    /// beyond 6 collapses here for display purposes.
    public let level: Int

    public init(title: String, sourceOffset: TextSize, level: Int = 1) {
        self.title = title
        self.normalizedKey = WikiLinkNormalizer.headingLookupKey(title)
        self.sourceOffset = sourceOffset
        self.level = max(1, min(6, level))
    }
}

public struct BlockAnchor: Equatable, Hashable, Sendable {
    public let blockID: String
    public let normalizedKey: String
    public let sourceOffset: TextSize

    public init(blockID: String, sourceOffset: TextSize) {
        self.blockID = blockID
        self.normalizedKey = WikiLinkNormalizer.blockLookupKey(blockID)
        self.sourceOffset = sourceOffset
    }
}

public struct DocumentReference: Equatable, Hashable, Sendable {
    public let kind: ReferenceKind
    public let target: WikiTarget
    public let alias: String?
    public let sourceRange: LiminalSourceRange
    public let targetRange: LiminalSourceRange?
    /// Backlink-context slice for this reference. Computed at parse time
    /// when the source bytes are available; `.empty` for indexes built
    /// without source (e.g., test fixtures, paths that didn't carry the
    /// source through).
    public let snippet: DocumentSnippet

    public init(
        kind: ReferenceKind,
        target: WikiTarget,
        alias: String? = nil,
        sourceRange: LiminalSourceRange,
        targetRange: LiminalSourceRange? = nil,
        snippet: DocumentSnippet = .empty
    ) {
        self.kind = kind
        self.target = target
        self.alias = alias
        self.sourceRange = sourceRange
        self.targetRange = targetRange
        self.snippet = snippet
    }
}

public struct DocumentIndex: Equatable, Sendable {
    public var blockOffsets: [TextSize]
    public var headings: [HeadingAnchor]
    public var blocks: [BlockAnchor]
    public var references: [DocumentReference]

    public static let empty = DocumentIndex()

    public init(
        blockOffsets: [TextSize] = [],
        headings: [HeadingAnchor] = [],
        blocks: [BlockAnchor] = [],
        references: [DocumentReference] = []
    ) {
        self.blockOffsets = blockOffsets
        self.headings = headings
        self.blocks = blocks
        self.references = references
    }

    public static func build(from parseResult: LiminalParseResult) -> DocumentIndex {
        build(root: parseResult.rootSyntax)
    }

    /// Build an index directly from a root syntax handle. Lets callers
    /// re-index after a structural edit (where `LiminalParseResult` is
    /// nil but `currentTree` advanced) without having to re-parse.
    /// Without `source`, every emitted reference's `snippet` is
    /// `.empty` — backlinks-panel context relies on the source-bearing
    /// overload below.
    public static func build(root: RootSyntax) -> DocumentIndex {
        var builder = DocumentIndexBuilder()
        return builder.build(root: root)
    }

    /// Source-bearing variant: each reference also carries a pre-computed
    /// `DocumentSnippet` of context around its source range. Used by the
    /// open-doc reindex path and the cold-start scan so backlinks display
    /// works without re-reading source bytes. The rope is queried via
    /// `bytes(in:)` for each snippet window — O(log N + window size) per
    /// reference; no full-source materialization.
    public static func build(root: RootSyntax, source: CambiumSource) -> DocumentIndex {
        var builder = DocumentIndexBuilder()
        return builder.build(root: root, source: source)
    }

    public func reference(containing offset: TextSize) -> DocumentReference? {
        innermostReference(in: references, containing: offset) { $0.sourceRange }
    }

    /// The heading whose section contains `offset`. The last heading
    /// whose source offset is at or before `offset` — when the
    /// cursor is on a heading line itself, that same heading is
    /// returned.
    public func heading(enclosing offset: TextSize) -> HeadingAnchor? {
        headings.last { $0.sourceOffset <= offset }
    }

    /// Vim `gh`'s ascend semantics: the parent heading of `heading`,
    /// i.e., the most recent preceding heading at a *shallower*
    /// level. Returns nil for a top-level (level-1) heading with no
    /// preceding heading.
    public func parentHeading(of heading: HeadingAnchor) -> HeadingAnchor? {
        headings.last {
            $0.sourceOffset < heading.sourceOffset && $0.level < heading.level
        }
    }

    /// Vim `[[`: the most recent heading strictly before `offset`.
    /// On a heading line, returns the previous heading; if there is
    /// no preceding heading, returns nil.
    public func heading(before offset: TextSize) -> HeadingAnchor? {
        headings.last { $0.sourceOffset < offset }
    }

    /// Vim `]]`: the first heading strictly after `offset`. Returns
    /// nil past the document's last heading.
    public func heading(after offset: TextSize) -> HeadingAnchor? {
        headings.first { $0.sourceOffset > offset }
    }

    /// Vim `[r`: the most recent reference (any kind) whose source
    /// range starts strictly before `offset`. Walks `references` in
    /// the order the indexer emitted them, which is source order.
    public func reference(before offset: TextSize) -> DocumentReference? {
        references.last { $0.sourceRange.start < offset }
    }

    /// Vim `]r`: the first reference whose source range starts
    /// strictly after `offset`. Returns nil past the last
    /// reference.
    public func reference(after offset: TextSize) -> DocumentReference? {
        references.first { $0.sourceRange.start > offset }
    }

    public func blockOffset(for anchor: LinkNavigationAnchor) -> TextSize? {
        switch anchor {
        case .heading(let heading):
            let key = WikiLinkNormalizer.headingLookupKey(heading)
            return headings.first { $0.normalizedKey == key }?.sourceOffset
        case .block(let blockID):
            let key = WikiLinkNormalizer.blockLookupKey(blockID)
            return blocks.first { $0.normalizedKey == key }?.sourceOffset
        case .sourceOffset(let sourceOffset):
            return blockOffsets.last { $0 <= sourceOffset }
        }
    }
}

private func innermostReference<Reference>(
    in references: [Reference],
    containing offset: TextSize,
    sourceRange: (Reference) -> LiminalSourceRange
) -> Reference? {
    var best: Reference?
    var bestLength: UInt32?

    for reference in references {
        let range = sourceRange(reference)
        guard range.contains(offset) else {
            continue
        }

        let length = range.length.rawValue
        if best == nil || length < (bestLength ?? UInt32.max) {
            best = reference
            bestLength = length
        }
    }

    return best
}

public struct WikiTarget: Equatable, Hashable, Sendable {
    public var notePath: String?
    public var heading: String?
    public var blockID: String?
    /// Phase 4.5: an absolute external URI (`https://...`, `mailto:...`,
    /// `data:...`, etc.). When non-nil, the target represents an external
    /// resource and the vault-related fields are all nil. Activation
    /// routes externals through `.openExternal` rather than vault
    /// resolution; the indexer still emits these so backlinks see them.
    public var externalURI: String?

    public init(
        notePath: String? = nil,
        heading: String? = nil,
        blockID: String? = nil,
        externalURI: String? = nil
    ) {
        self.externalURI = Self.cleanComponent(externalURI)
        if self.externalURI != nil {
            // External targets are mutually exclusive with vault fields.
            self.notePath = nil
            self.heading = nil
            self.blockID = nil
        } else {
            self.notePath = Self.cleanComponent(notePath)
            self.heading = Self.cleanComponent(heading)
            self.blockID = Self.cleanBlockID(blockID)
        }
    }

    public var isExternal: Bool {
        externalURI != nil
    }

    public var isLocalOnly: Bool {
        externalURI == nil && notePath == nil
    }

    public var hasAnchor: Bool {
        heading != nil || blockID != nil
    }

    public var rawTargetString: String {
        if let externalURI {
            return externalURI
        }

        var result = notePath ?? ""

        if let blockID {
            result += "#^\(blockID)"
        } else if let heading {
            result += "#\(heading)"
        }

        return result
    }

    public static func parse(_ raw: String) -> WikiTarget {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if Self.looksLikeAbsoluteURI(trimmed) {
            return WikiTarget(externalURI: trimmed)
        }

        guard let hashIndex = trimmed.firstIndex(of: "#") else {
            return WikiTarget(notePath: trimmed.isEmpty ? nil : trimmed)
        }

        let notePart = String(trimmed[..<hashIndex])
        let anchorPart = String(trimmed[trimmed.index(after: hashIndex)...])

        if anchorPart.hasPrefix("^") {
            return WikiTarget(
                notePath: notePart.isEmpty ? nil : notePart,
                blockID: String(anchorPart.dropFirst())
            )
        }

        return WikiTarget(
            notePath: notePart.isEmpty ? nil : notePart,
            heading: anchorPart
        )
    }

    /// True when `raw` begins with what RFC 3986 calls a scheme followed
    /// by `:`. The scheme prefix must precede any `/` or `#` so vault
    /// paths like `Folder/Note:foo` (which would have a colon embedded
    /// in the path) aren't misclassified.
    private static func looksLikeAbsoluteURI(_ raw: String) -> Bool {
        guard let colonIndex = raw.firstIndex(of: ":") else {
            return false
        }
        let prefix = raw[..<colonIndex]
        guard !prefix.isEmpty,
              prefix.first?.isLetter == true
        else {
            return false
        }
        for character in prefix {
            if character.isLetter || character.isNumber {
                continue
            }
            if character == "+" || character == "." || character == "-" {
                continue
            }
            return false
        }
        return true
    }

    private static func cleanComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanBlockID(_ value: String?) -> String? {
        guard let value = cleanComponent(value) else { return nil }
        let trimmed = value.hasPrefix("^") ? String(value.dropFirst()) : value
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum ReferenceKind: String, Equatable, Hashable, Sendable {
    case link
    case embed
}

public enum LinkNavigationAnchor: Equatable, Hashable, Sendable {
    case heading(String)
    case block(String)
    case sourceOffset(TextSize)
}

public enum LinkDestination: Equatable, Hashable, Sendable {
    case note(URL)
    case heading(URL, heading: String)
    case block(URL, blockID: String)

    public var noteID: URL {
        switch self {
        case .note(let noteID), .heading(let noteID, _), .block(let noteID, _):
            noteID
        }
    }

    public var anchor: LinkNavigationAnchor? {
        switch self {
        case .note:
            nil
        case .heading(_, let heading):
            .heading(heading)
        case .block(_, let blockID):
            .block(blockID)
        }
    }
}

public enum ReferenceResolution: Equatable, Hashable, Sendable {
    case resolved(LinkDestination)
    case noteResolved(URL, requestedAnchor: LinkNavigationAnchor)
    case unresolved
    case ambiguous([URL])
}

public struct ResolvedReference: Identifiable, Equatable, Hashable, Sendable {
    public let sourceNoteID: URL
    public let kind: ReferenceKind
    public let target: WikiTarget
    public let alias: String?
    public let sourceRange: LiminalSourceRange
    public let targetRange: LiminalSourceRange?
    public let snippet: DocumentSnippet
    public let resolution: ReferenceResolution

    /// Plain text of the backlink snippet. Preserved as the existing entry
    /// point for view code that doesn't yet care about the in-snippet
    /// reference offset.
    public var sourceSnippet: String { snippet.text }

    public var id: String {
        [
            sourceNoteID.absoluteString,
            kind.rawValue,
            target.rawTargetString,
            String(sourceRange.start.rawValue),
            String(sourceRange.length.rawValue)
        ].joined(separator: "|")
    }

    public init(
        sourceNoteID: URL,
        kind: ReferenceKind,
        target: WikiTarget,
        alias: String?,
        sourceRange: LiminalSourceRange,
        targetRange: LiminalSourceRange? = nil,
        snippet: DocumentSnippet = .empty,
        resolution: ReferenceResolution
    ) {
        self.sourceNoteID = sourceNoteID
        self.kind = kind
        self.target = target
        self.alias = alias
        self.sourceRange = sourceRange
        self.targetRange = targetRange
        self.snippet = snippet
        self.resolution = resolution
    }
}

public struct NoteNavigationRequest: Equatable, Sendable {
    public let noteID: URL
    public let anchor: LinkNavigationAnchor?
    public let nonce: UUID

    public init(noteID: URL, anchor: LinkNavigationAnchor? = nil, nonce: UUID = UUID()) {
        self.noteID = noteID
        self.anchor = anchor
        self.nonce = nonce
    }
}

public enum WikiLinkNormalizer {
    public static func noteLookupKey(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))

        guard !normalized.isEmpty else { return "" }

        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { component -> String in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.lowercased()
            }

        guard !components.isEmpty else { return "" }

        var lowered = components.joined(separator: "/")
        if lowered.hasSuffix(".md") {
            lowered.removeLast(3)
        }
        return lowered
    }

    public static func headingLookupKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    public static func blockLookupKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

public enum LinkActivationDecision: Equatable, Sendable {
    case open(noteID: URL, anchor: LinkNavigationAnchor?)
    case createNote(relativePath: String)
    case showAmbiguous([URL])
    /// Phase 4.5: target is an absolute external URI; route via the
    /// system default handler (`NSWorkspace.open`, `UIApplication.open`,
    /// etc.). Never auto-creates a vault note.
    case openExternal(URL)
    case noAction
}

public enum LinkActivationPolicy {
    public static func decision(
        for target: WikiTarget,
        resolution: ReferenceResolution
    ) -> LinkActivationDecision {
        // External-URI targets short-circuit vault resolution entirely —
        // we never want an `https://...` to flow through `.createNote`.
        if let externalURI = target.externalURI {
            if let url = URL(string: externalURI) {
                return .openExternal(url)
            }
            return .noAction
        }
        switch resolution {
        case .resolved(let destination):
            return .open(noteID: destination.noteID, anchor: destination.anchor)
        case .noteResolved(let noteID, _):
            return .open(noteID: noteID, anchor: nil)
        case .unresolved:
            return target.notePath.map { .createNote(relativePath: $0) } ?? .noAction
        case .ambiguous(let candidates):
            return .showAmbiguous(candidates)
        }
    }

    public static func decision(for reference: ResolvedReference) -> LinkActivationDecision {
        decision(for: reference.target, resolution: reference.resolution)
    }

    public static func decision(forBacklink reference: ResolvedReference) -> LinkActivationDecision {
        .open(
            noteID: reference.sourceNoteID,
            anchor: .sourceOffset(reference.sourceRange.start)
        )
    }
}

public struct VaultLinkIndex: Equatable, Sendable {
    fileprivate var notesByID: [URL: LiminalNoteMetadata]
    fileprivate var documentIndexesByNote: [URL: DocumentIndex]
    fileprivate var outgoingByNote: [URL: [ResolvedReference]]
    fileprivate var backlinksByNote: [URL: [ResolvedReference]]
    fileprivate var titleLookup: [String: [URL]]
    fileprivate var pathLookup: [String: URL]
    fileprivate var headingLookupByNote: [URL: [String: HeadingAnchor]]
    fileprivate var blockLookupByNote: [URL: [String: BlockAnchor]]
    /// Inverse index: for each normalized path key, the URLs of notes whose
    /// outgoing references resolve (or no-anchor-resolve) into that target.
    /// Powers cheap re-resolution when a doc's anchors or path identity
    /// change without rewalking every other note's outgoing list.
    fileprivate var sourcesByTargetPathKey: [String: Set<URL>]

    public static let empty = VaultLinkIndex(
        notesByID: [:],
        documentIndexesByNote: [:],
        outgoingByNote: [:],
        backlinksByNote: [:],
        titleLookup: [:],
        pathLookup: [:],
        headingLookupByNote: [:],
        blockLookupByNote: [:],
        sourcesByTargetPathKey: [:]
    )

    public static func build(
        notes: [LiminalNoteMetadata],
        documentIndexes: [URL: DocumentIndex] = [:]
    ) -> VaultLinkIndex {
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let indexes = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, documentIndexes[note.id] ?? .empty)
        })
        let titleLookup = Dictionary(grouping: notes, by: {
            WikiLinkNormalizer.noteLookupKey($0.title)
        }).mapValues { group in
            group.map(\.id).sorted { $0.absoluteString < $1.absoluteString }
        }
        let pathLookup = Dictionary(uniqueKeysWithValues: notes.map {
            (WikiLinkNormalizer.noteLookupKey($0.relativePathWithoutExtension), $0.id)
        })
        let headingLookupByNote = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, firstValueMap(indexes[note.id]?.headings ?? []) { $0.normalizedKey })
        })
        let blockLookupByNote = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, firstValueMap(indexes[note.id]?.blocks ?? []) { $0.normalizedKey })
        })

        let resolver = VaultLinkIndex(
            notesByID: notesByID,
            documentIndexesByNote: indexes,
            outgoingByNote: [:],
            backlinksByNote: [:],
            titleLookup: titleLookup,
            pathLookup: pathLookup,
            headingLookupByNote: headingLookupByNote,
            blockLookupByNote: blockLookupByNote,
            sourcesByTargetPathKey: [:]
        )

        var outgoingByNote: [URL: [ResolvedReference]] = [:]
        var backlinksByNote: [URL: [ResolvedReference]] = [:]
        var sourcesByTargetPathKey: [String: Set<URL>] = [:]

        for note in notes {
            let references = (indexes[note.id]?.references ?? []).map { reference in
                ResolvedReference(
                    sourceNoteID: note.id,
                    kind: reference.kind,
                    target: reference.target,
                    alias: reference.alias,
                    sourceRange: reference.sourceRange,
                    targetRange: reference.targetRange,
                    snippet: reference.snippet,
                    resolution: resolver.resolve(target: reference.target, from: note.id)
                )
            }

            outgoingByNote[note.id] = references

            for reference in references {
                if let recipientNoteID = recipientNoteID(for: reference.resolution) {
                    backlinksByNote[recipientNoteID, default: []].append(reference)
                }
                if let key = targetPathKey(for: reference.target) {
                    sourcesByTargetPathKey[key, default: []].insert(note.id)
                }
            }
        }

        // Canonicalize backlink order so the result of `build` is
        // structurally identical to the result of any sequence of
        // `applying(...)` calls reaching the same state — see
        // `backlinkOrder`.
        for (key, refs) in backlinksByNote {
            backlinksByNote[key] = refs.sorted(by: backlinkOrder)
        }

        return VaultLinkIndex(
            notesByID: notesByID,
            documentIndexesByNote: indexes,
            outgoingByNote: outgoingByNote,
            backlinksByNote: backlinksByNote,
            titleLookup: titleLookup,
            pathLookup: pathLookup,
            headingLookupByNote: headingLookupByNote,
            blockLookupByNote: blockLookupByNote,
            sourcesByTargetPathKey: sourcesByTargetPathKey
        )
    }

    /// Stable backlink ordering: by source note URL, then by source-range
    /// start. Both `build` and the incremental `applying(...)` paths sort
    /// `backlinksByNote` lists this way so the two are `Equatable`-identical
    /// regardless of how a given index state was reached.
    fileprivate static func backlinkOrder(_ a: ResolvedReference, _ b: ResolvedReference) -> Bool {
        let lhs = a.sourceNoteID.absoluteString
        let rhs = b.sourceNoteID.absoluteString
        if lhs != rhs { return lhs < rhs }
        return a.sourceRange.start.rawValue < b.sourceRange.start.rawValue
    }

    public func outgoing(for noteID: URL?) -> [ResolvedReference] {
        guard let noteID else { return [] }
        return outgoingByNote[noteID] ?? []
    }

    public func backlinks(for noteID: URL?) -> [ResolvedReference] {
        guard let noteID else { return [] }
        return backlinksByNote[noteID] ?? []
    }

    public func documentIndex(for noteID: URL?) -> DocumentIndex {
        guard let noteID else { return .empty }
        return documentIndexesByNote[noteID] ?? .empty
    }

    public func note(for noteID: URL?) -> LiminalNoteMetadata? {
        guard let noteID else { return nil }
        return notesByID[noteID]
    }

    public func reference(in noteID: URL?, at offset: TextSize) -> ResolvedReference? {
        guard let noteID else { return nil }
        return innermostReference(in: outgoingByNote[noteID] ?? [], containing: offset) { $0.sourceRange }
    }

    public func resolve(target: WikiTarget, from sourceNoteID: URL) -> ReferenceResolution {
        // External targets make no vault claim — `LinkActivationPolicy`
        // routes them via `.openExternal` regardless of the resolution
        // returned here.
        if target.isExternal {
            return .unresolved
        }

        let resolvedNoteID: URL

        if let notePath = target.notePath {
            let noteKey = WikiLinkNormalizer.noteLookupKey(notePath)
            if notePath.contains("/") {
                guard let exactMatch = pathLookup[noteKey] else {
                    return .unresolved
                }
                resolvedNoteID = exactMatch
            } else {
                let matches = titleLookup[noteKey] ?? []
                if matches.count > 1 {
                    return .ambiguous(matches.sorted { $0.absoluteString < $1.absoluteString })
                }
                guard let onlyMatch = matches.first else {
                    return .unresolved
                }
                resolvedNoteID = onlyMatch
            }
        } else {
            resolvedNoteID = sourceNoteID
        }

        if let blockID = target.blockID {
            let key = WikiLinkNormalizer.blockLookupKey(blockID)
            if let match = blockLookupByNote[resolvedNoteID]?[key] {
                return .resolved(.block(resolvedNoteID, blockID: match.blockID))
            }
            return .noteResolved(resolvedNoteID, requestedAnchor: .block(blockID))
        }

        if let heading = target.heading {
            let key = WikiLinkNormalizer.headingLookupKey(heading)
            if let match = headingLookupByNote[resolvedNoteID]?[key] {
                return .resolved(.heading(resolvedNoteID, heading: match.title))
            }
            return .noteResolved(resolvedNoteID, requestedAnchor: .heading(heading))
        }

        return .resolved(.note(resolvedNoteID))
    }

    private static func recipientNoteID(for resolution: ReferenceResolution) -> URL? {
        switch resolution {
        case .resolved(let destination):
            destination.noteID
        case .noteResolved(let noteID, _):
            noteID
        case .unresolved, .ambiguous:
            nil
        }
    }

    /// Normalized lookup key for a reference's target, or `nil` when the
    /// target makes no vault-path claim (external URI; pure-anchor target
    /// like `[[#Heading]]`). Used to maintain the inverse
    /// `sourcesByTargetPathKey` index so that anchor / path changes can
    /// re-resolve only the affected source notes.
    fileprivate static func targetPathKey(for target: WikiTarget) -> String? {
        guard !target.isExternal, let notePath = target.notePath else {
            return nil
        }
        return WikiLinkNormalizer.noteLookupKey(notePath)
    }

    // MARK: - Incremental updates

    /// Re-fold the index for a single note's add-or-update.
    ///
    /// Covers both "new note tracked" and "open document re-indexed after
    /// an edit". Cost is bounded by the references in `index` plus the
    /// references *targeting* this note (found via `sourcesByTargetPathKey`)
    /// — not by vault size. The result is `Equatable`-identical to
    /// `VaultLinkIndex.build(...)` over the same final note/index set.
    public func applying(
        documentChange url: URL,
        metadata: LiminalNoteMetadata,
        index: DocumentIndex
    ) -> VaultLinkIndex {
        var copy = self
        copy.applyDocumentChange(url: url, metadata: metadata, index: index)
        return copy
    }

    /// Re-fold the index for a note removal (file deleted, or document
    /// closed with no backing file). Drops the note's own rows and
    /// re-resolves every reference that targeted it.
    public func applying(removalOf url: URL) -> VaultLinkIndex {
        var copy = self
        copy.applyRemoval(of: url)
        return copy
    }

    private mutating func applyDocumentChange(
        url: URL,
        metadata: LiminalNoteMetadata,
        index newIndex: DocumentIndex
    ) {
        let oldMetadata = notesByID[url]
        let oldIndex = documentIndexesByNote[url]
        let isNew = oldMetadata == nil

        let titleChanged = oldMetadata?.title != metadata.title
        let pathChanged = oldMetadata?.relativePathWithoutExtension
            != metadata.relativePathWithoutExtension
        let anchorsChanged = oldIndex?.headings != newIndex.headings
            || oldIndex?.blocks != newIndex.blocks

        // 1. Per-note rows.
        notesByID[url] = metadata
        documentIndexesByNote[url] = newIndex
        headingLookupByNote[url] = Self.firstValueMap(newIndex.headings) { $0.normalizedKey }
        blockLookupByNote[url] = Self.firstValueMap(newIndex.blocks) { $0.normalizedKey }

        // 2. titleLookup — drop the stale title entry, add the current one.
        if let oldMetadata, titleChanged {
            removeFromTitleLookup(url: url, title: oldMetadata.title)
        }
        if isNew || titleChanged {
            let key = WikiLinkNormalizer.noteLookupKey(metadata.title)
            var urls = titleLookup[key] ?? []
            if !urls.contains(url) {
                urls.append(url)
                urls.sort { $0.absoluteString < $1.absoluteString }
                titleLookup[key] = urls
            }
        }

        // 3. pathLookup — single-valued; drop the stale key, set the new one.
        if let oldMetadata, pathChanged {
            let oldKey = WikiLinkNormalizer.noteLookupKey(oldMetadata.relativePathWithoutExtension)
            if pathLookup[oldKey] == url { pathLookup[oldKey] = nil }
        }
        pathLookup[WikiLinkNormalizer.noteLookupKey(metadata.relativePathWithoutExtension)] = url

        // 4. Detach this note's previous outgoing references from the
        //    backlink and inverse-target indexes.
        detachOutgoing(of: url)

        // 5. Re-resolve and attach this note's new outgoing references.
        //    Steps 1-3 already updated this note's own identity rows, so
        //    `resolve` sees the note's current title / path / anchors —
        //    self-references resolve correctly.
        let resolved = newIndex.references.map { reference in
            ResolvedReference(
                sourceNoteID: url,
                kind: reference.kind,
                target: reference.target,
                alias: reference.alias,
                sourceRange: reference.sourceRange,
                targetRange: reference.targetRange,
                snippet: reference.snippet,
                resolution: resolve(target: reference.target, from: url)
            )
        }
        attachOutgoing(resolved, of: url)

        // 6. This note's identity (title / path) or anchor set changed —
        //    or it's brand new — so every *other* note whose references
        //    target this note may now resolve differently. Find them via
        //    the inverse index and re-resolve just those.
        if titleChanged || pathChanged || anchorsChanged || isNew {
            var affectedKeys: Set<String> = [
                WikiLinkNormalizer.noteLookupKey(metadata.title),
                WikiLinkNormalizer.noteLookupKey(metadata.relativePathWithoutExtension)
            ]
            if let oldMetadata {
                affectedKeys.insert(WikiLinkNormalizer.noteLookupKey(oldMetadata.title))
                affectedKeys.insert(
                    WikiLinkNormalizer.noteLookupKey(oldMetadata.relativePathWithoutExtension)
                )
            }
            var sources: Set<URL> = []
            for key in affectedKeys {
                if let bucket = sourcesByTargetPathKey[key] { sources.formUnion(bucket) }
            }
            sources.remove(url) // already handled in step 5
            for source in sources {
                reresolveOutgoing(of: source)
            }
        }
    }

    private mutating func applyRemoval(of url: URL) {
        guard let oldMetadata = notesByID.removeValue(forKey: url) else { return }
        documentIndexesByNote[url] = nil
        headingLookupByNote[url] = nil
        blockLookupByNote[url] = nil
        removeFromTitleLookup(url: url, title: oldMetadata.title)
        let pathKey = WikiLinkNormalizer.noteLookupKey(oldMetadata.relativePathWithoutExtension)
        if pathLookup[pathKey] == url { pathLookup[pathKey] = nil }

        // Drop this note's own outgoing references entirely.
        detachOutgoing(of: url)
        outgoingByNote[url] = nil

        // Anything that resolved (or ambiguously pointed) *into* this note
        // must be re-resolved. Backlinks cover resolved/noteResolved
        // sources; the inverse index additionally covers `.ambiguous`
        // sources that removing this note may now disambiguate.
        var sources: Set<URL> = Set((backlinksByNote[url] ?? []).map(\.sourceNoteID))
        for key in [WikiLinkNormalizer.noteLookupKey(oldMetadata.title), pathKey] {
            if let bucket = sourcesByTargetPathKey[key] { sources.formUnion(bucket) }
        }
        backlinksByNote[url] = nil
        sources.remove(url)
        for source in sources {
            reresolveOutgoing(of: source)
        }
    }

    /// Recompute every outgoing reference for `url` against the current
    /// index state, patching `backlinksByNote` for any that changed
    /// recipient. `outgoingByNote[url]` is rewritten with refreshed
    /// resolutions; `sourcesByTargetPathKey` is left intact (the targets
    /// themselves didn't change — only their resolution may have).
    private mutating func reresolveOutgoing(of url: URL) {
        guard let current = outgoingByNote[url] else { return }
        var updated: [ResolvedReference] = []
        updated.reserveCapacity(current.count)
        for old in current {
            let new = ResolvedReference(
                sourceNoteID: old.sourceNoteID,
                kind: old.kind,
                target: old.target,
                alias: old.alias,
                sourceRange: old.sourceRange,
                targetRange: old.targetRange,
                snippet: old.snippet,
                resolution: resolve(target: old.target, from: url)
            )
            updated.append(new)

            let oldRecipient = Self.recipientNoteID(for: old.resolution)
            let newRecipient = Self.recipientNoteID(for: new.resolution)
            if oldRecipient == newRecipient {
                // Same recipient, but the resolved value may still differ
                // (e.g. resolved ↔ noteResolved). Replace in place.
                if let recipient = newRecipient {
                    replaceBacklink(
                        in: recipient,
                        from: url,
                        sourceRange: old.sourceRange,
                        with: new
                    )
                }
            } else {
                if let oldRecipient {
                    removeBacklink(in: oldRecipient, from: url, sourceRange: old.sourceRange)
                }
                if let newRecipient {
                    insertBacklink(in: newRecipient, ref: new)
                }
            }
        }
        outgoingByNote[url] = updated
    }

    // MARK: Incremental-update helpers

    /// Remove `url`'s outgoing references from the backlink and inverse-
    /// target indexes, and clear its `outgoingByNote` row.
    private mutating func detachOutgoing(of url: URL) {
        for ref in outgoingByNote[url] ?? [] {
            if let recipient = Self.recipientNoteID(for: ref.resolution) {
                removeBacklink(in: recipient, from: url, sourceRange: ref.sourceRange)
            }
        }
        for (key, bucket) in sourcesByTargetPathKey where bucket.contains(url) {
            var next = bucket
            next.remove(url)
            sourcesByTargetPathKey[key] = next.isEmpty ? nil : next
        }
        outgoingByNote[url] = nil
    }

    /// Install `resolved` as `url`'s outgoing references, registering each
    /// into the backlink and inverse-target indexes.
    private mutating func attachOutgoing(_ resolved: [ResolvedReference], of url: URL) {
        outgoingByNote[url] = resolved
        for ref in resolved {
            if let recipient = Self.recipientNoteID(for: ref.resolution) {
                insertBacklink(in: recipient, ref: ref)
            }
            if let key = Self.targetPathKey(for: ref.target) {
                sourcesByTargetPathKey[key, default: []].insert(url)
            }
        }
    }

    private mutating func insertBacklink(in recipient: URL, ref: ResolvedReference) {
        var list = backlinksByNote[recipient] ?? []
        let insertAt = list.firstIndex { Self.backlinkOrder(ref, $0) } ?? list.endIndex
        list.insert(ref, at: insertAt)
        backlinksByNote[recipient] = list
    }

    private mutating func removeBacklink(
        in recipient: URL,
        from sourceURL: URL,
        sourceRange: LiminalSourceRange
    ) {
        guard var list = backlinksByNote[recipient] else { return }
        if let idx = list.firstIndex(where: {
            $0.sourceNoteID == sourceURL && $0.sourceRange == sourceRange
        }) {
            list.remove(at: idx)
        }
        backlinksByNote[recipient] = list.isEmpty ? nil : list
    }

    private mutating func replaceBacklink(
        in recipient: URL,
        from sourceURL: URL,
        sourceRange: LiminalSourceRange,
        with ref: ResolvedReference
    ) {
        guard var list = backlinksByNote[recipient] else {
            insertBacklink(in: recipient, ref: ref)
            return
        }
        if let idx = list.firstIndex(where: {
            $0.sourceNoteID == sourceURL && $0.sourceRange == sourceRange
        }) {
            // Source URL + source range are stable across a re-resolve, so
            // the sort position is unchanged — replace in place.
            list[idx] = ref
            backlinksByNote[recipient] = list
        } else {
            insertBacklink(in: recipient, ref: ref)
        }
    }

    private mutating func removeFromTitleLookup(url: URL, title: String) {
        let key = WikiLinkNormalizer.noteLookupKey(title)
        guard var urls = titleLookup[key] else { return }
        urls.removeAll { $0 == url }
        titleLookup[key] = urls.isEmpty ? nil : urls
    }

    private static func firstValueMap<Value>(
        _ values: [Value],
        key: (Value) -> String
    ) -> [String: Value] {
        var result: [String: Value] = [:]
        for value in values {
            let resolvedKey = key(value)
            if result[resolvedKey] == nil {
                result[resolvedKey] = value
            }
        }
        return result
    }
}
