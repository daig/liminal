import CambiumCore
import Foundation

public typealias LiminalSourceRange = CambiumCore.TextRange

public struct LiminalNote: Identifiable, Hashable, Sendable {
    public let id: URL
    public let relativePath: String
    public var title: String
    public var content: String
    public var lastModified: Date

    public var filename: String { id.lastPathComponent }

    public var relativePathWithoutExtension: String {
        (relativePath as NSString).deletingPathExtension
    }

    public init(
        url: URL,
        relativePath: String,
        content: String = "",
        lastModified: Date = .now
    ) {
        self.id = url
        self.relativePath = relativePath
        self.title = url.deletingPathExtension().lastPathComponent
        self.content = content
        self.lastModified = lastModified
    }
}

public struct LiminalVault: Identifiable, Hashable, Sendable {
    public let id: URL
    public var name: String
    public var notes: [LiminalNote]

    public var url: URL { id }

    public init(url: URL, notes: [LiminalNote] = []) {
        self.id = url
        self.name = url.lastPathComponent
        self.notes = notes
    }
}

public struct HeadingAnchor: Equatable, Hashable, Sendable {
    public let title: String
    public let normalizedKey: String
    public let sourceOffset: TextSize

    public init(title: String, sourceOffset: TextSize) {
        self.title = title
        self.normalizedKey = WikiLinkNormalizer.headingLookupKey(title)
        self.sourceOffset = sourceOffset
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

    public init(
        kind: ReferenceKind,
        target: WikiTarget,
        alias: String? = nil,
        sourceRange: LiminalSourceRange
    ) {
        self.kind = kind
        self.target = target
        self.alias = alias
        self.sourceRange = sourceRange
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
        var builder = DocumentIndexBuilder()
        return builder.build(document: LiminalLowerer().lower(parseResult))
    }

    public func reference(containing offset: TextSize) -> DocumentReference? {
        references.first { $0.sourceRange.contains(offset) }
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

private struct DocumentIndexBuilder {
    private var blockOffsets: [TextSize] = []
    private var headings: [HeadingAnchor] = []
    private var blocks: [BlockAnchor] = []
    private var references: [DocumentReference] = []

    mutating func build(document: LiminalDocument) -> DocumentIndex {
        for item in document.items {
            switch item {
            case .block(.node(let node)), .value(let node):
                append(node)
            }
        }

        return DocumentIndex(
            blockOffsets: blockOffsets,
            headings: headings,
            blocks: blocks,
            references: references
        )
    }

    private mutating func append(_ node: LiminalNode) {
        guard let range = node.source?.range else {
            return
        }

        blockOffsets.append(range.start)

        switch node.type.rawValue {
        case "Heading":
            let title = plainText(node.content)
            if !WikiLinkNormalizer.headingLookupKey(title).isEmpty {
                headings.append(HeadingAnchor(title: title, sourceOffset: range.start))
            }
            appendReferences(in: node.content)

        case "Paragraph":
            appendReferences(in: node.content)

        case "WikiEmbedBlock":
            appendWikiEmbedReference(node, kind: .embed)

        default:
            appendReferences(in: node)
        }
    }

    private mutating func appendReferences(in content: LiminalContent?) {
        switch content {
        case .inline(let inlines):
            appendReferences(in: inlines)
        case .blocks(let blocks):
            for block in blocks {
                if case .node(let node) = block {
                    appendReferences(in: node)
                }
            }
        case nil:
            break
        }
    }

    private mutating func appendReferences(in inlines: [LiminalInline]) {
        for inline in inlines {
            switch inline {
            case .text, .interpolation:
                break
            case .embed:
                // Source-backed inline embeds lower as nodes with SurfaceForm ranges.
                // Plain LiminalEmbed values are semantic/runtime values and are not indexable here.
                break
            case .node(let node):
                appendReferences(in: node)
            }
        }
    }

    private mutating func appendReferences(in node: LiminalNode) {
        switch node.type.rawValue {
        case "WikiLink":
            appendWikiReference(node, kind: .link)
        case "WikiEmbedInline", "WikiEmbedBlock":
            appendWikiEmbedReference(node, kind: .embed)
        case "Link":
            appendReferences(in: node.content)
        case "Image":
            if let alt = fieldValue(named: "alt", in: node),
               case .inlineLiteral(let inlines) = alt
            {
                appendReferences(in: inlines)
            }
        default:
            appendReferences(in: node.content)
            appendReferences(in: node.fields)
        }
    }

    private mutating func appendReferences(in fields: [LiminalField]) {
        for field in fields {
            appendReferences(in: field.value)
        }
    }

    private mutating func appendReferences(in value: LiminalValue) {
        switch value {
        case .scalar, .reference, .embed:
            // .embed loses its source range during lowering today; slice 3
            // unifies EmbedValue with the node-shaped embed surfaces.
            break
        case .list(let values):
            for nested in values {
                appendReferences(in: nested)
            }
        case .record(let fields):
            appendReferences(in: fields)
        case .node(let node):
            appendReferences(in: node)
        case .inlineLiteral(let inlines):
            appendReferences(in: inlines)
        case .blockLiteral(let blocks):
            for block in blocks {
                if case .node(let node) = block {
                    appendReferences(in: node)
                }
            }
        }
    }

    private mutating func appendWikiReference(_ node: LiminalNode, kind: ReferenceKind) {
        guard let target = fieldString(named: "target", in: node),
              let range = node.source?.range
        else {
            return
        }

        let alias: String?
        if case .inline(let inlines) = node.content {
            alias = plainText(inlines)
        } else {
            alias = nil
        }

        references.append(DocumentReference(
            kind: kind,
            target: WikiTarget.parse(target),
            alias: alias,
            sourceRange: range
        ))
    }

    private mutating func appendWikiEmbedReference(_ node: LiminalNode, kind: ReferenceKind) {
        guard let target = fieldString(named: "target", in: node),
              let range = node.source?.range
        else {
            return
        }

        references.append(DocumentReference(
            kind: kind,
            target: WikiTarget.parse(target),
            alias: fieldString(named: "payload", in: node),
            sourceRange: range
        ))
    }

    private func plainText(_ content: LiminalContent?) -> String {
        guard case .inline(let inlines) = content else {
            return ""
        }
        return plainText(inlines)
    }

    private func plainText(_ inlines: [LiminalInline]) -> String {
        inlines.map(plainText).joined()
    }

    private func plainText(_ inline: LiminalInline) -> String {
        switch inline {
        case .text(let text):
            text
        case .interpolation(let expression):
            expression.rawValue
        case .embed(let embed):
            embed.fallback.isEmpty ? embed.target : plainText(embed.fallback)
        case .node(let node):
            plainText(node)
        }
    }

    private func plainText(_ node: LiminalNode) -> String {
        switch node.type.rawValue {
        case "SoftBreak":
            return " "
        case "HardBreak":
            return "\n"
        case "CodeSpan":
            return fieldString(named: "text", in: node) ?? ""
        case "WikiLink":
            if case .inline(let inlines) = node.content {
                return plainText(inlines)
            }
            return fieldString(named: "target", in: node) ?? ""
        case "WikiEmbedInline":
            return fieldString(named: "payload", in: node)
                ?? fieldString(named: "target", in: node)
                ?? ""
        case "Image":
            if let alt = fieldValue(named: "alt", in: node),
               case .inlineLiteral(let inlines) = alt
            {
                return plainText(inlines)
            }
            return ""
        default:
            return plainText(node.content)
        }
    }

    private func fieldString(named name: FieldName, in node: LiminalNode) -> String? {
        guard let value = fieldValue(named: name, in: node) else {
            return nil
        }

        switch value {
        case .scalar(.string(let value)),
             .scalar(.integer(let value)),
             .scalar(.number(let value)),
             .scalar(.bare(let value)):
            return value
        case .scalar(.boolean(let value)):
            return String(value)
        case .scalar(.null):
            return nil
        default:
            return nil
        }
    }

    private func fieldValue(named name: FieldName, in node: LiminalNode) -> LiminalValue? {
        node.fields.first { $0.name == name }?.value
    }
}

public struct WikiTarget: Equatable, Hashable, Sendable {
    public var notePath: String?
    public var heading: String?
    public var blockID: String?

    public init(notePath: String? = nil, heading: String? = nil, blockID: String? = nil) {
        self.notePath = Self.cleanComponent(notePath)
        self.heading = Self.cleanComponent(heading)
        self.blockID = Self.cleanBlockID(blockID)
    }

    public var isLocalOnly: Bool {
        notePath == nil
    }

    public var hasAnchor: Bool {
        heading != nil || blockID != nil
    }

    public var rawTargetString: String {
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
    public let sourceSnippet: String
    public let resolution: ReferenceResolution

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
        sourceSnippet: String,
        resolution: ReferenceResolution
    ) {
        self.sourceNoteID = sourceNoteID
        self.kind = kind
        self.target = target
        self.alias = alias
        self.sourceRange = sourceRange
        self.sourceSnippet = sourceSnippet
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
    case noAction
}

public enum LinkActivationPolicy {
    public static func decision(
        for target: WikiTarget,
        resolution: ReferenceResolution
    ) -> LinkActivationDecision {
        switch resolution {
        case .resolved(let destination):
            .open(noteID: destination.noteID, anchor: destination.anchor)
        case .noteResolved(let noteID, _):
            .open(noteID: noteID, anchor: nil)
        case .unresolved:
            target.notePath.map { .createNote(relativePath: $0) } ?? .noAction
        case .ambiguous(let candidates):
            .showAmbiguous(candidates)
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
    private let notesByID: [URL: LiminalNote]
    private let documentIndexesByNote: [URL: DocumentIndex]
    private let outgoingByNote: [URL: [ResolvedReference]]
    private let backlinksByNote: [URL: [ResolvedReference]]
    private let titleLookup: [String: [URL]]
    private let pathLookup: [String: URL]
    private let headingLookupByNote: [URL: [String: HeadingAnchor]]
    private let blockLookupByNote: [URL: [String: BlockAnchor]]

    public static let empty = VaultLinkIndex(
        notesByID: [:],
        documentIndexesByNote: [:],
        outgoingByNote: [:],
        backlinksByNote: [:],
        titleLookup: [:],
        pathLookup: [:],
        headingLookupByNote: [:],
        blockLookupByNote: [:]
    )

    public static func build(
        notes: [LiminalNote],
        documentIndexes: [URL: DocumentIndex] = [:]
    ) -> VaultLinkIndex {
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let indexes = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, documentIndexes[note.id] ?? .empty)
        })
        let titleLookup = Dictionary(grouping: notes, by: {
            WikiLinkNormalizer.noteLookupKey($0.title)
        }).mapValues { $0.map(\.id) }
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
            blockLookupByNote: blockLookupByNote
        )

        var outgoingByNote: [URL: [ResolvedReference]] = [:]
        var backlinksByNote: [URL: [ResolvedReference]] = [:]

        for note in notes {
            let references = (indexes[note.id]?.references ?? []).map { reference in
                ResolvedReference(
                    sourceNoteID: note.id,
                    kind: reference.kind,
                    target: reference.target,
                    alias: reference.alias,
                    sourceRange: reference.sourceRange,
                    sourceSnippet: snippet(in: note.content, around: reference.sourceRange),
                    resolution: resolver.resolve(target: reference.target, from: note.id)
                )
            }

            outgoingByNote[note.id] = references

            for reference in references {
                guard let recipientNoteID = recipientNoteID(for: reference.resolution) else {
                    continue
                }
                backlinksByNote[recipientNoteID, default: []].append(reference)
            }
        }

        return VaultLinkIndex(
            notesByID: notesByID,
            documentIndexesByNote: indexes,
            outgoingByNote: outgoingByNote,
            backlinksByNote: backlinksByNote,
            titleLookup: titleLookup,
            pathLookup: pathLookup,
            headingLookupByNote: headingLookupByNote,
            blockLookupByNote: blockLookupByNote
        )
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

    public func note(for noteID: URL?) -> LiminalNote? {
        guard let noteID else { return nil }
        return notesByID[noteID]
    }

    public func reference(in noteID: URL?, at offset: TextSize) -> ResolvedReference? {
        guard let noteID else { return nil }
        return outgoingByNote[noteID]?.first { $0.sourceRange.contains(offset) }
    }

    public func resolve(target: WikiTarget, from sourceNoteID: URL) -> ReferenceResolution {
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

    private static func snippet(in content: String, around range: LiminalSourceRange) -> String {
        let text = content as NSString
        guard text.length > 0 else { return "" }

        let location = Int(range.start.rawValue)
        let upperBound = Int(range.end.rawValue)
        let lowerBound = max(0, location - 36)
        let snippetUpperBound = min(text.length, upperBound + 36)
        let snippetRange = NSRange(location: lowerBound, length: snippetUpperBound - lowerBound)
        return text.substring(with: snippetRange)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
