import AppKit
import CambiumCore
import Foundation

/// Cmd+hover preview popover. Pops up an `NSPopover` anchored to the
/// link under the mouse cursor when Cmd is held, showing a slice of
/// the target document's content (with syntax highlighting) around
/// the resolved anchor offset.
///
/// **State machine.** The controller tracks Cmd-modifier state and
/// the currently-hovered reference target. When (`cmdHeld &&
/// currentTarget != nil`), after a 300ms onset delay, the popover
/// presents. While visible, target changes update instantly (no
/// re-delay). Hides on any of: Cmd-release (instant),
/// mouse-leave-text-view (after 80ms grace to absorb flicker between
/// adjacent links), or click.
///
/// **Performance.** Mouse-move events are gated on `cmdHeld` first
/// (one bool check), so idle hover cost is negligible. When Cmd is
/// held, each move does an `NSLayoutManager` hit-test plus a
/// reference-by-byte-offset lookup — both effectively constant. The
/// "target changed" comparison is the actual throttle: same
/// reference under cursor → no work. A one-entry parse cache reuses
/// the parse across multiple anchors of the same target, so
/// "hovering through several `[[Other#X]]` / `[[Other#Y]]` /
/// `[[Other#Z]]`" parses Other once, not three times.
@MainActor
final class HoverPreviewController {
    private weak var document: LiminalSourceDocument?
    private weak var textView: NSTextView?

    private let onsetDelay: Duration
    private let theme: LiminalHighlightTheme
    private let highlighter = LiminalHighlighter()

    private var popover: NSPopover?
    private var contentController: HoverPreviewContentController?

    private var cmdHeld = false
    private var currentTarget: HoverTarget?
    private var pendingTask: Task<Void, Never>?

    /// One-entry parse cache. Holds the full `LiminalParseResult`
    /// (not just `RootSyntax`) so the underlying `SharedSyntaxTree`
    /// stays alive for as long as the cache entry does.
    private var lastParse: ParseCacheEntry?

    private struct ParseCacheEntry {
        let url: URL
        let content: String
        let parsed: LiminalParseResult
    }

    init(
        document: LiminalSourceDocument,
        onsetDelay: Duration = .milliseconds(300),
        theme: LiminalHighlightTheme = .default
    ) {
        self.document = document
        self.onsetDelay = onsetDelay
        self.theme = theme
    }

    func attach(to textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Event handlers (called by VimTextView via delegate)

    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let cmdNow = flags.contains(.command)
        guard cmdNow != cmdHeld else { return }
        cmdHeld = cmdNow
        if !cmdHeld {
            // Cmd released while the mouse was stationary — kill the
            // popover instantly without waiting for the next mouse
            // event. (When the mouse IS moving, `handleMouseMoved`'s
            // live modifier check picks up the release on its own.)
            currentTarget = nil
            hide()
        }
    }

    func handleMouseMoved(at viewPoint: NSPoint) {
        // Read the live modifier state rather than trusting a stored
        // `cmdHeld` flag from `flagsChanged`. NSTextView's
        // `flagsChanged` only fires while it's first responder and is
        // easy to miss across window-focus transitions, so the stored
        // bit can drift. `NSEvent.modifierFlags` is a class property
        // that polls the current keyboard state — always accurate,
        // negligible cost per mouseMoved.
        let cmdNow = NSEvent.modifierFlags.contains(.command)
        if cmdNow != cmdHeld {
            cmdHeld = cmdNow
        }
        guard cmdHeld else {
            // Cmd not held → no preview. Tear down any lingering
            // state from a missed flagsChanged.
            if currentTarget != nil || (popover?.isShown ?? false) {
                currentTarget = nil
                hide()
            }
            return
        }

        let resolved = resolveTarget(at: viewPoint)
        let target = resolved?.target

        if target == currentTarget {
            return
        }
        currentTarget = target

        if let resolved {
            scheduleShow(for: resolved.target, anchorRect: resolved.anchorRect)
        } else {
            scheduleHide()
        }
    }

