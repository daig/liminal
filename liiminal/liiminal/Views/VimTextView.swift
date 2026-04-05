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

    private struct MarkIndicatorDot {
        let mark: Character
        let frame: CGRect
    }

    private struct MarkIndicatorLayout {
        let bounds: CGRect
        let dots: [MarkIndicatorDot]
    }

    private enum MouseDragState {
        case normalAnchor(position: Int, visualKind: VimVisualKind)
        case visualAdjusting
    }

    private var markTrackingArea: NSTrackingArea?

    weak var vimDelegate: VimTextViewDelegate?

    private let vimEngine = VimEngine()
    private var activeUndoHistory: VimUndoHistory?
    private var activeMarkStore: VimMarkStore?
    private var suppressUndoCapture = false
    private var isSynchronizingDocumentHeight = false
    private var isShowingRootHintCatalog = false
    private var mouseDragState: MouseDragState?
    private var currentCursorInfo: VimCursorInfoPresentation?
    private var visualState: VimVisualState? {
        didSet {
            if let visualState {
                normalCursorPosition = visualState.cursorPosition
            }
        }
    }

    /// Cursor position tracked independently in normal mode.
    private var normalCursorPosition: Int = 0

    private static let cursorHighlightKey = NSAttributedString.Key("vimCursorHighlight")
    private static let cursorColor = NSColor.systemOrange.withAlphaComponent(0.4)
    private static let markDotDiameter: CGFloat = 4.0
    private static let markDotGap: CGFloat = 2.0
    private static let markDotColumns = 3
    private static let markDotOffset: CGFloat = 1.5

    /// Current editing mode.
    private(set) var mode: VimMode = .normal {
        didSet {
            if mode != oldValue {
                if oldValue.isVisual && !mode.isVisual {
                    visualState = nil
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
        case .visual, .visualLine:
            isEditable = false
            clearNormalCursor()
            refreshMarkIndicators()
            let selectionRange = visualSelectionDisplayRange()
            setSelectedRange(selectionRange)
            refreshCursorInfo()
            ensureActiveCursorVisible()
        case .insert:
            clearNormalCursor()
            refreshMarkIndicators()
            // Place the real insertion point at the tracked position
            setSelectedRange(NSRange(location: insertionPointPosition(), length: 0))
            isEditable = true
            insertionPointColor = .textColor
            refreshCursorInfo()
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
        refreshMarkIndicators()

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

        refreshCursorInfo()
        ensureActiveCursorVisible()
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
        visualState = visualState?.movingHead(to: pos, in: text)

        let selectionRange = visualSelectionDisplayRange()
        setSelectedRange(selectionRange)
        refreshCursorInfo()
        ensureActiveCursorVisible()
    }

    private func insertionPointPosition() -> Int {
        let length = (string as NSString).length
        return max(0, min(normalCursorPosition, length))
    }

    private func visualSelectionDisplayRange() -> NSRange {
        visualState?.displayRange(in: string as NSString) ?? NSRange(location: 0, length: 0)
    }

    private func currentVisualSelection() -> VimSelectionResult? {
        let text = string as NSString
        guard text.length > 0 else { return nil }
        return visualState?.selection(in: text)
    }

    func loadDocumentText(
        _ text: String,
        undoHistory: VimUndoHistory,
        markStore: VimMarkStore
    ) {
        finalizeActiveInsertSessionIfNeeded()
        activeUndoHistory = undoHistory
        activeMarkStore = markStore
        isShowingRootHintCatalog = false
        mouseDragState = nil
        currentCursorInfo = nil
        toolTip = nil
        visualState = nil
        string = text
        normalCursorPosition = 0
        setSelectedRange(NSRange(location: 0, length: 0))
        vimEngine.reset()

        if mode != .normal {
            mode = .normal
        } else {
            updateModeAppearance()
        }

        synchronizeDocumentHeightToContent()
        refreshMarkIndicators()
        updateHoverTooltip(at: nil)
        publishVimState()
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalMode(event)
        case .visual, .visualLine:
            handleVisualMode(event)
        case .insert:
            handleInsertMode(event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkIndicators(in: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalModeMouseDown(event)
        case .visual, .visualLine:
            handleVisualModeMouseDown(event)
        case .insert:
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalModeMouseDragged(event)
        case .visual, .visualLine:
            handleVisualModeMouseDragged(event)
        case .insert:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragState = nil

        switch mode {
        case .insert:
            super.mouseUp(with: event)
        case .normal, .visual, .visualLine:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverTooltip(at: mouseTargetPosition(for: event, strictHitTesting: true))
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverTooltip(at: nil)
    }

    override func updateTrackingAreas() {
        if let markTrackingArea {
            removeTrackingArea(markTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        markTrackingArea = trackingArea

        super.updateTrackingAreas()
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
        captureMarkEditIfNeeded(
            in: affectedCharRange,
            replacementString: replacementString ?? ""
        )
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        synchronizeDocumentHeightToContent()
        refreshMarkIndicators()
        refreshHoverTooltipForCurrentMouseLocation()
        refreshCursorInfo()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.size.width - newSize.width) > 0.5
        super.setFrameSize(newSize)

        if widthChanged {
            synchronizeDocumentHeightToContent()
        }
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
        let hadPendingInput = vimEngine.sessionState.hasPendingInput

        guard let targetPosition = mouseTargetPosition(for: event) else {
            mouseDragState = nil
            publishVimState()
            return
        }

        if event.clickCount >= 3 && hadPendingInput == false {
            applyNormalModeTripleClick(at: targetPosition)
            publishVimState()
            return
        }

        if event.clickCount >= 2 && hadPendingInput == false {
            applyNormalModeDoubleClick(at: targetPosition)
            publishVimState()
            return
        }

        switch vimEngine.handleTargetPosition(targetPosition) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }

        mouseDragState = hadPendingInput ? nil : .normalAnchor(
            position: normalCursorPosition,
            visualKind: .characterwise
        )
        publishVimState()
    }

    private func applyNormalModeDoubleClick(at position: Int) {
        let text = string as NSString

        guard let selection = VimSelectionResolver.wordSelectionResult(in: text, at: position) else {
            moveCursorTo(position)
            mouseDragState = .normalAnchor(
                position: normalCursorPosition,
                visualKind: .characterwise
            )
            return
        }

        visualState = VimVisualState(
            kind: .characterwise,
            anchorPosition: selection.range.location,
            headPosition: NSMaxRange(selection.range) - 1
        )
        mouseDragState = .visualAdjusting
        vimEngine.clearPendingInput()
        vimEngine.setPreferredColumn(nil)
        vimEngine.setMode(.visual)
        mode = .visual
    }

    private func applyNormalModeTripleClick(at position: Int) {
        let text = string as NSString
        let clampedPosition: Int
        if text.length > 0 {
            clampedPosition = max(0, min(position, text.length - 1))
        } else {
            clampedPosition = 0
        }

        visualState = VimVisualState(
            kind: .linewise,
            anchorPosition: clampedPosition,
            headPosition: clampedPosition
        )
        mouseDragState = .visualAdjusting
        vimEngine.clearPendingInput()
        vimEngine.setPreferredColumn(nil)
        vimEngine.setMode(.visualLine)
        mode = .visualLine
    }

    private func handleNormalModeMouseDragged(_ event: NSEvent) {
        guard case .normalAnchor(let anchorPosition, let visualKind) = mouseDragState else { return }
        guard let targetPosition = mouseTargetPosition(for: event) else { return }
        guard targetPosition != anchorPosition else { return }

        enterVisualMode(visualKind)
        moveVisualCursorTo(targetPosition)
        mouseDragState = .visualAdjusting
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
            mouseDragState = nil
            publishVimState()
            return
        }

        if event.clickCount >= 3 {
            enterNormalModeFromVisual(at: targetPosition)
            applyNormalModeTripleClick(at: targetPosition)
            publishVimState()
            return
        }

        if event.clickCount >= 2 {
            enterNormalModeFromVisual(at: targetPosition)
            applyNormalModeDoubleClick(at: targetPosition)
            publishVimState()
            return
        }

        enterNormalModeFromVisual(at: targetPosition)
        mouseDragState = .normalAnchor(
            position: normalCursorPosition,
            visualKind: .characterwise
        )
        publishVimState()
    }

    private func handleVisualModeMouseDragged(_ event: NSEvent) {
        guard case .visualAdjusting = mouseDragState else { return }
        guard let targetPosition = mouseTargetPosition(for: event) else { return }

        moveVisualCursorTo(targetPosition)
        publishVimState()
    }

    // MARK: - Mode Transitions

    private func enterInsertMode(at insertionPosition: Int? = nil) {
        mouseDragState = nil
        visualState = nil
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
        mouseDragState = nil
        vimEngine.setMode(.normal)
        mode = .normal
        normalCursorPosition = committedNormalCursorPosition()
        drawNormalCursor()
        activeUndoHistory?.commitInsertSession(
            finalCursorPosition: normalCursorPosition,
            markSnapshot: currentMarkSnapshot()
        )
    }

    private func enterVisualMode(_ kind: VimVisualKind) {
        let text = string as NSString
        if mode.isVisual, let visualState {
            self.visualState = visualState.changingKind(to: kind, in: text)
        } else {
            visualState = VimVisualState.begin(
                kind: kind,
                at: normalCursorPosition,
                in: text
            )
        }

        let visualMode = visualState?.mode ?? kind.mode
        vimEngine.setMode(visualMode)
        mode = visualMode
    }

    private func enterNormalModeFromVisual(at cursorPosition: Int) {
        let text = string as NSString
        let clampedCursor = text.length > 0
            ? max(0, min(cursorPosition, text.length - 1))
            : 0

        mouseDragState = nil
        visualState = nil
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
        case .setMark(let name):
            applySetMark(name)
        case .enterVisual(let kind):
            enterVisualMode(kind)
        case .exitVisual:
            enterNormalModeFromVisual(at: normalCursorPosition)
        case .scrollCursorLine(let placement):
            VimViewportController.alignCursorLine(
                at: currentViewportCursorPosition(),
                to: placement,
                in: self
            )
        case .enterInsert(let transition):
            applyInsertTransition(transition)
        case .moveText(let motion, let count):
            let navigationResult = VimNavigator.destination(
                for: motion,
                count: count,
                in: string as NSString,
                from: normalCursorPosition,
                preferredColumn: vimEngine.sessionState.preferredColumn,
                markResolver: currentMarkResolver(in: string as NSString)
            )

            vimEngine.setPreferredColumn(navigationResult.preferredColumn)
            if mode.isVisual {
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
            if mode.isVisual {
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

    private func applyDelete(_ target: VimOperatorArgument) {
        guard let selection = resolvedSelection(for: target, from: normalCursorPosition) else {
            return
        }

        applyDelete(selection, beforeCursorPosition: normalCursorPosition)
    }

    private func applyChange(_ target: VimOperatorArgument) {
        guard let selection = resolvedSelection(for: target, from: normalCursorPosition) else {
            return
        }

        applyChange(selection, beforeCursorPosition: normalCursorPosition)
    }

    private func applyYank(_ target: VimOperatorArgument) {
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
        visualState = nil
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
            afterCursorPosition: finalCursor,
            markSnapshot: currentMarkSnapshot()
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
        if mode == .normal {
            drawNormalCursor()
        }
        activeUndoHistory?.commitImmediateEdits(
            [deleteEdit],
            beforeCursorPosition: beforeCursorPosition,
            afterCursorPosition: finalCursor,
            markSnapshot: currentMarkSnapshot()
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
        for target: VimOperatorArgument,
        from position: Int
    ) -> VimSelectionResult? {
        guard let resolvedTarget = VimOperatorArgumentResolver.resolvedTarget(
            for: target,
            in: string as NSString,
            from: position,
            preferredColumn: vimEngine.sessionState.preferredColumn,
            markResolver: currentMarkResolver(in: string as NSString)
        ) else {
            return nil
        }

        switch resolvedTarget {
        case .text(let selection):
            return selection
        }
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
            afterCursorPosition: finalCursor,
            markSnapshot: currentMarkSnapshot()
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
        mouseDragState = nil
        vimEngine.clearPendingInput()
        vimEngine.setPreferredColumn(nil)
        visualState = nil
        vimEngine.setMode(.normal)

        if mode != .normal {
            mode = .normal
        }

        let updatedText = string as NSString
        let finalCursor = updatedText.length > 0
            ? max(0, min(navigationResult.cursorPosition, updatedText.length - 1))
            : 0

        activeMarkStore?.restore(navigationResult.markSnapshot)
        normalCursorPosition = finalCursor
        setSelectedRange(NSRange(location: min(finalCursor, updatedText.length), length: 0))
        drawNormalCursor()
        refreshHoverTooltipForCurrentMouseLocation()
    }

    private func currentViewportCursorPosition() -> Int {
        if let visualState {
            return visualState.cursorPosition
        }
        return normalCursorPosition
    }

    private func ensureActiveCursorVisible() {
        VimViewportController.ensurePositionVisible(currentViewportCursorPosition(), in: self)
    }

    private func synchronizeDocumentHeightToContent() {
        guard !isSynchronizingDocumentHeight else { return }
        guard let layoutManager, let textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let minimumHeight = enclosingScrollView?.contentView.bounds.height ?? bounds.height
        let targetHeight = max(
            ceil(usedRect.height + (textContainerOrigin.y * 2)),
            minimumHeight
        )

        guard abs(frame.size.height - targetHeight) > 0.5 else { return }

        isSynchronizingDocumentHeight = true
        defer { isSynchronizingDocumentHeight = false }
        super.setFrameSize(NSSize(width: frame.size.width, height: targetHeight))
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

    private func applySetMark(_ name: Character) {
        let text = string as NSString
        guard activeMarkStore?.setLocalMark(named: name, at: normalCursorPosition, in: text) == true else {
            return
        }

        refreshMarkIndicators()
        refreshHoverTooltipForCurrentMouseLocation()
        refreshCursorInfo()
        activeUndoHistory?.updateCurrentMarkSnapshot(currentMarkSnapshot())
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

    private func captureMarkEditIfNeeded(
        in affectedCharRange: NSRange,
        replacementString: String
    ) {
        guard let activeMarkStore else { return }
        guard affectedCharRange.location != NSNotFound else { return }

        let text = string as NSString
        guard NSMaxRange(affectedCharRange) <= text.length else { return }

        activeMarkStore.apply(
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
            finalCursorPosition: committedNormalCursorPosition(),
            markSnapshot: currentMarkSnapshot()
        )
    }

    private func currentMarkSnapshot() -> VimMarkSnapshot {
        activeMarkStore?.snapshot() ?? .empty
    }

    private func currentMarkResolver(in text: NSString) -> VimMarkResolver {
        { [weak self] name in
            self?.activeMarkStore?.position(of: name, in: text)
        }
    }

    private func refreshMarkIndicators() {
        needsDisplay = true
    }

    private func drawMarkIndicators(in dirtyRect: NSRect) {
        let text = string as NSString
        guard text.length > 0 else { return }
        guard let layoutManager, let textContainer else { return }
        guard let groupedMarks = activeMarkStore?.groupedMarksByPosition(in: text) else { return }

        for (position, marks) in groupedMarks {
            guard
                let indicatorLayout = markIndicatorLayout(
                    for: position,
                    marks: marks,
                    in: text,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                ),
                indicatorLayout.bounds.intersects(dirtyRect)
            else {
                continue
            }

            for dot in indicatorLayout.dots {
                let tint = VimMarkPalette.tint(for: dot.mark)
                let color = NSColor(
                    calibratedHue: tint.hue,
                    saturation: tint.saturation,
                    brightness: tint.brightness,
                    alpha: 0.92
                )

                color.setFill()
                NSBezierPath(ovalIn: dot.frame).fill()
            }
        }
    }

    private func marksAtPosition(_ position: Int?) -> [Character] {
        guard let position else { return [] }
        let text = string as NSString
        guard text.length > 0 else { return [] }
        return activeMarkStore?.groupedMarksByPosition(in: text)[position] ?? []
    }

    private func updateHoverTooltip(at position: Int?) {
        let marks = marksAtPosition(position)
        toolTip = marks.isEmpty ? nil : markTooltipText(for: marks)
    }

    private func refreshHoverTooltipForCurrentMouseLocation() {
        guard let window else {
            updateHoverTooltip(at: nil)
            return
        }

        let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(localPoint) else {
            updateHoverTooltip(at: nil)
            return
        }

        updateHoverTooltip(at: mouseTargetPosition(for: localPoint, strictHitTesting: true))
    }

    private func refreshCursorInfo() {
        let info = currentCursorInfoPosition().flatMap(cursorInfo(at:))
        guard info != currentCursorInfo else { return }
        currentCursorInfo = info
        vimDelegate?.vimTextView(self, didChangeCursorInfo: info)
    }

    private func currentCursorInfoPosition() -> Int? {
        let text = string as NSString
        guard text.length > 0 else { return nil }

        switch mode {
        case .normal:
            return max(0, min(normalCursorPosition, text.length - 1))
        case .visual, .visualLine:
            guard let visualState else { return nil }
            return max(0, min(visualState.cursorPosition, text.length - 1))
        case .insert:
            return nil
        }
    }

    private func cursorInfo(at position: Int) -> VimCursorInfoPresentation? {
        let marks = marksAtPosition(position)
        guard !marks.isEmpty else { return nil }

        return VimCursorInfoPresentation(
            sectionTitle: "MARKS",
            items: marks.map {
                VimCursorInfoItem(label: String($0), tint: VimMarkPalette.tint(for: $0))
            }
        )
    }

    private func mouseTargetPosition(
        for point: NSPoint,
        strictHitTesting: Bool = false
    ) -> Int? {
        let text = string as NSString
        guard text.length > 0 else { return nil }
        guard let layoutManager, let textContainer else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = min(layoutManager.characterIndexForGlyph(at: glyphIndex), text.length - 1)
        if strictHitTesting {
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            let viewRect = glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            var hitRect = viewRect.insetBy(dx: -2, dy: -1)

            let marks = activeMarkStore?.groupedMarksByPosition(in: text)[characterIndex] ?? []
            if
                !marks.isEmpty,
                let indicatorLayout = markIndicatorLayout(
                    for: characterIndex,
                    marks: marks,
                    in: text,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                )
            {
                hitRect = hitRect.union(indicatorLayout.bounds.insetBy(dx: -1, dy: -1))
            }

            if !hitRect.contains(point) {
                return nil
            }
        }
        return characterIndex
    }

    private func markTooltipText(for marks: [Character]) -> String {
        let labels = marks.map(String.init).joined(separator: ", ")
        return marks.count == 1 ? "Mark \(labels)" : "Marks \(labels)"
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
        let hintContext = currentHintContext()

        if isShowingRootHintCatalog {
            return vimEngine.rootHintCandidate(in: hintContext)
        }

        return vimEngine.hintCandidate(in: hintContext)
    }

    private func currentHintContext() -> VimHintContext {
        let text = string as NSString
        let localMarkItems = activeMarkStore?.resolvedLocalMarks(in: text).map { mark in
            VimHintItem(
                key: String(mark.name),
                description: "Saved position",
                kind: .argument,
                tint: VimMarkPalette.tint(for: mark.name)
            )
        } ?? []

        return VimHintContext(
            dynamicOptions: [
                .localMarks: localMarkItems
            ]
        )
    }

    private func mouseTargetPosition(
        for event: NSEvent,
        strictHitTesting: Bool = false
    ) -> Int? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return mouseTargetPosition(for: viewPoint, strictHitTesting: strictHitTesting)
    }

    private func markIndicatorLayout(
        for position: Int,
        marks: [Character],
        in text: NSString,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> MarkIndicatorLayout? {
        guard !marks.isEmpty else { return nil }
        guard let glyphRect = markIndicatorGlyphRect(
            for: position,
            in: text,
            layoutManager: layoutManager,
            textContainer: textContainer
        ) else {
            return nil
        }

        let rows = stride(from: 0, to: marks.count, by: Self.markDotColumns).map {
            Array(marks[$0..<min($0 + Self.markDotColumns, marks.count)])
        }
        var dots: [MarkIndicatorDot] = []
        var bounds = CGRect.null

        for (rowIndex, rowMarks) in rows.enumerated() {
            let rowWidth =
                CGFloat(rowMarks.count) * Self.markDotDiameter
                + CGFloat(max(0, rowMarks.count - 1)) * Self.markDotGap
            let rowOriginX = glyphRect.midX - (rowWidth / 2)

            let rowOriginY: CGFloat
            if isFlipped {
                rowOriginY =
                    glyphRect.maxY + Self.markDotOffset
                    + CGFloat(rowIndex) * (Self.markDotDiameter + Self.markDotGap)
            } else {
                rowOriginY =
                    glyphRect.minY - Self.markDotOffset - Self.markDotDiameter
                    - CGFloat(rowIndex) * (Self.markDotDiameter + Self.markDotGap)
            }

            for (columnIndex, mark) in rowMarks.enumerated() {
                let frame = CGRect(
                    x: rowOriginX + CGFloat(columnIndex) * (Self.markDotDiameter + Self.markDotGap),
                    y: rowOriginY,
                    width: Self.markDotDiameter,
                    height: Self.markDotDiameter
                )
                dots.append(MarkIndicatorDot(mark: mark, frame: frame))
                bounds = bounds.union(frame)
            }
        }

        return MarkIndicatorLayout(bounds: bounds, dots: dots)
    }

    private func markIndicatorGlyphRect(
        for position: Int,
        in text: NSString,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGRect? {
        guard text.length > 0 else { return nil }

        let clampedPosition = max(0, min(position, text.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedPosition)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        var glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )

        if glyphRect.isEmpty {
            let lineUsedRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            glyphRect = CGRect(
                x: max(lineUsedRect.minX, lineUsedRect.maxX - 1),
                y: lineUsedRect.minY,
                width: 1,
                height: lineUsedRect.height
            )
        }

        return glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
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
    func vimTextView(_ textView: VimTextView, didChangeCursorInfo info: VimCursorInfoPresentation?)
}
