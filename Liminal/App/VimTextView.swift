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

    /// Mark indicators to paint as colored dots above their characters.
    /// Coordinator owns the anchor → utf16 location conversion and pushes
    /// this list whenever the registry changes. The view just paints what
    /// it's given.
    var markPositions: [MarkIndicator] = [] {
        didSet {
            guard oldValue != markPositions else { return }
            needsDisplay = true
        }
    }

    struct MarkIndicator: Equatable {
        let utf16Location: Int
        let letter: Character
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkIndicators(in: dirtyRect)
    }

    private func drawMarkIndicators(in dirtyRect: NSRect) {
        guard !markPositions.isEmpty,
              let layoutManager,
              let textContainer
        else { return }

        // Group marks by glyph position so multiple marks at the same
        // location stack in a grid instead of overlapping.
        let grouped = Dictionary(grouping: markPositions) { $0.utf16Location }
        let flipped = isFlipped

        for (location, indicators) in grouped {
            guard let baseRect = markIndicatorGlyphRect(
                forUTF16Location: location,
                layoutManager: layoutManager,
                textContainer: textContainer
            ) else { continue }

            // Stable visual order: sort by letter so the same mark always
            // lands in the same grid slot regardless of dictionary order.
            let sortedIndicators = indicators.sorted { $0.letter < $1.letter }
            guard let layout = MarkDotLayout.layout(
                forCount: sortedIndicators.count,
                anchoredTo: baseRect,
                flipped: flipped
            ) else { continue }

            guard layout.bounds.intersects(dirtyRect) else { continue }

            for (rect, indicator) in zip(layout.dotRects, sortedIndicators) {
                let color = VimMarkPalette.color(for: indicator.letter)
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    /// Map a UTF-16 location to the on-screen glyph rect (in view
    /// coordinates). Mirrors the reference's `markIndicatorGlyphRect`:
    /// uses NSLayoutManager bounding-rect APIs, falls back to the line
    /// fragment's used rect for empty-glyph positions, and offsets by
    /// `textContainerOrigin` for view space.
    private func markIndicatorGlyphRect(
        forUTF16Location location: Int,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        let text = string as NSString
        guard text.length > 0 else { return nil }

        let clampedLocation = max(0, min(location, text.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedLocation)
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
        return glyphRect.offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
    }

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

        if let special = Self.specialKey(forKeyCode: event.keyCode) {
            self.init(payload: .special(special), modifiers: modifiers)
            return
        }

        guard let raw = event.charactersIgnoringModifiers,
              let scalar = raw.unicodeScalars.first,
              let character = Character(String(scalar)) as Character?
        else { return nil }

        if character == " " {
            self.init(payload: .special(.space), modifiers: modifiers)
            return
        }

        // Shift is already encoded in the character ("A" vs "a", "$" vs "4")
        // for printable keys, so dropping it here keeps bindings simple —
        // `.char("$")` matches Shift+4 without callers having to write
        // `.char("$", modifiers: [.shift])`. Shift stays meaningful on
        // special keys (e.g. <S-Tab>) where it's not folded into the
        // character payload.
        var charModifiers = modifiers
        charModifiers.remove(.shift)
        self.init(payload: .character(character), modifiers: charModifiers)
    }

    private static func specialKey(forKeyCode keyCode: UInt16) -> SpecialKey? {
        switch keyCode {
        case 53:  return .escape
        case 36:  return .returnKey
        case 76:  return .returnKey
        case 48:  return .tab
        case 51:  return .backspace
        case 117: return .delete
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default:  return nil
        }
    }
}
