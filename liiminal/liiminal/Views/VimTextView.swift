import AppKit

/// NSTextView subclass that implements vim-style modal editing.
///
/// Uses `NSEvent.characters` for key matching, which respects the active
/// keyboard layout (Colemak, Dvorak, etc.) — the character that *would* be
/// typed in insert mode is the one matched in normal mode.
final class VimTextView: NSTextView {
    private enum OpenLineDirection {
        case above
        case below
    }

    weak var vimDelegate: VimTextViewDelegate?

    private let vimEngine = VimEngine()
    private var activeUndoHistory: VimUndoHistory?
    private var suppressUndoCapture = false
    private var isShowingRootHintCatalog = false
    private var visualAnchorPosition: Int?

    /// Cursor position tracked independently in normal mode.
    private var normalCursorPosition: Int = 0

    private static let cursorHighlightKey = NSAttributedString.Key("vimCursorHighlight")
    private static let cursorColor = NSColor.systemOrange.withAlphaComponent(0.4)

    /// Current editing mode.
    private(set) var mode: VimMode = .normal {
        didSet {
            if mode != oldValue {
                if oldValue == .visual && mode != .visual {
                    visualAnchorPosition = nil
                }
                if mode != .normal {
                    isShowingRootHintCatalog = false
                }
                updateModeAppearance()
                vimDelegate?.vimTextView(self, didChangeMode: mode)
                publishVimState()
            }
        }
    }

    // MARK: - Mode Appearance

    private func updateModeAppearance() {
        switch mode {
        case .normal:
            isEditable = false
            // Capture cursor position from the real selection
            normalCursorPosition = selectedRange().location
            drawNormalCursor()
        case .visual:
            isEditable = false
            clearNormalCursor()
            let selectionRange = visualSelectionDisplayRange()
            setSelectedRange(selectionRange)
            scrollRangeToVisible(selectionRange)
        case .insert:
            clearNormalCursor()
            // Place the real insertion point at the tracked position
            setSelectedRange(NSRange(location: insertionPointPosition(), length: 0))
            isEditable = true
            insertionPointColor = .textColor
        }
    }

    // MARK: - Normal Mode Cursor (background highlight)

