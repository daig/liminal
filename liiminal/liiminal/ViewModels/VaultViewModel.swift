import Foundation
import AppKit

@Observable
final class VaultViewModel {
    var vault: Vault?
    var selectedNoteID: URL?
    var errorMessage: String?

    let fileService = FileSystemService()

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

        // Clear selection if the selected note was deleted
        if let selectedID = selectedNoteID,
            !notes.contains(where: { $0.id == selectedID })
        {
            selectedNoteID = nil
        }
    }

    func createNote(titled title: String) {
        guard let vaultURL = vault?.url else { return }
        do {
            let newURL = try fileService.createNote(titled: title, in: vaultURL)
            refreshNotes()
            selectedNoteID = newURL
        } catch {
            errorMessage = "Failed to create note: \(error.localizedDescription)"
        }
    }

    private func loadVault(at url: URL) {
        let notes = fileService.scanDirectory(at: url)
        vault = Vault(url: url, notes: notes)
        selectedNoteID = nil

        fileService.startWatching(directory: url) { [weak self] in
            self?.refreshNotes()
        }
    }
}
