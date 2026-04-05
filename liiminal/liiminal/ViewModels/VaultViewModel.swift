import Foundation
import AppKit

@Observable
final class VaultViewModel {
    var vault: Vault?
    var selectedNoteID: URL?
    var linkIndex: VaultLinkIndex = .empty
    var navigationRequest: NoteNavigationRequest?
    var errorMessage: String?

    @ObservationIgnored let fileService = FileSystemService()

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return vault?.notes.first { $0.id == id }
    }

    func restorePreviousVault() {
        guard let url = BookmarkService.resolveBookmark() else { return }
        loadVault(at: url)
    }

    func openVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing your markdown notes"
        panel.prompt = "Open Vault"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Stop accessing previous vault's security scope if any
        if let previousURL = vault?.url {
            previousURL.stopAccessingSecurityScopedResource()
        }

        try? BookmarkService.saveBookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
        loadVault(at: url)
    }

    func refreshNotes() {
        guard let url = vault?.url else { return }
        let notes = fileService.scanDirectory(at: url)
        vault?.notes = notes
        rebuildLinkIndex()

        // Clear selection if the selected note was deleted
        if let selectedID = selectedNoteID,
            !notes.contains(where: { $0.id == selectedID })
        {
            selectedNoteID = nil
            navigationRequest = nil
        }
    }

    func createNote(titled title: String) {
        guard let vaultURL = vault?.url else { return }
        do {
            let newURL = try fileService.createNote(titled: title, in: vaultURL)
            refreshNotes()
            selectedNoteID = newURL
            navigationRequest = NoteNavigationRequest(noteID: newURL)
        } catch {
            errorMessage = "Failed to create note: \(error.localizedDescription)"
        }
    }

    func updateNoteContent(noteID: URL, content: String) {
        guard let noteIndex = vault?.notes.firstIndex(where: { $0.id == noteID }) else { return }
        vault?.notes[noteIndex].content = content
        rebuildLinkIndex()
    }

    func outgoingReferences(for noteID: URL?) -> [ResolvedReference] {
        linkIndex.outgoing(for: noteID)
    }

    func backlinks(for noteID: URL?) -> [ResolvedReference] {
        linkIndex.backlinks(for: noteID)
    }

    func documentIndex(for noteID: URL?) -> DocumentIndex {
        linkIndex.documentIndex(for: noteID)
    }

    func reference(in noteID: URL?, at offset: Int) -> ResolvedReference? {
        linkIndex.reference(in: noteID, at: offset)
    }

    func resolveReference(
        _ reference: DocumentReference,
        from sourceNoteID: URL,
        content: String
    ) -> ResolvedReference {
        ResolvedReference(
            sourceNoteID: sourceNoteID,
            kind: reference.kind,
            target: reference.target,
            alias: reference.alias,
            sourceSpan: reference.sourceSpan,
            sourceSnippet: snippet(in: content, around: reference.sourceSpan),
            resolution: linkIndex.resolve(target: reference.target, from: sourceNoteID)
        )
    }

    func note(for noteID: URL?) -> Note? {
        linkIndex.note(for: noteID)
    }

    func clearNavigationRequest() {
        navigationRequest = nil
    }

    func activateTarget(_ target: WikiTarget, from sourceNoteID: URL?) {
        guard let sourceNoteID else { return }
        let resolution = linkIndex.resolve(target: target, from: sourceNoteID)
        apply(LinkActivationPolicy.decision(for: target, resolution: resolution))
    }

    func activateReference(_ reference: ResolvedReference) {
        apply(LinkActivationPolicy.decision(for: reference))
    }

    func activateBacklink(_ reference: ResolvedReference) {
        apply(LinkActivationPolicy.decision(forBacklink: reference))
    }

    private func loadVault(at url: URL) {
        let notes = fileService.scanDirectory(at: url)
        vault = Vault(url: url, notes: notes)
        rebuildLinkIndex()
        selectedNoteID = nil
        navigationRequest = nil

        fileService.startWatching(directory: url) { [weak self] in
            self?.refreshNotes()
        }
    }

    private func rebuildLinkIndex() {
        linkIndex = VaultLinkIndex.build(notes: vault?.notes ?? [])
    }

    private func open(noteID: URL, anchor: LinkNavigationAnchor?) {
        selectedNoteID = noteID
        navigationRequest = NoteNavigationRequest(noteID: noteID, anchor: anchor)
    }

    private func apply(_ decision: LinkActivationDecision) {
        switch decision {
        case .open(let noteID, let anchor):
            open(noteID: noteID, anchor: anchor)
        case .createNote(let relativePath):
            createAndOpenNote(atRelativePath: relativePath)
        case .showAmbiguous(let candidates):
            let noteNames = candidates.compactMap { note(for: $0)?.relativePath }
            errorMessage = "Ambiguous wiki link: " + noteNames.joined(separator: ", ")
        case .noAction:
            break
        }
    }

    private func createAndOpenNote(atRelativePath relativePath: String) {
        guard let vaultURL = vault?.url else { return }

        do {
            let newURL = try fileService.createNote(atRelativePath: relativePath, in: vaultURL)
            refreshNotes()
            open(noteID: newURL, anchor: nil)
        } catch {
            errorMessage = "Failed to create note: \(error.localizedDescription)"
        }
    }

    private func snippet(in content: String, around span: SourceSpan) -> String {
        let text = content as NSString
        guard text.length > 0 else { return "" }

        let lowerBound = max(0, span.location - 36)
        let upperBound = min(text.length, span.upperBound + 36)
        let snippetRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
        return text.substring(with: snippetRange)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
