import Foundation
import Observation

enum VimMode: String {
    case normal
    case insert
    case visual
    case visualLine = "visual line"
}

extension VimMode {
    var isVisual: Bool {
        switch self {
        case .visual, .visualLine:
            true
        case .normal, .insert:
            false
        }
    }
}

@Observable
final class EditorViewModel {
    var currentNote: Note?
    var isDirty: Bool = false
    var document: Document = Document(blocks: [])
    var documentIndex: DocumentIndex = .empty
    var vimMode: VimMode = .normal
    var vimStatus = VimStatusPresentation(mode: .normal, detailText: nil)
    var vimHintSnapshot: VimHintSnapshot?
    var vimCursorInfo: VimCursorInfoPresentation?

    @ObservationIgnored let fileService: FileSystemService
    @ObservationIgnored private var pendingVimHintCandidate: VimHintCandidate?
    @ObservationIgnored private var vimHintTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var undoHistories: [URL: VimUndoHistory] = [:]
    private var markStores: [URL: VimMarkStore] = [:]
    private var scratchUndoHistory = VimUndoHistory(rootText: "")
    private var scratchMarkStore = VimMarkStore()

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
        documentIndex = DocumentIndex.build(from: document)
        clearVimHints()
        vimCursorInfo = nil
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

    func updateVimCursorInfo(_ info: VimCursorInfoPresentation?) {
        vimCursorInfo = info
    }

    func textDidChange(_ newText: String) {
        currentNote?.content = newText
        isDirty = true
        document = Document(blocks: BlockParser.parse(newText))
        documentIndex = DocumentIndex.build(from: document)
        scheduleSave()
    }

    func undoHistory(for note: Note?) -> VimUndoHistory {
        ensureEditorState(for: note).undoHistory
    }

    func markStore(for note: Note?) -> VimMarkStore {
        ensureEditorState(for: note).markStore
    }

    private func ensureEditorState(for note: Note?) -> (undoHistory: VimUndoHistory, markStore: VimMarkStore) {
        let loadedText = note?.content ?? ""

        guard let noteID = note?.id else {
            if scratchUndoHistory.currentText != loadedText {
                scratchUndoHistory = VimUndoHistory(rootText: loadedText)
                scratchMarkStore = VimMarkStore()
            }
            return (scratchUndoHistory, scratchMarkStore)
        }

        if let existingHistory = undoHistories[noteID], existingHistory.currentText == loadedText {
            if let existingMarkStore = markStores[noteID] {
                return (existingHistory, existingMarkStore)
            }

            let markStore = VimMarkStore()
            markStores[noteID] = markStore
            return (existingHistory, markStore)
        }

        let history = VimUndoHistory(rootText: loadedText)
        let markStore = VimMarkStore()
        undoHistories[noteID] = history
        markStores[noteID] = markStore
        return (history, markStore)
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
