import Foundation

enum LinkActivationDecision: Equatable, Sendable {
    case open(noteID: URL, anchor: LinkNavigationAnchor?)
    case createNote(relativePath: String)
    case showAmbiguous([URL])
    case noAction
}

enum LinkActivationPolicy {
    static func decision(
        for target: WikiTarget,
        resolution: ReferenceResolution
    ) -> LinkActivationDecision {
        switch resolution {
        case .resolved(let destination):
            return .open(noteID: destination.noteID, anchor: destination.anchor)
        case .noteResolved(let noteID, _):
            return .open(noteID: noteID, anchor: nil)
        case .unresolved:
            guard let notePath = target.notePath else { return .noAction }
            return .createNote(relativePath: notePath)
        case .ambiguous(let candidates):
            return .showAmbiguous(candidates)
        }
    }

    static func decision(for reference: ResolvedReference) -> LinkActivationDecision {
        decision(for: reference.target, resolution: reference.resolution)
    }

    static func decision(forBacklink reference: ResolvedReference) -> LinkActivationDecision {
        .open(
            noteID: reference.sourceNoteID,
            anchor: .sourceOffset(reference.sourceSpan.location)
        )
    }
}
