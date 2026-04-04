import Foundation

enum VimMode: String {
    case normal
    case insert
}

@Observable
final class EditorViewModel {
    var currentNote: Note?
    var isDirty: Bool = false
    var document: Document = Document(blocks: [])
    var vimMode: VimMode = .normal
    var vimStatus = VimStatusPresentation(mode: .normal, detailText: nil)

    let fileService: FileSystemService
    private var saveTask: Task<Void, Never>?
    private var undoHistories: [URL: VimUndoHistory] = [:]
    private var scratchUndoHistory = VimUndoHistory(rootText: "")

    init(fileService: FileSystemService) {
        self.fileService = fileService
    }

    func openNote(_ note: Note) {
        if isDirty { save() }

        var loaded = note
        if let content = try? fileService.readFile(at: note.id) {
            loaded.content = content
        }
        currentNote = loaded
        isDirty = false
        document = Document(blocks: BlockParser.parse(loaded.content))
    }

    func textDidChange(_ newText: String) {
        currentNote?.content = newText
        isDirty = true
        document = Document(blocks: BlockParser.parse(newText))
        scheduleSave()
    }

    func undoHistory(for note: Note?) -> VimUndoHistory {
        let loadedText = note?.content ?? ""

        guard let noteID = note?.id else {
            if scratchUndoHistory.currentText != loadedText {
                scratchUndoHistory = VimUndoHistory(rootText: loadedText)
            }
            return scratchUndoHistory
        }

        if let existingHistory = undoHistories[noteID], existingHistory.currentText == loadedText {
            return existingHistory
        }

        let history = VimUndoHistory(rootText: loadedText)
        undoHistories[noteID] = history
        return history
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
