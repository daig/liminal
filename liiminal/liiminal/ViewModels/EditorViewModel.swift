import Foundation

@Observable
final class EditorViewModel {
    var currentNote: Note?
    var isDirty: Bool = false

    let fileService: FileSystemService
    private var saveTask: Task<Void, Never>?

    init(fileService: FileSystemService) {
        self.fileService = fileService
    }

    func openNote(_ note: Note) {
        // Save current note before switching
        if isDirty { save() }

        // Load fresh content from disk
        var loaded = note
        if let content = try? fileService.readFile(at: note.id) {
            loaded.content = content
        }
        currentNote = loaded
        isDirty = false
    }

    func textDidChange(_ newText: String) {
        currentNote?.content = newText
        isDirty = true
        scheduleSave()
    }

    func save() {
        saveTask?.cancel()
        guard let note = currentNote, isDirty else { return }
        try? fileService.writeFile(content: note.content, to: note.id)
        isDirty = false
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
