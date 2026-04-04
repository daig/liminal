import AppKit

/// NSTextView subclass that implements vim-style modal editing.
///
/// Uses `NSEvent.characters` for key matching, which respects the active
/// keyboard layout (Colemak, Dvorak, etc.) — the character that *would* be
/// typed in insert mode is the one matched in normal mode.
final class VimTextView: NSTextView {

    weak var vimDelegate: VimTextViewDelegate?

    private let vimEngine = VimEngine()

    /// Cursor position tracked independently in normal mode.
    private var normalCursorPosition: Int = 0

    private static let cursorHighlightKey = NSAttributedString.Key("vimCursorHighlight")
    private static let cursorColor = NSColor.systemOrange.withAlphaComponent(0.4)

    /// Current editing mode.
    private(set) var mode: VimMode = .normal {
        didSet {
            if mode != oldValue {
                updateModeAppearance()
                vimDelegate?.vimTextView(self, didChangeMode: mode)
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

    private func insertionPointPosition() -> Int {
        let length = (string as NSString).length
        return max(0, min(normalCursorPosition, length))
    }

    func loadDocumentText(_ text: String) {
        string = text
        normalCursorPosition = 0
        setSelectedRange(NSRange(location: 0, length: 0))
        vimEngine.reset()

        if mode != .normal {
            mode = .normal
        } else {
            updateModeAppearance()
        }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch mode {
        case .normal:
            handleNormalMode(event)
        case .insert:
            handleInsertMode(event)
        }
    }

    // MARK: - Insert Mode

    private func handleInsertMode(_ event: NSEvent) {
        // ESC → return to normal mode
        if keyPress(for: event) == .special(.escape) {
            enterNormalMode()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Normal Mode

    private func handleNormalMode(_ event: NSEvent) {
        guard let keyPress = keyPress(for: event) else { return }

        switch vimEngine.handle(keyPress) {
        case .handled(let command):
            apply(command)
        case .pending, .ignored:
            break
        }
    }

    // MARK: - Mode Transitions

    private func enterInsertMode() {
        vimEngine.setMode(.insert)
        mode = .insert
    }

    private func enterNormalMode() {
        vimEngine.setMode(.normal)
        mode = .normal
        // Nudge cursor back one if sitting on a newline (vim convention)
        let text = string as NSString
        let pos = normalCursorPosition
        if pos > 0 && pos < text.length {
            let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
            if pos == NSMaxRange(lineRange) - 1
                && text.character(at: pos) == 0x0A
                && pos > lineRange.location
            {
                normalCursorPosition = pos - 1
            }
        }
        drawNormalCursor()
    }

    private func apply(_ command: VimCommand) {
        switch command {
        case .enterInsertMode:
            enterInsertMode()
        case .move(let motion, let count):
            let navigationResult = VimNavigator.destination(
                for: motion,
                count: count,
                in: string as NSString,
                from: normalCursorPosition,
                preferredColumn: vimEngine.sessionState.preferredColumn
            )

            vimEngine.setPreferredColumn(navigationResult.preferredColumn)
            moveCursorTo(navigationResult.position)
        }
    }

    private func keyPress(for event: NSEvent) -> VimKeyPress? {
        switch event.keyCode {
        case 53:
            return .special(.escape)
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
        return .character(char)
    }
}

// MARK: - Delegate Protocol

protocol VimTextViewDelegate: AnyObject {
    func vimTextView(_ textView: VimTextView, didChangeMode mode: VimMode)
}
