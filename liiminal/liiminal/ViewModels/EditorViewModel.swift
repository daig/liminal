import Foundation
import Observation

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
    var vimHintSnapshot: VimHintSnapshot?

    let fileService: FileSystemService
    @ObservationIgnored private var pendingVimHintCandidate: VimHintCandidate?
    @ObservationIgnored private var vimHintTask: Task<Void, Never>?
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
        clearVimHints()
    }

    func updateVimHintCandidate(_ candidate: VimHintCandidate?) {
        pendingVimHintCandidate = candidate

        switch candidate?.source {
        case .none:
            clearVimHints()
        case .some(.rootHelp):
            vimHintTask?.cancel()
            vimHintTask = nil
            vimHintSnapshot = candidate?.snapshot
        case .some(.pendingPrefix):
            if vimHintSnapshot != nil {
                vimHintTask?.cancel()
                vimHintTask = nil
                vimHintSnapshot = candidate?.snapshot
                return
            }

            vimHintTask?.cancel()
            vimHintSnapshot = nil
            vimHintTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.pendingVimHintCandidate == candidate else { return }
                    self.vimHintSnapshot = candidate?.snapshot
                    self.vimHintTask = nil
                }
            }
        }
    }

    func clearVimHints() {
        pendingVimHintCandidate = nil
        vimHintTask?.cancel()
        vimHintTask = nil
        vimHintSnapshot = nil
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