    private func drawNormalCursor() {
        guard let lm = layoutManager, textContainer != nil else { return }
        let text = string as NSString
        let length = text.length

        // Clear any previous highlight
        lm.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: length)
        )

        guard length > 0 else { return }
        let pos = min(normalCursorPosition, length - 1)
        normalCursorPosition = max(pos, 0)

        // Highlight the character at the cursor position
        let highlightRange = NSRange(location: normalCursorPosition, length: 1)
        lm.addTemporaryAttribute(
            .backgroundColor,
            value: Self.cursorColor,
            forCharacterRange: highlightRange
        )

        // Ensure it's visible
        scrollRangeToVisible(highlightRange)
    }

    private func clearNormalCursor() {
        guard let lm = layoutManager else { return }
        let length = (string as NSString).length
        lm.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: length)
        )
    }

    /// Update the cursor position and redraw.
    private func moveCursorTo(_ pos: Int) {
        let length = (string as NSString).length
        normalCursorPosition = max(0, min(pos, max(length - 1, 0)))
        drawNormalCursor()
    }

    private func moveVisualCursorTo(_ pos: Int) {
        let text = string as NSString
        normalCursorPosition = text.length > 0
            ? max(0, min(pos, text.length - 1))
            : 0

        let selectionRange = visualSelectionDisplayRange()
        setSelectedRange(selectionRange)
        scrollRangeToVisible(selectionRange)
    }

    private func insertionPointPosition() -> Int {
        let length = (string as NSString).length
        return max(0, min(normalCursorPosition, length))
    }

    private func visualSelectionDisplayRange() -> NSRange {
        let text = string as NSString
        guard text.length > 0, let visualAnchorPosition else {
            return NSRange(location: 0, length: 0)
        }

        let anchor = max(0, min(visualAnchorPosition, text.length - 1))
        let head = max(0, min(normalCursorPosition, text.length - 1))
        let lowerBound = min(anchor, head)
        let upperBound = max(anchor, head) + 1
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private func currentVisualSelection() -> VimSelectionResult? {
        let text = string as NSString
        guard text.length > 0, visualAnchorPosition != nil else { return nil }

        let range = visualSelectionDisplayRange()
        guard range.length > 0 else { return nil }

        return VimSelectionResult(
            range: range,
            cursorAnchor: range.location,
            linewise: false
        )
    }

    func loadDocumentText(_ text: String, undoHistory: VimUndoHistory) {
        finalizeActiveInsertSessionIfNeeded()
        activeUndoHistory = undoHistory
        isShowingRootHintCatalog = false
        visualAnchorPosition = nil
        string = text
        normalCursorPosition = 0
        setSelectedRange(NSRange(location: 0, length: 0))
        vimEngine.reset()

        if mode != .normal {
            mode = .normal
        } else {
            updateModeAppearance()
        }

        publishVimState()
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalMode(event)
        case .visual:
            handleVisualMode(event)
        case .insert:
            handleInsertMode(event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalModeMouseDown(event)
        case .visual:
            handleVisualModeMouseDown(event)
        case .insert:
            super.mouseDown(with: event)
        }
    }

    override func shouldChangeText(
        in affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        else {
            return false
        }

        captureInsertEditIfNeeded(
            in: affectedCharRange,
            replacementString: replacementString ?? ""
        )
        return true
    }

    // MARK: - Insert Mode

    private func handleInsertMode(_ event: NSEvent) {
        // ESC → return to normal mode
        if keyPress(for: event) == .special(.escape) {
            enterNormalModeFromInsert()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Normal Mode

    private func handleNormalMode(_ event: NSEvent) {
        guard let keyPress = keyPress(for: event) else { return }

        if isShowingRootHintCatalog && vimEngine.sessionState.hasPendingInput == false {
            if keyPress == .character(" ") || keyPress == .special(.escape) {
                isShowingRootHintCatalog = false
                publishVimState()
                return
            }

            isShowingRootHintCatalog = false
        }

        if keyPress == .character(" ") && vimEngine.sessionState.hasPendingInput == false {
            isShowingRootHintCatalog.toggle()
            publishVimState()
            return
        }

        switch vimEngine.handle(keyPress) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }

        publishVimState()
    }

    private func handleNormalModeMouseDown(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        isShowingRootHintCatalog = false

        guard let targetPosition = mouseTargetPosition(for: event) else {
            publishVimState()
            return
        }

        switch vimEngine.handleTargetPosition(targetPosition) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }

        publishVimState()
    }

    private func handleVisualMode(_ event: NSEvent) {
        guard let keyPress = keyPress(for: event) else { return }

        switch vimEngine.handle(keyPress) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }

        publishVimState()
    }

    private func handleVisualModeMouseDown(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        isShowingRootHintCatalog = false

        guard let targetPosition = mouseTargetPosition(for: event) else {
            publishVimState()
            return
        }

        switch vimEngine.handleTargetPosition(targetPosition) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }

        publishVimState()
    }

    // MARK: - Mode Transitions

    private func enterInsertMode(at insertionPosition: Int? = nil) {
        visualAnchorPosition = nil
        if let insertionPosition {
            let length = (string as NSString).length
            normalCursorPosition = max(0, min(insertionPosition, length))
        }
        activeUndoHistory?.beginInsertSession(
            beforeCursorPosition: insertionPointPosition()
        )
        vimEngine.setMode(.insert)
        mode = .insert
    }

    private func enterNormalModeFromInsert() {
        vimEngine.setMode(.normal)
        mode = .normal
        normalCursorPosition = committedNormalCursorPosition()
        drawNormalCursor()
        activeUndoHistory?.commitInsertSession(finalCursorPosition: normalCursorPosition)
    }

    private func enterVisualMode() {
        let text = string as NSString
        let anchor = text.length > 0
            ? max(0, min(normalCursorPosition, text.length - 1))
            : 0

        visualAnchorPosition = anchor
        vimEngine.setMode(.visual)
        mode = .visual
    }

    private func enterNormalModeFromVisual(at cursorPosition: Int) {
        let text = string as NSString
        let clampedCursor = text.length > 0
            ? max(0, min(cursorPosition, text.length - 1))
            : 0

        visualAnchorPosition = nil
        setSelectedRange(NSRange(location: min(clampedCursor, text.length), length: 0))
        normalCursorPosition = clampedCursor
        vimEngine.clearPendingInput()
        vimEngine.setPreferredColumn(nil)
        vimEngine.setMode(.normal)
        mode = .normal
    }

    private func apply(_ command: VimCommand) {
        switch command {
        case .beginOperator:
            return
        case .enterVisual:
            enterVisualMode()
        case .exitVisual:
            enterNormalModeFromVisual(at: normalCursorPosition)
        case .enterInsert(let transition):
            applyInsertTransition(transition)
        case .moveText(let motion, let count):
            let navigationResult = VimNavigator.destination(
                for: motion,
                count: count,
                in: string as NSString,
                from: normalCursorPosition,
                preferredColumn: vimEngine.sessionState.preferredColumn
            )

            vimEngine.setPreferredColumn(navigationResult.preferredColumn)
            if mode == .visual {
                moveVisualCursorTo(navigationResult.position)
            } else {
                moveCursorTo(navigationResult.position)
            }
        case .moveLayout(let motion, let count):
            let destination = VimLayoutNavigator.destination(
                for: motion,
                count: count,
                in: self,
                from: normalCursorPosition
            )
            vimEngine.setPreferredColumn(nil)
            if mode == .visual {
                moveVisualCursorTo(destination)
            } else {
                moveCursorTo(destination)
            }
        case .delete(let target):
            applyDelete(target)
        case .change(let target):
            applyChange(target)
        case .yank(let target):
            applyYank(target)
        case .deleteSelection:
            applyVisualDelete()
        case .changeSelection:
            applyVisualChange()
        case .yankSelection:
            applyVisualYank()
        case .paste(let placement, let count):
            applyPaste(placement, count: count)
        case .replaceSelectionWithPaste(let count):
            applyVisualPaste(count: count)
        case .undo(let count):
            applyUndo(count: count)
        case .redo(let count):
            applyRedo(count: count)
        }
    }

    private func applyInsertTransition(_ transition: VimInsertTransition) {
        let text = string as NSString

        switch transition {
        case .atCursor:
            enterInsertMode()
        case .afterCursor:
            enterInsertMode(at: appendInsertionPosition(in: text))
        case .lineFirstNonBlank:
            enterInsertMode(at: firstNonBlankInsertionPosition(in: text))
        case .lineEnd:
            enterInsertMode(at: lineEndInsertionPosition(in: text))
        case .openLineBelow:
            openLine(.below, in: text)
        case .openLineAbove:
            openLine(.above, in: text)
        }
    }

    private func openLine(_ direction: OpenLineDirection, in text: NSString) {
        let insertionLocation: Int
        let finalSelectionLocation: Int

        if text.length == 0 {
            insertionLocation = 0
            finalSelectionLocation = direction == .below ? 1 : 0
        } else {
            let lineRange = currentLineRange(in: text)

            switch direction {
            case .below:
                insertionLocation = lineContentUpperBound(of: lineRange, in: text)
                finalSelectionLocation = insertionLocation + 1
            case .above:
                insertionLocation = lineRange.location
                finalSelectionLocation = insertionLocation
            }
        }

        enterInsertMode(at: insertionLocation)
        insertText("\n", replacementRange: selectedRange())

        let length = (string as NSString).length
        let clampedSelection = max(0, min(finalSelectionLocation, length))
        setSelectedRange(NSRange(location: clampedSelection, length: 0))
        normalCursorPosition = clampedSelection
    }

    private func appendInsertionPosition(in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        let currentPosition = max(0, min(normalCursorPosition, text.length - 1))
        if text.character(at: currentPosition) == 0x0A {
            return currentPosition
        }

        let lineRange = currentLineRange(in: text)
        return min(currentPosition + 1, lineContentUpperBound(of: lineRange, in: text))
    }

    private func firstNonBlankInsertionPosition(in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        return firstNonBlank(in: currentLineRange(in: text), text: text)
    }

    private func lineEndInsertionPosition(in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        return lineContentUpperBound(of: currentLineRange(in: text), in: text)
    }

    private func currentLineRange(in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let location = max(0, min(normalCursorPosition, text.length - 1))
        return text.lineRange(for: NSRange(location: location, length: 0))
    }

    private func lineContentUpperBound(of lineRange: NSRange, in text: NSString) -> Int {
        guard lineRange.length > 0 else { return lineRange.location }

        let lastIndex = NSMaxRange(lineRange) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(lineRange)
    }

    private func firstNonBlank(in range: NSRange, text: NSString) -> Int {
        let upperBound = lineContentUpperBound(of: range, in: text)
        var currentIndex = range.location

        while currentIndex < upperBound {
            let character = text.character(at: currentIndex)
            guard let scalar = Unicode.Scalar(character) else { break }
            if !CharacterSet.whitespaces.contains(scalar) {
                return currentIndex
            }
            currentIndex += 1
        }

        return range.location
    }

    private func applyDelete(_ target: VimOperatorTarget) {
        guard let selection = resolvedSelection(for: target, from: normalCursorPosition) else {
            return
        }

        applyDelete(selection, beforeCursorPosition: normalCursorPosition)
    }

    private func applyChange(_ target: VimOperatorTarget) {
        guard let selection = resolvedSelection(for: target, from: normalCursorPosition) else {
            return
        }

        applyChange(selection, beforeCursorPosition: normalCursorPosition)
    }

    private func applyYank(_ target: VimOperatorTarget) {
        guard let selection = resolvedSelection(for: target, from: normalCursorPosition) else {
            return
        }

        applyYank(selection)
    }

    private func applyVisualDelete() {
        guard let selection = currentVisualSelection() else {
            enterNormalModeFromVisual(at: normalCursorPosition)
            return
        }

        let beforeCursor = normalCursorPosition
        applyDelete(selection, beforeCursorPosition: beforeCursor)
        enterNormalModeFromVisual(at: normalCursorPosition)
    }

    private func applyVisualChange() {
        guard let selection = currentVisualSelection() else {
            enterNormalModeFromVisual(at: normalCursorPosition)
            return
        }

        let beforeCursor = normalCursorPosition
        visualAnchorPosition = nil
        applyChange(selection, beforeCursorPosition: beforeCursor)
    }

    private func applyVisualYank() {
        guard let selection = currentVisualSelection() else {
            enterNormalModeFromVisual(at: normalCursorPosition)
            return
        }

        let finalCursor = selection.range.location
        applyYank(selection)
        enterNormalModeFromVisual(at: finalCursor)
    }

    private func applyVisualPaste(count: Int?) {
        guard let selection = currentVisualSelection() else {
            enterNormalModeFromVisual(at: normalCursorPosition)
            return
        }

        let text = string as NSString
        let beforeCursor = normalCursorPosition
        guard let payload = VimPasteboard.read() else {
            enterNormalModeFromVisual(at: selection.range.location)
            return
        }
        guard let paste = VimPasteResolver.replaceSelectionResult(
            for: payload,
            replacing: selection,
            count: count
        ) else {
            enterNormalModeFromVisual(at: selection.range.location)
            return
        }

        let pasteEdit = textEdit(
            in: paste.range,
            replacementString: paste.replacementString,
            from: text
        )
        guard performTextChange(in: paste.range, replacementString: paste.replacementString) else {
            return
        }

        vimEngine.setPreferredColumn(nil)

        let updatedText = string as NSString
        let finalCursor = paste.linewise
            ? linewiseCursorPosition(afterDeletingAt: paste.cursorAnchor, in: updatedText)
            : characterwiseCursorPosition(afterDeletingAt: paste.cursorAnchor, in: updatedText)

        normalCursorPosition = finalCursor
        activeUndoHistory?.commitImmediateEdits(
            [pasteEdit],
            beforeCursorPosition: beforeCursor,
            afterCursorPosition: finalCursor
        )
        enterNormalModeFromVisual(at: finalCursor)
    }

    private func applyDelete(_ selection: VimSelectionResult, beforeCursorPosition: Int) {
        let text = string as NSString
        let deleteEdit = textEdit(
            in: selection.range,
            replacementString: "",
            from: text
        )
        guard performTextChange(in: selection.range, replacementString: "") else { return }

        writeSelectionToPasteboard(
            text: deleteEdit.removedText,
            linewise: selection.linewise
        )
        vimEngine.setPreferredColumn(nil)

        let updatedText = string as NSString
        let finalCursor = selection.linewise
            ? linewiseCursorPosition(afterDeletingAt: selection.cursorAnchor, in: updatedText)
            : characterwiseCursorPosition(afterDeletingAt: selection.cursorAnchor, in: updatedText)

        normalCursorPosition = finalCursor
        setSelectedRange(NSRange(location: min(finalCursor, updatedText.length), length: 0))
        drawNormalCursor()
        activeUndoHistory?.commitImmediateEdits(
            [deleteEdit],
            beforeCursorPosition: beforeCursorPosition,
            afterCursorPosition: finalCursor
        )
    }

    private func applyChange(_ selection: VimSelectionResult, beforeCursorPosition: Int) {
        let text = string as NSString
        let change = VimChangeResolver.changeResult(
            replacing: selection,
            in: text,
            from: selection.cursorAnchor
        )
        let changeEdit =
            change.range.map {
                textEdit(
                    in: $0,
                    replacementString: change.replacementString,
                    from: text
                )
            }

        if let range = change.range {
            guard performTextChange(in: range, replacementString: change.replacementString) else {
                return
            }
        }

        if let clipboardPayload = change.clipboardPayload {
            writeSelectionToPasteboard(payload: clipboardPayload)
        }

        if let changeEdit {
            activeUndoHistory?.beginInsertSession(beforeCursorPosition: beforeCursorPosition)
            activeUndoHistory?.appendEditToActiveInsertSession(changeEdit)
        }

        vimEngine.setPreferredColumn(nil)
        enterInsertMode(at: change.insertionLocation)
    }

    private func applyYank(_ selection: VimSelectionResult) {
        let text = string as NSString
        let selectedText = text.substring(with: selection.range)
        writeSelectionToPasteboard(
            payload: VimPastePayload(
                text: selectedText,
                style: selection.linewise ? .linewise : .characterwise
            )
        )
    }

    private func resolvedSelection(
        for target: VimOperatorTarget,
        from position: Int
    ) -> VimSelectionResult? {
        VimSelectionResolver.selectionResult(
            for: target,
            in: string as NSString,
            from: position,
            preferredColumn: vimEngine.sessionState.preferredColumn
        )
    }

    private func applyPaste(_ placement: VimPastePlacement, count: Int?) {
        guard let payload = VimPasteboard.read() else { return }

        let text = string as NSString
        let beforeCursor = normalCursorPosition
        guard let paste = VimPasteResolver.pasteResult(
            for: payload,
            placement: placement,
            count: count,
            in: text,
            from: normalCursorPosition
        ) else {
            return
        }

        let pasteEdit = textEdit(
            in: paste.range,
            replacementString: paste.replacementString,
            from: text
        )
        guard performTextChange(in: paste.range, replacementString: paste.replacementString) else {
            return
        }

        vimEngine.setPreferredColumn(nil)

        let updatedText = string as NSString
        let finalCursor = paste.linewise
            ? linewiseCursorPosition(afterDeletingAt: paste.cursorAnchor, in: updatedText)
            : characterwiseCursorPosition(afterDeletingAt: paste.cursorAnchor, in: updatedText)

        normalCursorPosition = finalCursor
        setSelectedRange(NSRange(location: min(finalCursor, updatedText.length), length: 0))
        drawNormalCursor()
        activeUndoHistory?.commitImmediateEdits(
            [pasteEdit],
            beforeCursorPosition: beforeCursor,
            afterCursorPosition: finalCursor
        )
    }

    private func applyUndo(count: Int?) {
        applyUndoNavigation(
            activeUndoHistory?.undo(count: max(count ?? 1, 1))
        )
    }

    private func applyRedo(count: Int?) {
        applyUndoNavigation(
            activeUndoHistory?.redo(count: max(count ?? 1, 1))
        )
    }

    private func applyUndoNavigation(_ navigationResult: VimUndoNavigationResult?) {
        guard let navigationResult else { return }

        replaceEntireTextWithUndoCaptureSuppressed(navigationResult.text)
        vimEngine.clearPendingInput()
        vimEngine.setPreferredColumn(nil)
        visualAnchorPosition = nil
        vimEngine.setMode(.normal)

        if mode != .normal {
            mode = .normal
        }

        let updatedText = string as NSString
        let finalCursor = updatedText.length > 0
            ? max(0, min(navigationResult.cursorPosition, updatedText.length - 1))
            : 0

        normalCursorPosition = finalCursor
        setSelectedRange(NSRange(location: min(finalCursor, updatedText.length), length: 0))
        drawNormalCursor()
    }

    private func writeSelectionToPasteboard(text: String, linewise: Bool) {
        writeSelectionToPasteboard(
            payload: VimPastePayload(
                text: text,
                style: linewise ? .linewise : .characterwise
            )
        )
    }

    private func writeSelectionToPasteboard(payload: VimPastePayload) {
        VimPasteboard.write(payload)
    }

    private func characterwiseCursorPosition(afterDeletingAt anchor: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        let clamped = max(0, min(anchor, text.length - 1))
        if text.character(at: clamped) == 0x0A && clamped > 0 {
            let lineRange = text.lineRange(for: NSRange(location: clamped, length: 0))
            if clamped > lineRange.location {
                return clamped - 1
            }
        }

        return clamped
    }

    private func linewiseCursorPosition(afterDeletingAt anchor: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        let clamped = max(0, min(anchor, text.length - 1))
        let lineRange = text.lineRange(for: NSRange(location: clamped, length: 0))
        return firstNonBlank(in: lineRange, text: text)
    }

    private func textEdit(
        in range: NSRange,
        replacementString: String,
        from text: NSString
    ) -> VimTextEdit {
        VimTextEdit(
            location: range.location,
            removedText: text.substring(with: range),
            insertedText: replacementString
        )
    }

    private func performTextChange(in range: NSRange, replacementString: String) -> Bool {
        guard let textStorage else { return false }

        let wasEditable = isEditable
        if !wasEditable {
            isEditable = true
        }
        defer {
            if !wasEditable {
                isEditable = false
            }
        }

        guard shouldChangeText(in: range, replacementString: replacementString) else {
            return false
        }

        textStorage.replaceCharacters(in: range, with: replacementString)
        didChangeText()
        return true
    }

    private func captureInsertEditIfNeeded(
        in affectedCharRange: NSRange,
        replacementString: String
    ) {
        guard !suppressUndoCapture else { return }
        guard mode == .insert else { return }
        guard let activeUndoHistory else { return }
        guard affectedCharRange.location != NSNotFound else { return }

        let text = string as NSString
        guard NSMaxRange(affectedCharRange) <= text.length else { return }

        activeUndoHistory.appendEditToActiveInsertSession(
            textEdit(
                in: affectedCharRange,
                replacementString: replacementString,
                from: text
            )
        )
    }

    private func replaceEntireTextWithUndoCaptureSuppressed(_ text: String) {
        guard string != text else { return }

        suppressUndoCapture = true
        defer { suppressUndoCapture = false }

        let existingText = string as NSString
        _ = performTextChange(
            in: NSRange(location: 0, length: existingText.length),
            replacementString: text
        )
    }

    private func finalizeActiveInsertSessionIfNeeded() {
        guard activeUndoHistory?.hasActiveInsertSession == true else { return }
        activeUndoHistory?.commitInsertSession(
            finalCursorPosition: committedNormalCursorPosition()
        )
    }

    private func committedNormalCursorPosition() -> Int {
        let text = string as NSString
        guard text.length > 0 else { return 0 }

        let sourcePosition = mode == .insert
            ? selectedRange().location
            : normalCursorPosition
        var finalCursor = max(0, min(sourcePosition, text.length - 1))

        if sourcePosition > 0 && sourcePosition < text.length {
            let lineRange = text.lineRange(for: NSRange(location: sourcePosition, length: 0))
            if sourcePosition == NSMaxRange(lineRange) - 1
                && text.character(at: sourcePosition) == 0x0A
                && sourcePosition > lineRange.location
            {
                finalCursor = sourcePosition - 1
            }
        }

        return finalCursor
    }

    private func publishVimState() {
        vimDelegate?.vimTextView(
            self,
            didChangeStatus: vimEngine.sessionState.statusPresentation
        )
        vimDelegate?.vimTextView(
            self,
            didChangeHintCandidate: currentHintCandidate()
        )
    }

    private func currentHintCandidate() -> VimHintCandidate? {
        guard mode == .normal else { return nil }

        if isShowingRootHintCatalog {
            return vimEngine.rootHintCandidate()
        }

        return vimEngine.hintCandidate
    }

    private func mouseTargetPosition(for event: NSEvent) -> Int? {
        let text = string as NSString
        guard text.length > 0 else { return 0 }
        guard let layoutManager, let textContainer else { return nil }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return min(characterIndex, text.length - 1)
    }

    private func keyPress(for event: NSEvent) -> VimKeyPress? {
        switch event.keyCode {
        case 53:
            return .special(.escape)
        case 117:
            return .special(.forwardDelete)
        case 123:
            return .special(.leftArrow)
        case 124:
            return .special(.rightArrow)
        case 125:
            return .special(.downArrow)
        case 126:
            return .special(.upArrow)
        default:
            break
        }

        guard let chars = event.characters, let char = chars.first else { return nil }

        if let scalar = chars.unicodeScalars.first {
            switch scalar.value {
            case 0x12:
                return .special(.ctrlR)
            case 0x15:
                return .special(.ctrlU)
            case 0x04:
                return .special(.ctrlD)
            case 0x02:
                return .special(.ctrlB)
            case 0x06:
                return .special(.ctrlF)
            default:
                break
            }
        }

        return .character(char)
    }
}

// MARK: - Delegate Protocol

protocol VimTextViewDelegate: AnyObject {
    func vimTextView(_ textView: VimTextView, didChangeMode mode: VimMode)
    func vimTextView(_ textView: VimTextView, didChangeStatus status: VimStatusPresentation)
    func vimTextView(_ textView: VimTextView, didChangeHintCandidate candidate: VimHintCandidate?)
}
