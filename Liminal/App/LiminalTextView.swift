import AppKit
import CambiumCore
import CambiumIncremental
import SwiftUI

struct LiminalTextView: NSViewRepresentable {
    @ObservedObject var document: LiminalSourceDocument

    func makeNSView(context: Context) -> NSScrollView {
        let textView = VimTextView()
        let scrollView = Self.makeScrollView(wrapping: textView)

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.typingAttributes = context.coordinator.theme.defaultAttributes

        textView.string = document.session.source
        textView.textStorage?.delegate = context.coordinator
        textView.vimController = document.vimController

        context.coordinator.textView = textView
        document.vimController.delegate = context.coordinator

        DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            coordinator?.applyHighlights()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VimTextView else { return }
        let target = document.session.source
        if textView.string != target {
            context.coordinator.isApplyingProgrammaticEdit = true
            textView.string = target
            context.coordinator.isApplyingProgrammaticEdit = false
            context.coordinator.applyHighlights()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    // MARK: - Scroll view construction
    //
    // `NSTextView.scrollableTextView()` returns a stock NSTextView; to
    // host our `VimTextView` subclass we replicate the wrapping manually.
    // Mirrors AppKit's own implementation: a non-flipped clip view, a
    // text view sized to the clip's content size with sane resizing
    // masks, and a vertical scroller.

    private static func makeScrollView(wrapping textView: VimTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = false

        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    @MainActor
    final class Coordinator: NSObject, NSTextStorageDelegate, VimControllerDelegate {
        let document: LiminalSourceDocument
        weak var textView: VimTextView?
        var isApplyingProgrammaticEdit = false

        let highlighter = LiminalHighlighter()
        let theme = LiminalHighlightTheme.default

        init(document: LiminalSourceDocument) {
            self.document = document
        }

        // MARK: - NSTextStorageDelegate

        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }

            let replacement = textStorage.attributedSubstring(from: editedRange).string

            MainActor.assumeIsolated {
                guard !isApplyingProgrammaticEdit else { return }

                let preEditRange = NSRange(
                    location: editedRange.location,
                    length: editedRange.length - delta
                )
                let preEditSource = document.session.source
                guard let byteRange = LiminalTextView.utf16RangeToByteRange(
                    preEditRange,
                    in: preEditSource
                ) else {
                    NSLog("LiminalTextView: failed to convert NSRange \(preEditRange) to byte range")
                    return
                }

                let edit = TextEdit(
                    range: TextRange(
                        start: TextSize(UInt32(byteRange.lowerBound)),
                        length: TextSize(UInt32(byteRange.count))
                    ),
                    replacement: replacement
                )
                document.applyTextEdits([edit])
                applyHighlights()
            }
        }

        // MARK: - VimControllerDelegate

        func moveCursor(direction: MoveDirection, count: Int) {
            guard let textView else { return }
            let steps = max(1, count)
            switch direction {
            case .left:
                for _ in 0..<steps { textView.moveLeft(self) }
            case .right:
                for _ in 0..<steps { textView.moveRight(self) }
            case .up:
                for _ in 0..<steps { textView.moveUp(self) }
            case .down:
                for _ in 0..<steps { textView.moveDown(self) }
            }
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func structuralMotion(_ motion: StructuralMotion, count: Int) {
            guard let textView,
                  let parsed = document.session.parseResult
            else { return }
            let steps = max(1, count)

            // Start from the current cursor byte offset, jump iteratively.
            var byteOffset = currentCursorByteOffset() ?? 0
            for _ in 0..<steps {
                let next: Int?
                switch motion {
                case .previousSibling:
                    next = StructureCursor.previousSibling(of: byteOffset, in: parsed.rootSyntax)
                case .nextSibling:
                    next = StructureCursor.nextSibling(of: byteOffset, in: parsed.rootSyntax)
                }
                guard let next else { break }
                byteOffset = next
            }
            setCursor(byteOffset: byteOffset)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func toggleTaskAtCursor() {
            guard let offset = currentCursorByteOffset() else { return }
            document.toggleTaskAt(byteOffset: offset)
        }

        // MARK: - Cursor helpers

        private func currentCursorByteOffset() -> Int? {
            guard let textView else { return nil }
            let selectedRange = textView.selectedRange()
            let cursorNSRange = NSRange(location: selectedRange.location, length: 0)
            return LiminalTextView.utf16RangeToByteRange(
                cursorNSRange,
                in: textView.string
            )?.lowerBound
        }

        private func setCursor(byteOffset: Int) {
            guard let textView else { return }
            let range = CambiumCore.TextRange(
                start: TextSize(UInt32(max(0, byteOffset))),
                length: TextSize(UInt32(0))
            )
            guard let nsRange = LiminalTextView.byteRangeToNSRange(range, in: textView.string)
            else { return }
            textView.setSelectedRange(nsRange)
        }

        /// Re-apply highlights to the entire text storage from the current
        /// parse result. Called after every user edit, on initial display,
        /// and when the source is replaced externally (document load).
        func applyHighlights() {
            guard let textView,
                  let storage = textView.textStorage,
                  let parsed = document.session.parseResult
            else { return }

            let spans = highlighter.spans(for: parsed.rootSyntax)
            let source = storage.string
            let fullRange = NSRange(location: 0, length: storage.length)

            isApplyingProgrammaticEdit = true
            storage.beginEditing()
            storage.setAttributes(theme.defaultAttributes, range: fullRange)
            for span in spans {
                guard let nsRange = LiminalTextView.byteRangeToNSRange(span.range, in: source) else {
                    continue
                }
                let attrs = theme.attributes(for: span.category, modifiers: span.modifiers)
                storage.addAttributes(attrs, range: nsRange)
            }
            storage.endEditing()
            isApplyingProgrammaticEdit = false

            textView.typingAttributes = theme.defaultAttributes
        }
    }

    // MARK: - Byte ↔ UTF-16 range conversion

    nonisolated static func utf16RangeToByteRange(
        _ nsRange: NSRange,
        in source: String
    ) -> Range<Int>? {
        let utf16 = source.utf16
        guard nsRange.location >= 0,
              nsRange.length >= 0,
              nsRange.location <= utf16.count,
              nsRange.location + nsRange.length <= utf16.count
        else { return nil }

        let startUTF16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location)
        let endUTF16 = utf16.index(startUTF16, offsetBy: nsRange.length)
        guard let startStr = String.Index(startUTF16, within: source),
              let endStr = String.Index(endUTF16, within: source)
        else { return nil }

        let startByte = source.utf8.distance(from: source.utf8.startIndex, to: startStr)
        let endByte = source.utf8.distance(from: source.utf8.startIndex, to: endStr)
        return startByte..<endByte
    }

    nonisolated static func byteRangeToNSRange(
        _ range: CambiumCore.TextRange,
        in source: String
    ) -> NSRange? {
        let startByte = Int(range.start.rawValue)
        let endByte = startByte + Int(range.length.rawValue)
        let utf8 = source.utf8
        guard startByte >= 0, endByte >= startByte, endByte <= utf8.count else {
            return nil
        }

        let startUTF8 = utf8.index(utf8.startIndex, offsetBy: startByte)
        let endUTF8 = utf8.index(utf8.startIndex, offsetBy: endByte)
        guard let startStr = startUTF8.samePosition(in: source),
              let endStr = endUTF8.samePosition(in: source)
        else { return nil }

        let utf16 = source.utf16
        guard let startUTF16Idx = startStr.samePosition(in: utf16),
              let endUTF16Idx = endStr.samePosition(in: utf16)
        else { return nil }

        let startUTF16 = utf16.distance(from: utf16.startIndex, to: startUTF16Idx)
        let endUTF16 = utf16.distance(from: utf16.startIndex, to: endUTF16Idx)
        return NSRange(location: startUTF16, length: endUTF16 - startUTF16)
    }
}