    func handleMouseExited() {
        currentTarget = nil
        scheduleHide()
    }

    /// Caller hint that a click is about to dispatch — hide the
    /// popover so it doesn't linger over the click action.
    func cancelForClick() {
        currentTarget = nil
        hide()
    }

    // MARK: - Target resolution

    private struct ResolvedHover {
        let target: HoverTarget
        let anchorRect: NSRect
    }

    private func resolveTarget(at viewPoint: NSPoint) -> ResolvedHover? {
        guard let textView,
              let document,
              let url = document.fileURL,
              let root = document.currentRootSyntax
        else { return nil }

        let textLength = (textView.string as NSString).length
        guard textLength > 0 else { return nil }

        let utf16Index = textView.characterIndexForInsertion(at: viewPoint)
        // characterIndexForInsertion returns a value past-the-end on
        // empty space below the last line — clamp to last char so
        // hits at end-of-doc don't false-trigger.
        let clamped = min(utf16Index, max(textLength - 1, 0))
        let nsRange = NSRange(location: clamped, length: 0)
        guard let byteRange = LiminalTextView.utf16RangeToByteRange(
            nsRange,
            in: textView.string
        ) else { return nil }

        let byteOffset = TextSize(UInt32(byteRange.lowerBound))
        let canonicalCurrent = VaultRegistry.canonicalNoteURL(for: url)
        let entry = VaultRegistry.shared.entry(for: url)
        let docIndex = entry.indexes[canonicalCurrent]
            ?? DocumentIndex.build(root: root)

        guard let reference = docIndex.reference(containing: byteOffset)
        else { return nil }

        guard let target = HoverPreviewController.hoverTarget(
            for: reference,
            currentURL: canonicalCurrent,
            in: entry.linkIndex
        ) else { return nil }

        let rect = referenceRect(for: reference, in: textView)
        return ResolvedHover(target: target, anchorRect: rect)
    }

    /// Pure dispatch from a reference to a `HoverTarget` (or nil for
    /// non-previewable kinds: external URI, unresolved, ambiguous).
    /// Lifted out of `resolveTarget(at:)` so tests can exercise it
    /// without an `NSTextView`.
    nonisolated static func hoverTarget(
        for reference: DocumentReference,
        currentURL: URL,
        in vaultLinkIndex: VaultLinkIndex
    ) -> HoverTarget? {
        if reference.target.isExternal {
            return nil
        }
        let resolution = vaultLinkIndex.resolve(
            target: reference.target,
            from: currentURL
        )
        switch resolution {
        case .resolved(let destination):
            return HoverTarget(
                targetURL: destination.noteID,
                anchor: destination.anchor
            )
        case .noteResolved(let url, let requestedAnchor):
            // Note exists but anchor doesn't — preview the note from
            // the top with the missing anchor noted in the title.
            return HoverTarget(
                targetURL: url,
                anchor: requestedAnchor,
                anchorMissing: true
            )
        case .unresolved, .ambiguous:
            return nil
        }
    }

    private func referenceRect(for reference: DocumentReference, in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let nsRange = LiminalTextView.byteRangeToNSRange(
                  reference.sourceRange,
                  in: textView.string
              )
        else { return .zero }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: nsRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    // MARK: - Show / hide scheduling

    private func scheduleShow(for target: HoverTarget, anchorRect: NSRect) {
        pendingTask?.cancel()

        // Already-visible popover updates instantly (no delay).
        if let popover, popover.isShown {
            present(target: target, anchorRect: anchorRect)
            return
        }

        let delay = onsetDelay
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-check that the target is still current (could have
            // changed during the delay).
            guard self.currentTarget == target else { return }
            self.present(target: target, anchorRect: anchorRect)
        }
    }

    private func scheduleHide() {
        pendingTask?.cancel()
        // Small grace period to absorb flicker as the cursor crosses
        // plain text between two adjacent links.
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            if self.currentTarget == nil {
                self.hide()
            }
        }
    }

    private func hide() {
        pendingTask?.cancel()
        pendingTask = nil
        popover?.performClose(nil)
    }

