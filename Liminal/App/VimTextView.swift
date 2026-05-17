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

    /// Receives Cmd-click activations. The Coordinator implements this;
    /// when it returns `true`, the view considers the click handled and
    /// does NOT fall through to NSTextView's normal cursor-placement /
    /// drag-tracking behavior.
    weak var linkActivationDelegate: VimTextViewLinkActivationDelegate?

    /// Receives Cmd-modifier and mouse-move events for the hover
    /// preview popover. Idle hover cost is one bool check inside the
    /// delegate (gated on Cmd-held), so the per-frame overhead of
    /// having `mouseMoved` enabled at all is negligible.
    weak var linkHoverDelegate: VimTextViewLinkHoverDelegate?

    private var hoverTrackingArea: NSTrackingArea?

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

    /// UTF-16 ranges covered by the active visual CST forest selection.
    /// The Coordinator pushes this whenever the forest changes (entry,
    /// navigation, extend) and clears it on mode exit. Drawn as a
    /// translucent rounded-rect background under the glyphs in the
    /// ranges — visually distinct from AppKit's native text selection
    /// so users can tell structural selection (`gC`) from `v`/`V`/
    /// `<C-v>` at a glance.
    ///
    /// Independent of `selectedRange`: the CST overlay is painted in
    /// `draw(_:)` regardless of system selection state, and the system
    /// caret is parked at the head edge of the forest so users can see
    /// which end will move when they press `J`/`K` or apply an
    /// extending motion.
    var cstSelectionRanges: [NSRange] = [] {
        didSet {
            guard oldValue != cstSelectionRanges else { return }
            needsDisplay = true
        }
    }

    /// Marker for which end of `cstSelectionRanges` is the head — the
    /// moving end under `J` / `K` / extending motions, swapped by `o`.
    /// `nil` when the selection is a singleton (no meaningful end
    /// distinction) or when not in `.visualCST`.
    var cstHeadEdge: CSTHeadEdge? {
        didSet {
            guard oldValue != cstHeadEdge else { return }
            needsDisplay = true
        }
    }

    /// Where to paint the head accent. `headRange` is the UTF-16 range
    /// of the head's child specifically (not the whole forest); `edge`
    /// picks which side of that range to draw the bar on.
    struct CSTHeadEdge: Equatable {
        let headRange: NSRange
        let edge: Edge

        enum Edge: Equatable { case leading, trailing }
    }

    struct MarkIndicator: Equatable {
        let utf16Location: Int
        let letter: Character
    }

    /// One in-editor forest-mark indicator: a UTF-16 range covering the
    /// marked subtree plus the letter (drives color) and resolution
    /// strength (drives alpha — `.recovered` paints dimmer than
    /// `.strong`).
    struct ForestMarkOverlay: Equatable {
        let range: NSRange
        let letter: Character
        let strength: ForestMarkStrength
    }

    var forestMarkOverlays: [ForestMarkOverlay] = [] {
        didSet {
            guard oldValue != forestMarkOverlays else { return }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Forest mark outlines first — they're the most ambient layer.
        // CST selection + head accent paint on top so the live selection
        // is always the dominant visual.
        drawForestMarkOverlays(in: dirtyRect)
        drawCSTSelectionOverlay(in: dirtyRect)
        drawCSTHeadAccent(in: dirtyRect)
        drawMarkIndicators(in: dirtyRect)
    }

    /// Paint translucent rounded-rect backgrounds over every line
    /// fragment covered by `cstSelectionRanges`. Drawn after `super.draw`
    /// (i.e. on top of glyphs), with low alpha so the underlying text
    /// stays legible — same effect as a highlighter pen.
    ///
    /// Uses `enumerateEnclosingRects(forGlyphRange:withinSelectedGlyphRange:in:_:)`
    /// so multi-line forests render as one rectangle per line (matching
    /// the natural reading shape) rather than a bounding rect that
    /// would also cover gutter space at line ends.
    private func drawCSTSelectionOverlay(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer
        else { return }

        let color = NSColor.systemTeal.withAlphaComponent(0.22)
        color.setFill()

        let origin = textContainerOrigin
        for range in cstSelectionRanges where range.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                guard drawRect.intersects(dirtyRect) else { return }
                NSBezierPath(roundedRect: drawRect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    /// Paint a solid teal vertical bar at the head edge of the forest.
    /// The bar runs the full line-fragment height of the head's edge
    /// line (first line for `.leading`, last line for `.trailing`) so
    /// it visually bookends the highlight on the head's side.
    private func drawCSTHeadAccent(in dirtyRect: NSRect) {
        guard let head = cstHeadEdge,
              head.headRange.length > 0,
              let layoutManager,
              let textContainer
        else { return }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: head.headRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return }

        var rects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            rects.append(rect)
        }
        guard let edgeRect = (head.edge == .leading ? rects.first : rects.last)
        else { return }

        let origin = textContainerOrigin
        let barWidth: CGFloat = 3
        let x: CGFloat
        switch head.edge {
        case .leading:
            x = edgeRect.minX + origin.x
        case .trailing:
            x = edgeRect.maxX + origin.x - barWidth
        }
        let barRect = NSRect(
            x: x,
            y: edgeRect.minY + origin.y,
            width: barWidth,
            height: edgeRect.height
        )
        guard barRect.intersects(dirtyRect) else { return }

        NSColor.systemTeal.setFill()
        barRect.fill()
    }

    /// Paint a thin rounded-rect outline over every line fragment
    /// covered by each forest mark's byte range. Color is the
    /// per-letter `VimMarkPalette` hue; alpha modulates with
    /// resolution strength (`.strong` brightest, `.recovered`
    /// dimmest). Drawn before `drawCSTSelectionOverlay` so a live CST
    /// selection paints on top of any mark outline.
    private func drawForestMarkOverlays(in dirtyRect: NSRect) {
        guard !forestMarkOverlays.isEmpty,
              let layoutManager,
              let textContainer
        else { return }

        let origin = textContainerOrigin
        for overlay in forestMarkOverlays where overlay.range.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: overlay.range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }

            let baseColor = VimMarkPalette.color(for: overlay.letter)
            let alpha: CGFloat
            switch overlay.strength {
            case .strong:    alpha = 0.55
            case .weak:      alpha = 0.40
            case .recovered: alpha = 0.28
            }
            let strokeColor = baseColor.withAlphaComponent(alpha)
            strokeColor.setStroke()

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: 0.5, dy: 0.5)
                guard drawRect.intersects(dirtyRect) else { return }
                let path = NSBezierPath(roundedRect: drawRect, xRadius: 3, yRadius: 3)
                path.lineWidth = 1.0
                path.stroke()
            }
        }
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

    // MARK: - Hover tracking

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Required to receive mouseMoved events at all; tracking
        // areas alone aren't enough on the document-window path.
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,  // ignored when .inVisibleRect is set
            options: [
                .mouseMoved,
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func flagsChanged(with event: NSEvent) {
        linkHoverDelegate?.vimTextView(self, modifierFlagsChanged: event.modifierFlags)
        super.flagsChanged(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        linkHoverDelegate?.vimTextView(self, mouseMovedTo: pointInView)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        linkHoverDelegate?.vimTextViewMouseExited(self)
        super.mouseExited(with: event)
    }

    /// Cmd-click intercepts: if the delegate claims the click, swallow
    /// it (no cursor placement, no drag tracking). Cmd-Shift-click is
    /// also claimed so wiki links can open in a workspace tab. Otherwise
    /// fall through to NSTextView's default.
    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (flags == .command || flags == [.command, .shift]),
           event.clickCount == 1,
           let delegate = linkActivationDelegate {
            let pointInView = convert(event.locationInWindow, from: nil)
            let utf16Index = characterIndexForInsertion(at: pointInView)
            if delegate.vimTextView(
                self,
                didCmdClickAt: utf16Index,
                modifierFlags: event.modifierFlags
            ) {
                return
            }
        }
        super.mouseDown(with: event)
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

/// Cmd-click receiver. Returns `true` to claim the click (no
/// cursor placement, no drag); `false` to let the text view fall
/// through to its normal mouse handling.
@MainActor
protocol VimTextViewLinkActivationDelegate: AnyObject {
    func vimTextView(
        _ view: VimTextView,
        didCmdClickAt utf16Index: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool
}

/// Cmd-modifier and mouse-move receiver for the hover preview
/// pipeline. The delegate is responsible for gating expensive work
/// on Cmd-held state — the view forwards every event unconditionally.
@MainActor
protocol VimTextViewLinkHoverDelegate: AnyObject {
    func vimTextView(_ view: VimTextView, modifierFlagsChanged flags: NSEvent.ModifierFlags)
    func vimTextView(_ view: VimTextView, mouseMovedTo pointInView: NSPoint)
    func vimTextViewMouseExited(_ view: VimTextView)
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
