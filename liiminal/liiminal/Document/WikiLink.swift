import Foundation

struct WikiTarget: Equatable, Hashable, Sendable {
    var notePath: String?
    var heading: String?
    var blockID: String?

    init(notePath: String? = nil, heading: String? = nil, blockID: String? = nil) {
        self.notePath = Self.cleanComponent(notePath)
        self.heading = Self.cleanComponent(heading)
        self.blockID = Self.cleanBlockID(blockID)
    }

    var isLocalOnly: Bool {
        notePath == nil
    }

    var hasAnchor: Bool {
        heading != nil || blockID != nil
    }

    var rawTargetString: String {
        var result = notePath ?? ""

        if let blockID {
            result += "#^\(blockID)"
        } else if let heading {
            result += "#\(heading)"
        }

        return result
    }

    static func parse(_ raw: String) -> WikiTarget {
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

enum ReferenceKind: String, Equatable, Hashable, Sendable {
    case link
    case embed
}

struct SourceSpan: Equatable, Hashable, Sendable {
    let location: Int
    let length: Int

    var upperBound: Int {
        location + length
    }

    func contains(_ offset: Int) -> Bool {
        offset >= location && offset < upperBound
    }
}

enum LinkNavigationAnchor: Equatable, Hashable, Sendable {
    case heading(String)
    case block(String)
    case sourceOffset(Int)
}

enum LinkDestination: Equatable, Hashable, Sendable {
    case note(URL)
    case heading(URL, heading: String)
    case block(URL, blockID: String)

    var noteID: URL {
        switch self {
        case .note(let noteID), .heading(let noteID, _), .block(let noteID, _):
            return noteID
        }
    }

    var anchor: LinkNavigationAnchor? {
        switch self {
        case .note:
            return nil
        case .heading(_, let heading):
            return .heading(heading)
        case .block(_, let blockID):
            return .block(blockID)
        }
    }
}

enum ReferenceResolution: Equatable, Hashable, Sendable {
    case resolved(LinkDestination)
    case noteResolved(URL, requestedAnchor: LinkNavigationAnchor)
    case unresolved
    case ambiguous([URL])
}

struct ResolvedReference: Identifiable, Equatable, Hashable, Sendable {
    let sourceNoteID: URL
    let kind: ReferenceKind
    let target: WikiTarget
    let alias: String?
    let sourceSpan: SourceSpan
    let sourceSnippet: String
    let resolution: ReferenceResolution

    var id: String {
        [
            sourceNoteID.absoluteString,
            kind.rawValue,
            target.rawTargetString,
            String(sourceSpan.location),
            String(sourceSpan.length),
        ].joined(separator: "|")
    }
}

struct NoteNavigationRequest: Equatable, Sendable {
    let noteID: URL
    let anchor: LinkNavigationAnchor?
    let nonce: UUID

    init(noteID: URL, anchor: LinkNavigationAnchor? = nil, nonce: UUID = UUID()) {
        self.noteID = noteID
        self.anchor = anchor
        self.nonce = nonce
    }
}

enum WikiLinkNormalizer {
    static func noteLookupKey(_ raw: String) -> String {
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

    static func headingLookupKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    static func blockLookupKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