    // MARK: - Presentation

    private func present(target: HoverTarget, anchorRect: NSRect) {
        guard let textView else { return }
        let snapshot = buildSnapshot(for: target)
        let controller = ensurePopover()
        controller.updateContent(snapshot: snapshot)
        if let popover, !popover.isShown {
            popover.show(
                relativeTo: anchorRect,
                of: textView,
                preferredEdge: .maxY
            )
        }
    }

    private func ensurePopover() -> HoverPreviewContentController {
        if let contentController, popover != nil {
            return contentController
        }
        let controller = HoverPreviewContentController(theme: theme)
        contentController = controller
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        self.popover = popover
        return controller
    }

    // MARK: - Snapshot

    private func buildSnapshot(for target: HoverTarget) -> HoverPreviewSnapshot {
        let canonical = target.targetURL
        let entry = VaultRegistry.shared.entry(for: canonical)

        // Source bytes for the hover target come from disk: the
        // hot-tier `LiminalNoteMetadata` no longer carries content for
        // closed notes (and the hover target is almost always a
        // *different* note than the one the user is editing). The
        // `lastParse` cache below avoids re-parsing when the same
        // target is hovered repeatedly without disk churn.
        guard let content = try? String(contentsOf: canonical, encoding: .utf8) else {
            return HoverPreviewSnapshot.unavailable(target: target, theme: theme)
        }

        let parsed: LiminalParseResult
        if let cached = lastParse, cached.url == canonical, cached.content == content {
            parsed = cached.parsed
        } else {
            do {
                parsed = try LiminalParser().parse(content)
                lastParse = ParseCacheEntry(url: canonical, content: content, parsed: parsed)
            } catch {
                return HoverPreviewSnapshot.unavailable(target: target, theme: theme)
            }
        }

        let docIndex = entry.indexes[canonical]
            ?? DocumentIndex.build(root: parsed.rootSyntax)

        let anchorByteOffset: Int
        if let anchor = target.anchor,
           let byteOffset = docIndex.blockOffset(for: anchor) {
            anchorByteOffset = Int(byteOffset.rawValue)
        } else {
            anchorByteOffset = 0
        }

        let (sliceStart, sliceEnd) = HoverPreviewController.computeSliceRange(
            in: content,
            anchorByteOffset: anchorByteOffset
        )
        let sliceText = HoverPreviewController.sliceContent(
            content,
            byteStart: sliceStart,
            byteEnd: sliceEnd
        )

        let sliceRange = TextRange(
            start: TextSize(UInt32(sliceStart)),
            length: TextSize(UInt32(sliceEnd - sliceStart))
        )
        let spans = highlighter.spans(for: parsed.rootSyntax, in: sliceRange)
        let attributed = HoverPreviewController.buildAttributedString(
            sliceText: sliceText,
            sliceByteStart: sliceStart,
            spans: spans,
            theme: theme
        )

        return HoverPreviewSnapshot(
            title: HoverPreviewController.title(for: target),
            attributedBody: attributed
        )
    }

    // MARK: - Static helpers (pure; testable; nonisolated so callers
    // outside the main actor — e.g. `HoverPreviewSnapshot.unavailable`
    // — can use them).

    nonisolated static func title(for target: HoverTarget) -> String {
        let baseName = target.targetURL.deletingPathExtension().lastPathComponent
        guard let anchor = target.anchor else { return baseName }
        let suffix: String
        switch anchor {
        case .heading(let h):
            suffix = "› #\(h)"
        case .block(let b):
            suffix = "› ^\(b)"
        case .sourceOffset:
            return baseName
        }
        return target.anchorMissing
            ? "\(baseName) \(suffix) (anchor not found)"
            : "\(baseName) \(suffix)"
    }

