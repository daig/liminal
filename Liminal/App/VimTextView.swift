import AppKit

/// NSTextView subclass that routes keys through a `VimController` in
/// Normal mode and behaves like a stock NSTextView in Insert mode.
///
/// Key interception rules:
/// - `keyDown(with:)`: in marked-text composition (IME), pass through.
///   Otherwise translate the event to `VimKey` and ask the controller;
///   `.consumed` → swallow the event, `.passthrough` → forward to super.
/// - `insertText(_:replacementRange:)`: only forwards in Insert mode.
///   Belt-and-suspenders against any code path that bypasses keyDown
///   (drag/drop, programmatic insert).
final class VimTextView: NSTextView {
    weak var vimController: VimController?

    override func keyDown(with event: NSEvent) {
        // IME / dead-key composition: NSTextView's keyDown fires before
        // the composed character is committed. Let it through so IME
        // works in Insert mode.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        guard let controller = vimController else {
            super.keyDown(with: event)
            return
        }

        guard let key = VimKey(event: event) else {
            super.keyDown(with: event)
            return
        }

        switch controller.handle(key) {
        case .consumed:
            return
        case .passthrough:
            super.keyDown(with: event)
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard vimController?.mode == .insert else { return }
        super.insertText(string, replacementRange: replacementRange)
    }
}

extension VimKey {
    /// Build a `VimKey` from an AppKit `NSEvent`. Returns nil for events
    /// that don't carry a meaningful keypress (purely modifier-only
    /// presses, etc.) — those should fall through to NSTextView's normal
    /// handling.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option)  { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }

        // Special keys by keyCode (consistent across keyboard layouts).
        // NSEvent.keyCode is the physical key location.
        if let special = Self.specialKey(forKeyCode: event.keyCode) {
            self.init(payload: .special(special), modifiers: modifiers)
            return
        }

        // Printable / Ctrl-letter combinations: use charactersIgnoringModifiers
        // so `J` and `j` differ only by the shift modifier, and vim
        // bindings match the physical key.
        guard let raw = event.charactersIgnoringModifiers,
              let scalar = raw.unicodeScalars.first,
              let character = Character(String(scalar)) as Character?
        else { return nil }

        // Map literal space to .special(.space) for consistent hint display.
        if character == " " {
            self.init(payload: .special(.space), modifiers: modifiers)
            return
        }

        self.init(payload: .character(character), modifiers: modifiers)
    }

    private static func specialKey(forKeyCode keyCode: UInt16) -> SpecialKey? {
        switch keyCode {
        case 53:  return .escape
        case 36:  return .returnKey      // Return
        case 76:  return .returnKey      // Numpad Enter
        case 48:  return .tab
        case 51:  return .backspace
        case 117: return .delete         // Forward delete
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default:  return nil
        }
    }
}
