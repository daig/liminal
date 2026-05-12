import AppKit
import CambiumCore
import CambiumIncremental
import Combine
import SwiftUI

struct LiminalTextView: NSViewRepresentable {
    @ObservedObject var document: LiminalSourceDocument

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.makeVimTextView()
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
        // Mirror initial mode into the layout manager's cursor style and
        // start watching for changes.
        context.coordinator.installModeObservers(on: document.vimController)
        context.coordinator.refreshCursorStyle()

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
        context.coordinator.refreshCursorStyle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    // MARK: - View construction
    //
    // `NSTextView.scrollableTextView()` returns a stock NSTextView; to
    // host our `VimTextView` subclass we wire up the text stack manually.

    private static func makeVimTextView() -> VimTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        return VimTextView(frame: .zero, textContainer: textContainer)
    }

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

        private var modeObservation: AnyCancellable?

        init(document: LiminalSourceDocument) {
            self.document = document
        }

        // MARK: - Mode observation

        func installModeObservers(on controller: VimController) {
            modeObservation = controller.$mode.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCursorStyle()
                }
            }
        }

        /// Block-cursor effect via selection: in Normal mode, the cursor's
        /// selection is length 1 so NSTextView's selection highlight paints
        /// a block over the "current" character. In Insert mode, length 0
        /// for a conventional caret. Called after every motion and on mode
        /// transitions.
        func refreshCursorStyle() {
            guard let textView else { return }
            let current = textView.selectedRange()
            let textLength = (textView.string as NSString).length
            switch document.vimController.mode {
            case .normal:
                let location = min(current.location, max(textLength - 1, 0))
                let length = (location < textLength) ? 1 : 0
                if current.location != location || current.length != length {
                    textView.setSelectedRange(NSRange(location: location, length: length))
                }
            case .insert:
                if current.length != 0 {
                    textView.setSelectedRange(NSRange(location: current.location, length: 0))
                }
            }
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
        //
        // Cursor motion writes `setSelectedRange` directly rather than going
        // through NSResponder action methods (moveLeft/Right/Up/Down), which
        // can silently no-op depending on responder state. All motion math
        // lives in `CursorMotionEngine`; this method just hands off and
        // applies the result.

        func moveCursor(motion: CursorMotion, count: Int) {
            guard let textView else { return }
            let currentLocation = textView.selectedRange().location
            let newLocation = CursorMotionEngine.newOffset(
                for: motion,
                in: textView.string,
                from: currentLocation,
                count: count
            )
            setCursorAt(utf16Location: newLocation)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func structuralMotion(_ motion: StructuralMotion, count: Int) {
            guard let textView,
                  let parsed = document.session.parseResult
            else { return }
            let steps = max(1, count)

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

        /// Task toggle: structural CST edit + surgical textStorage sync.
        ///
        /// The architecturally-honest path: the action is "flip the state
        /// of this checkbox," and we know statically that this preserves
        /// every other token's content and every sibling subtree's
        /// identity. So we rebuild the listItem subtree with only the
        /// `.taskMarker` token's text changed, and commit via Phase 5a's
        /// structural replace primitive. No reparse, no highlight refresh
        /// (marker attributes are invariant under toggle), no source-to-
        /// string round-trip.
        ///
        /// After the structural edit lands, `session.source` reflects the
        /// new text but the textStorage still shows the old. We sync the
        /// 3-byte marker range surgically with the textStorage delegate
        /// suppressed so the edit doesn't loop back as a textual edit.
        func toggleTaskAtCursor() {
            guard let textView,
                  let root = document.currentRootSyntax,
                  let offset = currentCursorByteOffset(),
                  let location = StructureCursor.taskListItem(at: offset, in: root)
            else { return }

            let newMarker: String
            switch location.state {
            case .unchecked: newMarker = "[x]"
            case .checked:   newMarker = "[ ]"
            }

            guard let nsRange = LiminalTextView.byteRangeToNSRange(
                location.markerByteRange,
                in: textView.string
            ) else { return }

            // Step 1: structural CST edit. `session.lastTree` advances;
            // `session.source` now has the flipped marker.
            guard document.structuralToggleTask(listItemHandle: location.listItemHandle)
            else { return }

            // Step 2: surgically sync the textStorage at the marker range.
            // `isApplyingProgrammaticEdit` suppresses the textStorage
            // delegate's reparse path, so this is a one-way sync, not a
            // round-trip through `applyTextEdits`.
            isApplyingProgrammaticEdit = true
            if textView.shouldChangeText(in: nsRange, replacementString: newMarker) {
                textView.replaceCharacters(in: nsRange, with: newMarker)
                textView.didChangeText()
            }
            isApplyingProgrammaticEdit = false

            // Step 3: cursor on the (now-toggled) marker for the block
            // cursor's benefit.
            setCursorAt(utf16Location: nsRange.location)
        }

        // MARK: - Marks

        /// Encode the current cursor position as a `CSTAnchor` and stash
        /// it under `name` in the controller's mark registry.
        func setMark(_ name: Character) {
            guard let root = document.currentRootSyntax,
                  let byteOffset = currentCursorByteOffset()
            else { return }
            let offset = TextSize(UInt32(byteOffset))
            guard let anchor = CSTAnchor.atSourceOffset(offset, in: root)
            else { return }
            document.vimController.setMark(name, anchor: anchor)
        }

        /// Resolve a stored mark against the current tree and move the
        /// cursor there. Lost or unknown marks are silent no-ops.
        func jumpToMark(_ name: Character) {
            guard let textView,
                  let root = document.currentRootSyntax,
                  let anchor = document.vimController.marks.anchor(named: name)
            else { return }
            let byteOffset: TextSize
            switch anchor.resolve(in: root) {
            case .strong(let off), .weak(let off), .recovered(let off):
                byteOffset = off
            case .lost:
                return
            }
            setCursor(byteOffset: Int(byteOffset.rawValue))
            textView.scrollRangeToVisible(textView.selectedRange())
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
            setCursorAt(utf16Location: nsRange.location)
        }

        /// Centralized cursor placement: in Normal mode wraps a length-1
        /// selection around the character at `utf16Location` (so the
        /// system-drawn selection highlight acts as our block cursor); in
        /// Insert mode places a length-0 caret.
        private func setCursorAt(utf16Location: Int) {
            guard let textView else { return }
            let textLength = (textView.string as NSString).length
            let clampedLocation = max(0, min(utf16Location, textLength))
            let length: Int
            switch document.vimController.mode {
            case .normal:
                length = (clampedLocation < textLength) ? 1 : 0
            case .insert:
                length = 0
            }
            textView.setSelectedRange(NSRange(location: clampedLocation, length: length))
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