    /// Compute a `[startByte, endByte)` slice range of `content`
    /// starting at the anchor's line (snapped back to the line's
    /// first byte) and extending forward up to `maxLines` lines or
    /// `maxBytes` bytes, whichever hits first.
    ///
    /// The slice deliberately starts *at* the anchor — not before —
    /// so the popover's visible top is the destination the link
    /// points to. Showing content *above* the anchor would obscure
    /// what the user actually wants to see (e.g., for a small note
    /// that fits entirely in the budget, "top of file" would be
    /// shown above the anchor and the anchor would be buried in
    /// the middle).
    nonisolated static func computeSliceRange(
        in content: String,
        anchorByteOffset: Int,
        maxLines: Int = 12,
        maxBytes: Int = 2048
    ) -> (Int, Int) {
        let bytes = Array(content.utf8)
        let total = bytes.count
        guard total > 0 else { return (0, 0) }
        let anchor = max(0, min(anchorByteOffset, total))

        let start = lineStartByte(in: bytes, atOrBefore: anchor)

        var end = start
        var linesSeen = 0
        while end < total {
            if bytes[end] == 0x0A {
                linesSeen += 1
                end += 1
                if linesSeen >= maxLines { break }
            } else {
                end += 1
            }
            if (end - start) >= maxBytes { break }
        }
        return (start, end)
    }

    nonisolated private static func lineStartByte(in bytes: [UInt8], atOrBefore offset: Int) -> Int {
        var i = min(offset, bytes.count)
        while i > 0 && bytes[i - 1] != 0x0A { i -= 1 }
        return i
    }

    nonisolated private static func lineEndByte(in bytes: [UInt8], atOrAfter offset: Int) -> Int {
        var i = min(offset, bytes.count)
        while i < bytes.count && bytes[i] != 0x0A { i += 1 }
        return i
    }

    nonisolated static func sliceContent(_ content: String, byteStart: Int, byteEnd: Int) -> String {
        let bytes = Array(content.utf8)
        let clampedStart = max(0, min(byteStart, bytes.count))
        let clampedEnd = max(clampedStart, min(byteEnd, bytes.count))
        return String(decoding: bytes[clampedStart..<clampedEnd], as: UTF8.self)
    }

    nonisolated static func buildAttributedString(
        sliceText: String,
        sliceByteStart: Int,
        spans: [HighlightSpan],
        theme: LiminalHighlightTheme
    ) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: sliceText)
        let fullRange = NSRange(location: 0, length: (sliceText as NSString).length)
        attr.setAttributes(theme.defaultAttributes, range: fullRange)

        let offsetMap = OffsetMap(source: sliceText)
        for span in spans {
            let localStartByte = Int(span.range.start.rawValue) - sliceByteStart
            let localLengthByte = Int(span.range.length.rawValue)
            guard localStartByte >= 0,
                  let nsRange = offsetMap.nsRange(
                      forByteStart: UInt32(localStartByte),
                      length: UInt32(localLengthByte)
                  )
            else { continue }
            let attributes = theme.attributes(
                for: span.category,
                modifiers: span.modifiers
            )
            attr.addAttributes(attributes, range: nsRange)
        }
        return attr
    }
}

/// Identifies a hover target: which document the popover should
/// show, and which anchor (if any) to scroll to within it.
struct HoverTarget: Equatable {
    let targetURL: URL
    let anchor: LinkNavigationAnchor?
    /// True when the target note exists but the requested anchor
    /// (heading or block) wasn't found — the preview shows the doc
    /// from the top with a notice in the title.
    let anchorMissing: Bool

    init(targetURL: URL, anchor: LinkNavigationAnchor?, anchorMissing: Bool = false) {
        self.targetURL = targetURL
        self.anchor = anchor
        self.anchorMissing = anchorMissing
    }
}

struct HoverPreviewSnapshot {
    let title: String
    let attributedBody: NSAttributedString

    static func unavailable(target: HoverTarget, theme: LiminalHighlightTheme) -> HoverPreviewSnapshot {
        let body = NSMutableAttributedString(
            string: "(content unavailable — file not yet indexed or unreadable)"
        )
        body.setAttributes(
            theme.defaultAttributes,
            range: NSRange(location: 0, length: body.length)
        )
        return HoverPreviewSnapshot(
            title: HoverPreviewController.title(for: target),
            attributedBody: body
        )
    }
}
