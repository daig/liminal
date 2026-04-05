import Foundation

struct VaultLinkIndex: Equatable, Sendable {
    private let notesByID: [URL: Note]
    private let documentIndexesByNote: [URL: DocumentIndex]
    private let outgoingByNote: [URL: [ResolvedReference]]
    private let backlinksByNote: [URL: [ResolvedReference]]
    private let titleLookup: [String: [URL]]
    private let pathLookup: [String: URL]
    private let headingLookupByNote: [URL: [String: HeadingAnchor]]
    private let blockLookupByNote: [URL: [String: BlockAnchor]]

    static let empty = VaultLinkIndex(
        notesByID: [:],
        documentIndexesByNote: [:],
        outgoingByNote: [:],
        backlinksByNote: [:],
        titleLookup: [:],
        pathLookup: [:],
        headingLookupByNote: [:],
        blockLookupByNote: [:]
    )

    static func build(notes: [Note]) -> VaultLinkIndex {
        struct IndexedNote {
            let note: Note
            let documentIndex: DocumentIndex
        }

        let indexedNotes = notes.map { note in
            IndexedNote(
                note: note,
                documentIndex: DocumentIndex.build(
                    from: Document(blocks: BlockParser.parse(note.content))
                )
            )
        }

        let notesByID = Dictionary(
            uniqueKeysWithValues: indexedNotes.map { ($0.note.id, $0.note) }
        )
        let documentIndexesByNote = Dictionary(
            uniqueKeysWithValues: indexedNotes.map { ($0.note.id, $0.documentIndex) }
        )
        let titleLookup = Dictionary(grouping: indexedNotes, by: {
            WikiLinkNormalizer.noteLookupKey($0.note.title)
        }).mapValues { $0.map(\.note.id) }
        let pathLookup = Dictionary(
            uniqueKeysWithValues: indexedNotes.map {
                (WikiLinkNormalizer.noteLookupKey($0.note.relativePathWithoutExtension), $0.note.id)
            }
        )
        let headingLookupByNote = Dictionary(
            uniqueKeysWithValues: indexedNotes.map { indexed in
                (
                    indexed.note.id,
                    firstValueMap(indexed.documentIndex.headings) { $0.normalizedKey }
                )
            }
        )
        let blockLookupByNote = Dictionary(
            uniqueKeysWithValues: indexedNotes.map { indexed in
                (
                    indexed.note.id,
                    firstValueMap(indexed.documentIndex.blocks) { $0.normalizedKey }
                )
            }
        )

        var outgoingByNote: [URL: [ResolvedReference]] = [:]
        var backlinksByNote: [URL: [ResolvedReference]] = [:]

        let index = VaultLinkIndex(
            notesByID: notesByID,
            documentIndexesByNote: documentIndexesByNote,
            outgoingByNote: [:],
            backlinksByNote: [:],
            titleLookup: titleLookup,
            pathLookup: pathLookup,
            headingLookupByNote: headingLookupByNote,
            blockLookupByNote: blockLookupByNote
        )

        for indexedNote in indexedNotes {
            let references = indexedNote.documentIndex.references.map { reference in
                ResolvedReference(
                    sourceNoteID: indexedNote.note.id,
                    kind: reference.kind,
                    target: reference.target,
                    alias: reference.alias,
                    sourceSpan: reference.sourceSpan,
                    sourceSnippet: Self.snippet(in: indexedNote.note.content, around: reference.sourceSpan),
                    resolution: index.resolve(target: reference.target, from: indexedNote.note.id)
                )
            }

            outgoingByNote[indexedNote.note.id] = references

            for reference in references {
                guard let recipientNoteID = Self.recipientNoteID(for: reference.resolution) else {
                    continue
                }
                backlinksByNote[recipientNoteID, default: []].append(reference)
            }
        }

        return VaultLinkIndex(
            notesByID: notesByID,
            documentIndexesByNote: documentIndexesByNote,
            outgoingByNote: outgoingByNote,
            backlinksByNote: backlinksByNote,
            titleLookup: titleLookup,
            pathLookup: pathLookup,
            headingLookupByNote: headingLookupByNote,
            blockLookupByNote: blockLookupByNote
        )
    }

    func outgoing(for noteID: URL?) -> [ResolvedReference] {
        guard let noteID else { return [] }
        return outgoingByNote[noteID] ?? []
    }

    func backlinks(for noteID: URL?) -> [ResolvedReference] {
        guard let noteID else { return [] }
        return backlinksByNote[noteID] ?? []
    }

    func documentIndex(for noteID: URL?) -> DocumentIndex {
        guard let noteID else { return .empty }
        return documentIndexesByNote[noteID] ?? .empty
    }

    func note(for noteID: URL?) -> Note? {
        guard let noteID else { return nil }
        return notesByID[noteID]
    }

    func reference(in noteID: URL?, at offset: Int) -> ResolvedReference? {
        guard let noteID else { return nil }
        return outgoingByNote[noteID]?.first { $0.sourceSpan.contains(offset) }
    }

    func resolve(target: WikiTarget, from sourceNoteID: URL) -> ReferenceResolution {
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
            return destination.noteID
        case .noteResolved(let noteID, _):
            return noteID
        case .unresolved, .ambiguous:
            return nil
        }
    }

    private static func snippet(in content: String, around span: SourceSpan) -> String {
        let text = content as NSString
        guard text.length > 0 else { return "" }

        let lowerBound = max(0, span.location - 36)
        let upperBound = min(text.length, span.upperBound + 36)
        let snippetRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
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
