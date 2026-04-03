import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    let editorViewModel: EditorViewModel

    func makeNSView(context: Context) -> NSScrollView {
        // Build TextKit 2 stack
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textLayoutManager.textContainer = textContainer

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Load initial content
        if let note = editorViewModel.currentNote {
            textView.string = note.content
            context.coordinator.currentNoteID = note.id
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let newNoteID = editorViewModel.currentNote?.id
        if context.coordinator.currentNoteID != newNoteID {
            context.coordinator.currentNoteID = newNoteID
            textView.string = editorViewModel.currentNote?.content ?? ""
            // Reset scroll position when switching notes
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(editorViewModel: editorViewModel)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var currentNoteID: URL?
        let editorViewModel: EditorViewModel

        init(editorViewModel: EditorViewModel) {
            self.editorViewModel = editorViewModel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            editorViewModel.textDidChange(textView.string)
        }
    }
}
