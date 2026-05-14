import AppKit
import CambiumCore
import CambiumIncremental
import CambiumSelection
import Combine
import SwiftUI

struct LiminalTextView: NSViewRepresentable {
    @ObservedObject var document: LiminalSourceDocument
    let navigationRequest: NavigationRequest?

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
        // Vim-style undo lives entirely on the document. NSTextView's
        // own byte-level undo would compete with transaction undo, so
        // keep AppKit undo disabled.
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.typingAttributes = context.coordinator.theme.defaultAttributes

        textView.string = document.session.source
        textView.textStorage?.delegate = context.coordinator
        textView.delegate = context.coordinator
        textView.vimController = document.vimController
        textView.linkActivationDelegate = context.coordinator
        textView.linkHoverDelegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.hoverPreviewController.attach(to: textView)
        document.vimController.delegate = context.coordinator
        // Seed the initial undo snapshot now that we're on the
        // MainActor — the document's off-main inits couldn't do this
        // because seeding touches MainActor-bound state. Idempotent.
        document.seedInitialUndoSnapshotIfNeeded()
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
        context.coordinator.consumeNavigationRequest(navigationRequest)
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
    final class Coordinator: NSObject, NSTextStorageDelegate, NSTextViewDelegate, VimControllerDelegate, VimTextViewLinkActivationDelegate, VimTextViewLinkHoverDelegate, NavigationSubscriber {
        let document: LiminalSourceDocument
        weak var textView: VimTextView?
        var isApplyingProgrammaticEdit = false
        private var lastConsumedNavigationNonce: UUID?

        let highlighter = LiminalHighlighter()
        let theme = LiminalHighlightTheme.default

        private enum HighlightRepaintScope {
            case fullDocument
            case parserDirtyRange
            case explicitByteRanges([CambiumCore.TextRange])
        }

        private struct HighlightPaintScope {
            let byteRange: CambiumCore.TextRange?
            let nsRange: NSRange
            let offsetMap: OffsetMap
        }

        /// Cmd+hover popover lifetime is tied to this Coordinator —
        /// when the window closes the controller goes with it, and
        /// its `NSPopover` is released along with it. Constructed
        /// once at init since it doesn't depend on the text view.
        let hoverPreviewController: HoverPreviewController

        private var modeObservation: AnyCancellable?
        private var marksObservation: AnyCancellable?
        private var preferencesObservation: AnyCancellable?
        private var fileURLObservation: AnyCancellable?

        /// Tracks the URL we're currently subscribed to with the
        /// router, so we can unsubscribe correctly when the document
        /// URL changes (e.g. Save As) without leaking stale entries.
        private var routerSubscriptionURL: URL?

        /// Visual-mode anchor for the charwise / linewise variants.
        /// Set when `v` / `V` is pressed; cleared on exit. UTF-16
        /// offset where the visual selection started.
        private var visualAnchorUTF16: Int?

        /// Visual-block anchor as (line, column). The block's other
        /// corner is the cursor's current (line, column).
        private var visualBlockAnchor: (line: Int, column: Int)?

        /// Visual-mode head: the moving end of the selection (the end
        /// the user is extending). Tracked separately because reading
        /// `textView.selectedRange().location` in a forward-extending
        /// visual selection always returns the *anchor* (the smaller
        /// of {anchor, head}) — so without this field, motion handlers
        /// would compute their next target from the anchor and the
        /// selection would cap at +1 cell. Updated by every extend
        /// call; cleared on visual-mode exit.
        private var visualHeadUTF16: Int?

        /// Active forest selection in ``VimMode/visualCST``. Set by
        /// `enterCSTVisualMode`; mutated by the structural-motion
        /// delegate methods; cleared on visual-mode exit. Holds a
        /// `SyntaxNodeHandle` into the tree it was captured against;
        /// `ensureForestIsLive()` validates the tree hasn't been
        /// replaced before every navigation call.
        private var cstForest: LiminalForest?

        init(document: LiminalSourceDocument) {
            self.document = document
            self.hoverPreviewController = HoverPreviewController(document: document)
        }

        // No `deinit` cleanup needed for the navigation router: it
        // holds subscribers weakly, so a closed Coordinator drops out
        // automatically on the next `navigate`. Save-As URL changes
        // are handled explicitly in `updateRouterSubscription`.

        // MARK: - Mode observation

        func installModeObservers(on controller: VimController) {
            modeObservation = controller.$mode.sink { [weak self] newMode in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !newMode.isVisual {
                        // Leaving any visual mode → drop anchors so
                        // the next motion in normal mode places the
                        // cursor cleanly instead of trying to extend
                        // a stale selection. Also drop the CST forest
                        // (only set inside .visualCST) so it doesn't
                        // outlive the tree it was captured against, and
                        // clear the overlay so the teal highlight
                        // disappears the instant the mode flips.
                        self.visualAnchorUTF16 = nil
                        self.visualBlockAnchor = nil
                        self.visualHeadUTF16 = nil
                        self.cstForest = nil
                        self.textView?.cstSelectionRange = nil
                    }
                    self.refreshCursorStyle()
                }
            }
            marksObservation = controller.$marks.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMarkIndicators()
                }
            }
            // Re-apply (or clear) highlights when the user toggles the
            // syntax-highlighting preference from the View menu.
            preferencesObservation = EditorPreferences.shared
                .$highlightingEnabled
                .dropFirst() // already in correct state at init
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.applyHighlights()
                    }
                }
            // Track the document's URL through the navigation router
            // so cross-window Cmd-clicks land here when this is the
            // target. Drains any pending request the router was
            // holding for this URL.
            fileURLObservation = document.$fileURL.sink { [weak self] newURL in
                Task { @MainActor [weak self] in
                    self?.updateRouterSubscription(to: newURL)
                }
            }
        }

        private func updateRouterSubscription(to newURL: URL?) {
            if let oldURL = routerSubscriptionURL, oldURL != newURL {
                NavigationRouter.shared.unsubscribe(self, for: oldURL)
                routerSubscriptionURL = nil
            }
            if let newURL, routerSubscriptionURL != newURL {
                NavigationRouter.shared.subscribe(self, for: newURL)
                routerSubscriptionURL = newURL
            }
        }

        // MARK: - NavigationSubscriber

        func consumeNavigationRequest(_ request: NavigationRequest?) {
            guard let request,
                  lastConsumedNavigationNonce != request.nonce
            else { return }
            lastConsumedNavigationNonce = request.nonce
            handleNavigation(request)
        }

        /// Incoming cross-document navigation. The router has already
        /// matched this request to our document URL; we bring our
        /// window forward (the second-Cmd-click case where the target
        /// is open but in the background), resolve the anchor against
        /// the current `DocumentIndex`, and scroll.
        nonisolated func handleNavigation(_ request: NavigationRequest) {
            MainActor.assumeIsolated {
                // Without this, Cmd-clicking a wikilink whose target
                // is already open scrolls the background window
                // silently and the user sees nothing happen in their
                // current window.
                textView?.window?.makeKeyAndOrderFront(nil)
                guard let docIndex = currentDocumentIndex() else {
                    return
                }
                if let anchor = request.anchor,
                   let byteOffset = docIndex.blockOffset(for: anchor) {
                    scrollToByteOffset(Int(byteOffset.rawValue))
                } else {
                    // Anchor missing or no anchor — land at top so the
                    // user sees that the navigation took effect.
                    scrollToByteOffset(0)
                }
            }
        }

        /// Resolve every live mark against the current tree and push the
        /// resulting `(utf16Location, letter)` list to the text view so
        /// `draw(_:)` can paint the dots.
        func refreshMarkIndicators() {
            guard let textView else { return }
            guard let root = document.currentRootSyntax else {
                textView.markPositions = []
                return
            }
            let source = textView.string
            let indicators: [VimTextView.MarkIndicator] = document
                .vimController
                .marks
                .marks
                .compactMap { (letter, anchor) -> VimTextView.MarkIndicator? in
                    let byteOffset: TextSize
                    switch anchor.resolve(in: root) {
                    case .strong(let off), .weak(let off), .recovered(let off):
                        byteOffset = off
                    case .lost:
                        return nil
                    }
                    let range = CambiumCore.TextRange(
                        start: byteOffset,
                        length: TextSize(0)
                    )
                    guard let nsRange = LiminalTextView.byteRangeToNSRange(
                        range,
                        in: source
                    ) else { return nil }
                    return VimTextView.MarkIndicator(
                        utf16Location: nsRange.location,
                        letter: letter
                    )
                }
            textView.markPositions = indicators
            // Glyph positions may have shifted even when the indicator
            // tuple is unchanged (e.g., text on a prior line moved); force
            // a redraw of the visible region to catch that case.
            textView.needsDisplay = true
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
            case .visual, .visualLine, .visualBlock, .visualCST:
                // Visual modes own their selection — leave it alone
                // and let the per-motion extend logic (or the CST
                // forest mirror, for .visualCST) manage it.
                break
            }
        }

        // MARK: - NSTextViewDelegate

        nonisolated func textViewDidChangeSelection(_ notification: Notification) {
            MainActor.assumeIsolated {
                refreshInspector()
            }
        }

        /// Recompute the inspector snapshot from the current cursor +
        /// tree. Cheap (one tree walk).
        func refreshInspector() {
            guard let textView else {
                document.cstInspector.refresh(
                    cursorByteOffset: nil,
                    root: nil,
                    source: ""
                )
                return
            }
            let offset = currentCursorByteOffset()
            document.cstInspector.refresh(
                cursorByteOffset: offset,
                root: document.currentRootSyntax,
                source: textView.string
            )
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
                guard document.applyTextEdits([edit]) else { return }
                applyHighlights(in: editedRange)
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
            let currentLocation = currentMotionCursorUTF16()
            let newLocation = CursorMotionEngine.newOffset(
                for: motion,
                in: textView.string,
                from: currentLocation,
                count: count
            )
            setCursorAt(utf16Location: newLocation)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        /// Where the cursor is for purposes of motion. In a visual mode
        /// this is the *head* (the moving end of the selection) — NOT
        /// the anchor end that `textView.selectedRange().location`
        /// returns when extending forward. In normal / insert the
        /// selection start IS the cursor, so this collapses to the same
        /// value. Every motion handler (h/j/k/l, gj/gk, gg/G, [[/]],
        /// H/M/L, w/b/e, etc.) must go through this — otherwise
        /// forward-extending visual selections cap at +1 cell because
        /// the next motion target keeps recomputing from the anchor.
        private func currentMotionCursorUTF16() -> Int {
            guard let textView else { return 0 }
            if document.vimController.mode.isVisual,
               let head = visualHeadUTF16 {
                return head
            }
            return textView.selectedRange().location
        }

        func structuralMotion(_ motion: StructuralMotion, count: Int) {
            guard let textView else { return }
            let steps = max(1, count)
            let startOffset = currentCursorByteOffset() ?? 0

            switch motion {
            case .previousSibling, .nextSibling:
                guard let parsed = document.session.parseResult else { return }
                var byteOffset = startOffset
                for _ in 0..<steps {
                    let next: Int?
                    switch motion {
                    case .previousSibling:
                        next = StructureCursor.previousSibling(of: byteOffset, in: parsed.rootSyntax)
                    case .nextSibling:
                        next = StructureCursor.nextSibling(of: byteOffset, in: parsed.rootSyntax)
                    default: next = nil
                    }
                    guard let next else { break }
                    byteOffset = next
                }
                setCursor(byteOffset: byteOffset)

            case .enclosingHeading:
                // `gh` semantics: jump to the heading whose section
                // contains the cursor. From inside section X's body
                // → land on X. From on X's heading line → ascend to
                // X's parent (so successive `gh`s walk up the
                // hierarchy). Counts repeat the ascend.
                guard let docIndex = currentDocumentIndex() else { return }
                let source = textView.string
                var pivot = startOffset
                var target: HeadingAnchor?
                for _ in 0..<steps {
                    guard let h = docIndex.heading(
                        enclosing: TextSize(UInt32(pivot))
                    ) else { break }
                    let nextTarget: HeadingAnchor?
                    if isCursorOnHeadingLine(
                        cursorByte: pivot,
                        heading: h,
                        in: source
                    ) {
                        nextTarget = docIndex.parentHeading(of: h)
                    } else {
                        nextTarget = h
                    }
                    guard let next = nextTarget else { break }
                    target = next
                    pivot = Int(next.sourceOffset.rawValue)
                }
                if let final = target {
                    setCursor(byteOffset: headingFirstNonBlank(at: final, in: source))
                }

            case .previousHeading, .nextHeading:
                // `[[` / `]]` semantics: walk between *different*
                // headings. From inside section X's body, `[[` should
                // land on X-1, not X — so we pivot through the
                // enclosing heading first, then take strict-less
                // against its source offset. After step 1 the cursor
                // is on a heading and the same logic naturally walks
                // further back. `]]` doesn't have this asymmetry
                // (strict-greater already skips the enclosing
                // heading) but routes through the same path for
                // symmetry.
                guard let docIndex = currentDocumentIndex() else { return }
                let source = textView.string
                var pivot = startOffset
                for _ in 0..<steps {
                    let nextHeading: HeadingAnchor?
                    switch motion {
                    case .previousHeading:
                        let pivotOffset = docIndex.heading(
                            enclosing: TextSize(UInt32(pivot))
                        )?.sourceOffset ?? TextSize(UInt32(pivot))
                        nextHeading = docIndex.heading(before: pivotOffset)
                    case .nextHeading:
                        nextHeading = docIndex.heading(
                            after: TextSize(UInt32(pivot))
                        )
                    default:
                        nextHeading = nil
                    }
                    guard let nextHeading else { break }
                    pivot = headingFirstNonBlank(at: nextHeading, in: source)
                }
                setCursor(byteOffset: pivot)

            case .previousReference, .nextReference:
                guard let docIndex = currentDocumentIndex() else { return }
                var byteOffset = startOffset
                for _ in 0..<steps {
                    let nextRef: DocumentReference?
                    if motion == .previousReference {
                        nextRef = docIndex.reference(
                            before: TextSize(UInt32(byteOffset))
                        )
                    } else {
                        nextRef = docIndex.reference(
                            after: TextSize(UInt32(byteOffset))
                        )
                    }
                    guard let nextRef else { break }
                    byteOffset = Int(nextRef.sourceRange.start.rawValue)
                }
                setCursor(byteOffset: byteOffset)
            }

            textView.scrollRangeToVisible(textView.selectedRange())
        }

        /// True when `cursorByte` falls on the same source line as
        /// `heading.sourceOffset`. Used by `gh` to decide between
        /// "land on this section's heading" (cursor in body) and
        /// "ascend to parent" (cursor on the heading line itself).
        private func isCursorOnHeadingLine(
            cursorByte: Int,
            heading: HeadingAnchor,
            in source: String
        ) -> Bool {
            let utf8 = source.utf8
            let headingByte = Int(heading.sourceOffset.rawValue)
            let lo = min(cursorByte, headingByte)
            let hi = max(cursorByte, headingByte)
            guard hi <= utf8.count else { return false }
            // Walk the bytes between cursor and heading; if any is a
            // newline, they're on different lines.
            let loIdx = utf8.index(utf8.startIndex, offsetBy: lo)
            let hiIdx = utf8.index(utf8.startIndex, offsetBy: hi)
            var idx = loIdx
            while idx < hiIdx {
                if utf8[idx] == 0x0A /* \n */ { return false }
                idx = utf8.index(after: idx)
            }
            return true
        }

        /// Resolve a heading anchor's "land here" byte offset:
        /// first non-blank of the heading line (past the `#`
        /// markers + whitespace). Reuses NSString's line API so we
        /// don't have to rebuild the lineFirstNonBlank logic from
        /// the engine — `CursorMotionEngine` is UTF-16-indexed,
        /// the heading offset is UTF-8.
        private func headingFirstNonBlank(
            at heading: HeadingAnchor,
            in source: String
        ) -> Int {
            let byteOffset = Int(heading.sourceOffset.rawValue)
            // Convert byte offset → UTF-16 → walk line forward to first
            // non-`#`, non-whitespace char → convert back to byte offset.
            let utf8 = source.utf8
            guard byteOffset >= 0, byteOffset <= utf8.count else { return byteOffset }
            let startIdx = utf8.index(utf8.startIndex, offsetBy: byteOffset)
            var cursor = startIdx
            // Skip any run of `#` markers.
            while cursor < utf8.endIndex, utf8[cursor] == 0x23 /* # */ {
                cursor = utf8.index(after: cursor)
            }
            // Skip whitespace (space, tab) on the line.
            while cursor < utf8.endIndex {
                let byte = utf8[cursor]
                if byte == 0x20 || byte == 0x09 {
                    cursor = utf8.index(after: cursor)
                    continue
                }
                if byte == 0x0A || byte == 0x0D { break } // EOL: heading body empty
                break
            }
            return utf8.distance(from: utf8.startIndex, to: cursor)
        }

        /// Vim's `H` / `M` / `L` — jump to top/middle/bottom of the
        /// visible viewport. Pulls the visible glyph range from the
        /// layout manager, converts to characters, and hands the
        /// rest to `CursorMotionEngine`. No scroll needed: the
        /// target is already on screen by definition.
        func viewportMotion(_ motion: ViewportMotion, count: Int) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: textView.visibleRect,
                in: textContainer
            )
            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let target = CursorMotionEngine.newOffset(
                for: motion,
                in: textView.string,
                visibleCharRange: charRange,
                count: count
            )
            setCursorAt(utf16Location: target)
        }

        /// Vim's `gj` / `gk` / `g0` / `g^` / `g$` — display-line
        /// motions over soft-wrapped rows. The "current display
        /// line" is the line fragment at the cursor; `gj` / `gk`
        /// step to neighbor fragments preserving the cursor's
        /// preferred x; `g0` / `g^` / `g$` snap within the current
        /// fragment via the engine.
        func displayLineMotion(_ motion: DisplayLineMotion, count: Int) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }
            let charIndex = textView.selectedRange().location

            switch motion {
            case .start, .firstNonBlank, .end:
                guard let lineRange = displayLineCharRange(
                    at: charIndex,
                    layoutManager: layoutManager
                ) else { return }
                let target = CursorMotionEngine.newOffset(
                    for: motion,
                    in: textView.string,
                    displayLineRange: lineRange
                )
                setCursorAt(utf16Location: target)
                textView.scrollRangeToVisible(textView.selectedRange())

            case .down, .up:
                let steps = max(1, count)
                let direction: VerticalDisplayDirection =
                    (motion == .down) ? .down : .up
                var current = charIndex
                for _ in 0..<steps {
                    guard let next = neighborDisplayLineCharIndex(
                        from: current,
                        direction: direction,
                        layoutManager: layoutManager,
                        textContainer: textContainer
                    ) else { break }
                    if next == current { break }
                    current = next
                }
                setCursorAt(utf16Location: current)
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        private enum VerticalDisplayDirection { case up, down }

        /// Character range covering the display line that contains
        /// `charIndex`. Returns nil if the layout manager can't
        /// resolve a fragment (empty text, bad index).
        private func displayLineCharRange(
            at charIndex: Int,
            layoutManager: NSLayoutManager
        ) -> NSRange? {
            guard layoutManager.numberOfGlyphs > 0 else { return nil }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let safeGlyph = min(glyphIndex, layoutManager.numberOfGlyphs - 1)
            var lineGlyphRange = NSRange()
            _ = layoutManager.lineFragmentUsedRect(
                forGlyphAt: safeGlyph,
                effectiveRange: &lineGlyphRange
            )
            return layoutManager.characterRange(
                forGlyphRange: lineGlyphRange,
                actualGlyphRange: nil
            )
        }

        /// Find the character at the cursor's preferred x in the
        /// neighbor display line. Returns nil at document
        /// boundaries (no neighbor fragment to step into).
        private func neighborDisplayLineCharIndex(
            from charIndex: Int,
            direction: VerticalDisplayDirection,
            layoutManager: NSLayoutManager,
            textContainer: NSTextContainer
        ) -> Int? {
            guard layoutManager.numberOfGlyphs > 0 else { return nil }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let safeGlyph = min(glyphIndex, layoutManager.numberOfGlyphs - 1)

            var currentRange = NSRange()
            let currentRect = layoutManager.lineFragmentRect(
                forGlyphAt: safeGlyph,
                effectiveRange: &currentRange
            )
            // Preferred x = cursor's x within the container.
            let glyphLocation = layoutManager.location(forGlyphAt: safeGlyph)
            let preferredX = currentRect.minX + glyphLocation.x

            // Neighbor glyph: step one past the current fragment
            // (down) or one before its start (up).
            let neighborGlyph: Int
            switch direction {
            case .down:
                let candidate = currentRange.location + currentRange.length
                guard candidate < layoutManager.numberOfGlyphs else { return nil }
                neighborGlyph = candidate
            case .up:
                guard currentRange.location > 0 else { return nil }
                neighborGlyph = currentRange.location - 1
            }

            var neighborRange = NSRange()
            let neighborRect = layoutManager.lineFragmentRect(
                forGlyphAt: neighborGlyph,
                effectiveRange: &neighborRange
            )
            // Probe at preferred x, vertically inside the neighbor
            // fragment. `glyphIndex(for:in:)` returns the closest
            // glyph regardless of distance — exactly what we want
            // since `preferredX` may exceed the neighbor's used
            // width (short line).
            let probe = NSPoint(x: preferredX, y: neighborRect.midY)
            let foundGlyph = layoutManager.glyphIndex(for: probe, in: textContainer)
            return layoutManager.characterIndexForGlyph(at: foundGlyph)
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
            let cursor = textView.selectedRange().location
            guard let before = document.makeUndoSnapshot(cursor: cursor) else { return }

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
            document.recordTextTransaction(
                before: before,
                afterCursor: nsRange.location,
                edits: [
                    TextEdit(
                        range: location.markerByteRange,
                        replacement: newMarker
                    )
                ]
            )
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

        // MARK: - VimTextViewLinkHoverDelegate

        func vimTextView(_ view: VimTextView, modifierFlagsChanged flags: NSEvent.ModifierFlags) {
            hoverPreviewController.handleFlagsChanged(flags)
        }

        func vimTextView(_ view: VimTextView, mouseMovedTo pointInView: NSPoint) {
            hoverPreviewController.handleMouseMoved(at: pointInView)
        }

        func vimTextViewMouseExited(_ view: VimTextView) {
            hoverPreviewController.handleMouseExited()
        }

        // MARK: - Cmd-click activation

        /// Cmd-click receiver. Resolve the byte offset under the click,
        /// look up the innermost reference via `DocumentIndex`, and
        /// route through the activation policy. Returns `true` to
        /// claim the click; `false` falls back to NSTextView's default
        /// cursor placement.
        ///
        /// Plain Cmd-click replaces the active workspace tab. Cmd-Shift-click
        /// routes the same activation into a new workspace tab.
        func vimTextView(
            _ view: VimTextView,
            didCmdClickAt utf16Index: Int,
            modifierFlags: NSEvent.ModifierFlags
        ) -> Bool {
            // Click takes over from hover; close any visible popover
            // so it doesn't linger over the action.
            hoverPreviewController.cancelForClick()
            guard let textView,
                  let byteRange = LiminalTextView.utf16RangeToByteRange(
                      NSRange(location: utf16Index, length: 0),
                      in: textView.string
                  )
            else { return false }
            return activateReference(
                atByteOffset: TextSize(UInt32(byteRange.lowerBound)),
                anchorUTF16Index: utf16Index,
                disposition: NavigationDisposition.click(modifierFlags: modifierFlags)
            )
        }

        /// Shared activation core: given a source byte offset (where
        /// to look for a reference) and a UTF-16 anchor index (where
        /// to anchor the ambiguity popover, if it appears), resolve
        /// the reference under the byte offset and route through the
        /// activation policy. Returns `true` if a reference was
        /// found and dispatched.
        ///
        /// Used by both the mouse path (`vimTextView(_:didCmdClickAt:...)`)
        /// and the keyboard path (`gd`).
        @discardableResult
        private func activateReference(
            atByteOffset byteOffset: TextSize,
            anchorUTF16Index: Int,
            disposition: NavigationDisposition
        ) -> Bool {
            guard let url = document.fileURL,
                  let docIndex = currentDocumentIndex()
            else { return false }
            let canonicalURL = VaultRegistry.canonicalNoteURL(for: url)
            let entry = VaultRegistry.shared.entry(for: url)
            guard let result = CmdClickHandler.decision(
                atByteOffset: byteOffset,
                documentURL: canonicalURL,
                documentIndex: docIndex,
                vaultLinkIndex: entry.linkIndex
            ) else { return false }
            return activate(
                decision: result.decision,
                in: docIndex,
                currentURL: canonicalURL,
                clickUTF16Index: anchorUTF16Index,
                disposition: disposition
            )
        }

        /// `gd`: keyboard equivalent of Cmd-click. Read the cursor's
        /// byte offset, anchor any ambiguity popover at the cursor's
        /// UTF-16 position, dispatch via the same activation core
        /// the mouse path uses. Always replaces in the current tab
        /// (the new-tab disposition is a mouse-only Cmd+Shift
        /// affordance).
        func goToDefinitionAtCursor() {
            guard let textView,
                  let byteOffset = currentCursorByteOffset()
            else { return }
            let utf16Index = textView.selectedRange().location
            activateReference(
                atByteOffset: TextSize(UInt32(byteOffset)),
                anchorUTF16Index: utf16Index,
                disposition: .replaceInCurrentTab
            )
        }

        /// Apply the engine's plan for entering insert mode at
        /// `position`. The pre-edit (if any) goes through
        /// `replaceCharacters`, which fires the textStorage delegate
        /// → `applyTextEdits` so the parser stays in sync. Cursor
        /// then moves to the planned UTF-16 position.
        func prepareForInsert(at position: InsertPosition) {
            guard let textView else { return }
            let cursor = textView.selectedRange().location
            // Open the insert-session bracket BEFORE applying the
            // pre-edit so the session covers the o/O/A insertion
            // transformation as well as any subsequent typing — one
            // unified undo step on Esc.
            document.beginInsertSession(at: cursor)
            let plan = CursorMotionEngine.planInsertEntry(
                for: position,
                in: textView.string,
                cursor: cursor
            )
            if let edit = plan.edit,
               textView.shouldChangeText(
                   in: edit.range,
                   replacementString: edit.replacement
               )
            {
                textView.replaceCharacters(in: edit.range, with: edit.replacement)
                textView.didChangeText()
            }
            setCursorAt(utf16Location: plan.cursorAfter)
        }

        // MARK: - Yank / delete / paste

        /// Compute the (text, kind, ranges, cursor-after-yank
        /// position) tuple for the current visual selection. The
        /// shape depends on which visual mode we're in. Returns
        /// nil when there's no active visual mode.
        private struct VisualSnapshot {
            let text: String
            let kind: YankKind
            let structuralFragmentData: Data?
            let ranges: [NSRange] // for delete: replace each in reverse
            let cursorAfter: Int  // start of the selection (vim convention)
        }
        private func snapshotVisualSelection() -> VisualSnapshot? {
            guard let textView else { return nil }
            let nsString = textView.string as NSString
            let mode = document.vimController.mode
            switch mode {
            case .visual:
                let r = textView.selectedRange()
                guard r.length > 0 else { return nil }
                return VisualSnapshot(
                    text: nsString.substring(with: r),
                    kind: .characterwise,
                    structuralFragmentData: nil,
                    ranges: [r],
                    cursorAfter: r.location
                )
            case .visualLine:
                let r = textView.selectedRange()
                guard r.length > 0 else { return nil }
                return VisualSnapshot(
                    text: nsString.substring(with: r),
                    kind: .linewise,
                    structuralFragmentData: nil,
                    ranges: [r],
                    cursorAfter: r.location
                )
            case .visualBlock:
                let ranges = (textView.selectedRanges as? [NSValue])?
                    .map(\.rangeValue) ?? []
                guard !ranges.isEmpty else { return nil }
                let rows = ranges.map { nsString.substring(with: $0) }
                return VisualSnapshot(
                    text: rows.joined(separator: "\n"),
                    kind: .blockwise,
                    structuralFragmentData: nil,
                    ranges: ranges,
                    cursorAfter: ranges.first?.location ?? 0
                )
            case .visualCST:
                // The CST forest is the source of truth in this mode —
                // `textView.selectedRange` only holds a parked caret, not
                // the structural range. Resolve the forest's byte range
                // to an NSRange directly. The yank kind is `.cstForest`
                // so future structural-paste can recognize it; v1 paste
                // treats it as characterwise.
                guard ensureForestIsLive(), let forest = cstForest else { return nil }
                let map = OffsetMap(source: textView.string)
                guard let r = map.nsRange(
                    forByteStart: forest.byteRange.start.rawValue,
                    length: forest.byteRange.length.rawValue
                ), r.length > 0 else { return nil }
                guard let fragment = try? StructuralCSTFragment.capture(forest),
                      let fragmentData = try? fragment.serializedData()
                else { return nil }
                return VisualSnapshot(
                    text: fragment.sourceText,
                    kind: .cstForest,
                    structuralFragmentData: fragmentData,
                    ranges: [r],
                    cursorAfter: r.location
                )
            case .normal, .insert:
                return nil
            }
        }

        func yankSelection() {
            guard let snap = snapshotVisualSelection() else { return }
            yankText(
                snap.text,
                kind: snap.kind,
                structuralFragmentData: snap.structuralFragmentData
            )
            // Mode flip back to .normal happens in the controller's
            // dispatch; cursor placement here so it lands at the
            // start of the previous selection.
            setCursorAt(utf16Location: snap.cursorAfter)
        }

        func deleteSelection() {
            guard let snap = snapshotVisualSelection(),
                  let before = document.makeUndoSnapshot(cursor: snap.cursorAfter)
            else { return }
            let edits = deleteRanges(
                snap.ranges,
                yankAs: snap.kind,
                text: snap.text,
                structuralFragmentData: snap.structuralFragmentData
            )
            setCursorAt(utf16Location: snap.cursorAfter)
            document.recordTextTransaction(
                before: before,
                afterCursor: snap.cursorAfter,
                edits: edits
            )
        }

        func changeSelection() {
            guard let snap = snapshotVisualSelection() else { return }
            document.beginInsertSession(at: snap.cursorAfter)
            _ = deleteRanges(
                snap.ranges,
                yankAs: snap.kind,
                text: snap.text,
                structuralFragmentData: snap.structuralFragmentData
            )
            setCursorAt(utf16Location: snap.cursorAfter)
        }

        /// Vim `u`: walk the Liminal-owned undo history directly and
        /// apply each returned patch to the text view.
        func undo(count: Int) {
            for _ in 0..<max(1, count) {
                guard let navigation = document.undoStep() else { break }
                applyUndoNavigation(navigation)
            }
        }

        func redo(count: Int) {
            for _ in 0..<max(1, count) {
                guard let navigation = document.redoStep() else { break }
                applyUndoNavigation(navigation)
            }
        }

        /// Esc out of insert mode: close the open insert session in
        /// the undo history. The document records one transaction (or
        /// drops the session as a no-op if no text changed).
        func commitInsertSession() {
            let cursor = textView?.selectedRange().location ?? 0
            document.commitInsertSession(at: cursor)
        }

        /// Drive the text view from an undo/redo transaction: apply
        /// only the changed byte ranges, suppressing the delegate so
        /// the already-installed target CST is not reparsed.
        @MainActor
        private func applyUndoNavigation(_ navigation: CSTUndoNavigation) {
            guard let textView else { return }
            let edits = navigation.sourceEdits.sorted {
                $0.range.start.rawValue > $1.range.start.rawValue
            }
            let prior = isApplyingProgrammaticEdit
            isApplyingProgrammaticEdit = true
            for edit in edits {
                guard let nsRange = LiminalTextView.byteRangeToNSRange(
                    edit.range,
                    in: textView.string
                ) else {
                    preconditionFailure("Undo patch range could not be mapped into NSTextView text")
                }
                let replacement = String(decoding: edit.replacementUTF8, as: UTF8.self)
                if textView.shouldChangeText(in: nsRange, replacementString: replacement) {
                    textView.replaceCharacters(in: nsRange, with: replacement)
                    textView.didChangeText()
                }
            }
            isApplyingProgrammaticEdit = prior

            document.vimController.forceNormalMode()
            let safeCursor = max(0, min(
                navigation.target.cursor,
                (textView.string as NSString).length
            ))
            textView.setSelectedRange(NSRange(location: safeCursor, length: 0))
            refreshCursorStyle()
            guard let root = document.currentRootSyntax else {
                preconditionFailure("Undo target tree was not installed before highlight repaint")
            }
            let repaintRanges = LiminalDirtySpan.expandedHighlightRanges(
                root: root,
                touching: navigation.targetPatchRanges
            )
            applyHighlights(inTargetByteRanges: repaintRanges)
        }

        /// Write `text` to the system pasteboard with `kind`. No-op for
        /// empty strings. Shared by visual yank, operator-pending yank,
        /// and the delete-yank step inside `deleteRanges`.
        private func yankText(
            _ text: String,
            kind: YankKind,
            structuralFragmentData: Data? = nil
        ) {
            guard !text.isEmpty else { return }
            SystemPasteboard.write(
                text: text,
                kind: kind,
                structuralFragmentData: structuralFragmentData
            )
        }

        /// Delete the contents of `ranges`. If `text` is non-nil, copy
        /// it to the pasteboard first (vim's delete-implies-yank). Ranges
        /// are replaced in descending order so earlier deletions don't
        /// shift later range indices.
        @discardableResult
        private func deleteRanges(
            _ ranges: [NSRange],
            yankAs kind: YankKind,
            text: String?,
            structuralFragmentData: Data? = nil
        ) -> [TextEdit] {
            guard let textView, !ranges.isEmpty else { return [] }
            let sourceBefore = textView.string
            let edits = ranges
                .filter { $0.length > 0 }
                .map { textEdit(for: $0, replacement: "", in: sourceBefore) }
            if let text {
                yankText(
                    text,
                    kind: kind,
                    structuralFragmentData: structuralFragmentData
                )
            }
            for range in ranges.sorted(by: { $0.location > $1.location }) {
                guard range.length > 0 else { continue }
                if textView.shouldChangeText(in: range, replacementString: "") {
                    textView.replaceCharacters(in: range, with: "")
                    textView.didChangeText()
                }
            }
            return edits
        }

        private func textEdit(
            for range: NSRange,
            replacement: String,
            in source: String
        ) -> TextEdit {
            guard let byteRange = LiminalTextView.utf16RangeToByteRange(
                range,
                in: source
            ) else {
                preconditionFailure("Text edit range could not be mapped into UTF-8 source")
            }
            return TextEdit(
                range: TextRange(
                    start: TextSize(UInt32(byteRange.lowerBound)),
                    length: TextSize(UInt32(byteRange.count))
                ),
                replacement: replacement
            )
        }

        /// Apply a normal-mode operator (`d` / `c` / `y`) over a target
        /// computed by `OperatorRange`. The controller flips to insert
        /// mode after this returns when `op == .change`, so the cursor
        /// must already be at the deletion site by then.
        func applyOperator(
            _ op: VimOperator,
            target: OperatorTarget,
            count: Int
        ) {
            guard let textView else { return }
            let cursor = textView.selectedRange().location
            let result = OperatorRange.resolve(
                op: op, target: target,
                in: textView.string,
                cursor: cursor,
                count: count
            )
            let nsString = textView.string as NSString
            let safeRange = NSRange(
                location: max(0, min(result.range.location, nsString.length)),
                length: max(0, min(result.range.length,
                                   nsString.length - result.range.location))
            )
            let text = safeRange.length > 0
                ? nsString.substring(with: safeRange) : ""
            switch op {
            case .yank:
                yankText(text, kind: result.kind)
                // Vim convention: cursor lands at the start of the
                // yanked range.
                setCursorAt(utf16Location: safeRange.location)
            case .delete:
                guard let before = document.makeUndoSnapshot(cursor: cursor) else { return }
                let edits = deleteRanges([safeRange], yankAs: result.kind, text: text)
                positionCursorAfterDelete(
                    at: safeRange.location, kind: result.kind
                )
                document.recordTextTransaction(
                    before: before,
                    afterCursor: textView.selectedRange().location,
                    edits: edits
                )
            case .change:
                document.beginInsertSession(at: cursor)
                _ = deleteRanges([safeRange], yankAs: result.kind, text: text)
                // For change, cursor sits at the deletion start; the
                // controller flips to insert mode immediately after
                // this returns and calls prepareForInsert(.atCursor).
                textView.setSelectedRange(
                    NSRange(location: safeRange.location, length: 0)
                )
            }
        }

        /// After a charwise delete, cursor lands at the deletion start
        /// — but if that position is now past the new line's content
        /// end (e.g., after `D`), back up to the line's last char.
        /// Linewise deletes leave the cursor at the start of the line
        /// where deletion ended (vim aligns to first non-blank; we
        /// settle for line start as a reasonable v1).
        private func positionCursorAfterDelete(at location: Int, kind: YankKind) {
            guard let textView else { return }
            let nsString = textView.string as NSString
            switch kind {
            case .characterwise, .blockwise, .cstForest:
                // .cstForest deletes share characterwise cursor placement
                // semantics in v1 (the forest's byte range was treated as
                // a contiguous character-mode selection).
                var start = 0, contentEnd = 0, end = 0
                let safe = max(0, min(location, nsString.length))
                nsString.getLineStart(
                    &start, end: &end, contentsEnd: &contentEnd,
                    for: NSRange(location: safe, length: 0)
                )
                let adjusted = (location >= contentEnd && contentEnd > start)
                    ? contentEnd - 1 : location
                setCursorAt(utf16Location: adjusted)
            case .linewise:
                setCursorAt(utf16Location: location)
            }
        }

        func paste(after: Bool) {
            guard let textView,
                  let entry = SystemPasteboard.read()
            else { return }
            if entry.kind == .cstForest {
                pasteStructural(entry, after: after)
                return
            }
            let cursor = textView.selectedRange().location
            guard let before = document.makeUndoSnapshot(cursor: cursor) else { return }
            let plan = PasteEngine.plan(
                text: entry.text,
                kind: entry.kind,
                in: textView.string,
                cursor: cursor,
                after: after
            )
            let edit = textEdit(
                for: plan.range,
                replacement: plan.replacement,
                in: textView.string
            )
            if textView.shouldChangeText(
                in: plan.range,
                replacementString: plan.replacement
            ) {
                textView.replaceCharacters(in: plan.range, with: plan.replacement)
                textView.didChangeText()
            }
            setCursorAt(utf16Location: plan.cursorAfter)
            document.recordTextTransaction(
                before: before,
                afterCursor: plan.cursorAfter,
                edits: [edit]
            )
        }

        private func pasteStructural(
            _ entry: VimPasteboardEntry,
            after: Bool
        ) {
            guard let textView,
                  let fragmentData = entry.structuralFragmentData,
                  let fragment = try? StructuralCSTFragment.decode(data: fragmentData),
                  let tree = document.session.currentTree,
                  let cursorByte = currentCursorByteOffset()
            else {
                NSSound.beep()
                return
            }

            let cursor = textView.selectedRange().location
            guard let before = document.makeUndoSnapshot(cursor: cursor) else { return }
            let oldSource = textView.string
            let structuralPlan: StructuralCSTPastePlan
            do {
                guard let plan = try StructuralCSTPastePlanner.plan(
                    fragment: fragment,
                    in: tree,
                    cursorByteOffset: TextSize(UInt32(cursorByte)),
                    after: after
                ) else {
                    NSSound.beep()
                    return
                }
                structuralPlan = plan
            } catch {
                NSLog("LiminalTextView: structural paste planning failed: \(error)")
                NSSound.beep()
                return
            }

            guard let nsRange = LiminalTextView.byteRangeToNSRange(
                structuralPlan.edit.range,
                in: oldSource
            ) else {
                NSSound.beep()
                return
            }

            guard document.applyStructuralReplacement(
                target: structuralPlan.target,
                replacement: structuralPlan.replacement,
                edits: [structuralPlan.edit]
            ) else { return }

            let prior = isApplyingProgrammaticEdit
            isApplyingProgrammaticEdit = true
            let replacement = String(
                decoding: structuralPlan.edit.replacementUTF8,
                as: UTF8.self
            )
            if textView.shouldChangeText(in: nsRange, replacementString: replacement) {
                textView.replaceCharacters(in: nsRange, with: replacement)
                textView.didChangeText()
            }
            isApplyingProgrammaticEdit = prior

            #if DEBUG
            precondition(
                textView.string == document.session.source,
                "Structural paste text view and target CST source diverged"
            )
            #endif

            setCursor(byteOffset: Int(structuralPlan.cursorByteOffset.rawValue))
            document.recordTextTransaction(
                before: before,
                afterCursor: textView.selectedRange().location,
                edits: [structuralPlan.edit]
            )
            guard let root = document.currentRootSyntax else { return }
            let repaintRanges = LiminalDirtySpan.expandedHighlightRanges(
                root: root,
                touching: [structuralPlan.insertedRange]
            )
            applyHighlights(inTargetByteRanges: repaintRanges)
        }

        /// Pull the cached `DocumentIndex` from the vault entry, or
        /// build it on demand from the current root if the cache hasn't
        /// caught up. Returns nil only when there is no CST at all
        /// (e.g., parse never completed).
        private func currentDocumentIndex() -> DocumentIndex? {
            if let url = document.fileURL {
                let entry = VaultRegistry.shared.entry(for: url)
                let canonical = VaultRegistry.canonicalNoteURL(for: url)
                if let cached = entry.indexes[canonical] {
                    return cached
                }
            }
            // Cache miss or untitled: build fresh from the CST.
            guard let root = document.currentRootSyntax else { return nil }
            return DocumentIndex.build(root: root)
        }

        private func activate(
            decision: LinkActivationDecision,
            in docIndex: DocumentIndex,
            currentURL: URL,
            clickUTF16Index: Int,
            disposition: NavigationDisposition
        ) -> Bool {
            switch decision {
            case .openExternal(let url):
                NSWorkspace.shared.open(url)
                return true

            case .open(let noteID, let anchor):
                if disposition == .replaceInCurrentTab, noteID == currentURL {
                    if let anchor, let byteOffset = docIndex.blockOffset(for: anchor) {
                        scrollToByteOffset(Int(byteOffset.rawValue))
                    } else if anchor != nil {
                        // Anchor missing despite within-doc target —
                        // jump to top so the user sees something
                        // happened.
                        scrollToByteOffset(0)
                    }
                    return true
                }
                NavigationRouter.shared.navigate(
                    to: noteID,
                    anchor: anchor,
                    disposition: disposition
                )
                return true

            case .createNote(let relativePath):
                createAndOpenNote(
                    relativePath: relativePath,
                    vaultRoot: VaultRegistry.canonicalVaultRoot(for: currentURL),
                    disposition: disposition
                )
                return true

            case .showAmbiguous(let candidates):
                showAmbiguityMenu(
                    candidates: candidates,
                    at: clickUTF16Index,
                    currentURL: currentURL,
                    disposition: disposition
                )
                return true

            case .noAction:
                return true
            }
        }

        /// Pop up an `NSMenu` listing each candidate note (vault-
        /// relative path). Selecting one re-issues an explicit
        /// navigation through the router. Anchored at the
        /// clicked-character's glyph rect in the text view's local
        /// coordinates.
        private func showAmbiguityMenu(
            candidates: [URL],
            at utf16Index: Int,
            currentURL: URL,
            disposition: NavigationDisposition
        ) {
            guard let textView else { return }
            let menu = NSMenu(title: "Open which note?")
            for url in candidates {
                let item = NSMenuItem(
                    title: vaultRelativeDisplayPath(for: url, currentURL: currentURL),
                    action: #selector(activateAmbiguousCandidate(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = AmbiguousNavigationChoice(
                    url: url,
                    disposition: disposition
                )
                menu.addItem(item)
            }
            let anchor = pointForCharacter(utf16Index, in: textView)
            menu.popUp(positioning: nil, at: anchor, in: textView)
        }

        @objc private func activateAmbiguousCandidate(_ sender: NSMenuItem) {
            guard let choice = sender.representedObject as? AmbiguousNavigationChoice else { return }
            NavigationRouter.shared.navigate(
                to: choice.url,
                anchor: nil,
                disposition: choice.disposition
            )
        }

        /// Vault-relative display string for a candidate URL. Falls
        /// back to the file's last path component if the URL isn't
        /// actually under the current vault root.
        private func vaultRelativeDisplayPath(for url: URL, currentURL: URL) -> String {
            let vaultRoot = VaultRegistry.canonicalVaultRoot(for: currentURL)
            let prefix = vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/"
            if url.path.hasPrefix(prefix) {
                return String(url.path.dropFirst(prefix.count))
            }
            return url.lastPathComponent
        }

        /// Local-coordinate position to anchor a popup menu at the
        /// glyph for `utf16Index`. Falls back to the text view's
        /// origin if the layout manager can't produce a rect.
        private func pointForCharacter(_ utf16Index: Int, in textView: NSTextView) -> NSPoint {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return .zero }
            let textLength = (textView.string as NSString).length
            let clampedIndex = max(0, min(utf16Index, max(textLength - 1, 0)))
            guard textLength > 0 else { return textView.textContainerOrigin }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            return NSPoint(
                x: rect.origin.x + textView.textContainerOrigin.x,
                y: rect.origin.y + rect.height + textView.textContainerOrigin.y
            )
        }

        /// Materialize an unresolved wikilink target as a real
        /// `.lim` file inside the current vault, then route a
        /// navigation through the router so the new doc opens.
        /// Subdirectories in `relativePath` are created as needed.
        private func createAndOpenNote(
            relativePath: String,
            vaultRoot: URL,
            disposition: NavigationDisposition
        ) {
            let path = relativePath.lowercased().hasSuffix(".lim")
                ? relativePath
                : relativePath + ".lim"
            let newFileURL = vaultRoot.appendingPathComponent(path)
            let parent = newFileURL.deletingLastPathComponent()

            do {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
            } catch {
                NSLog("LiminalTextView: createDirectory failed for \(parent.path): \(error)")
                return
            }

            if !FileManager.default.fileExists(atPath: newFileURL.path) {
                let created = FileManager.default.createFile(
                    atPath: newFileURL.path,
                    contents: Data(),
                    attributes: nil
                )
                if !created {
                    NSLog("LiminalTextView: createFile failed for \(newFileURL.path)")
                    return
                }
            }
            NavigationRouter.shared.navigate(
                to: newFileURL,
                anchor: nil,
                disposition: disposition
            )
        }

        /// Move the cursor (and viewport) to a byte offset within the
        /// current document. Used by Cmd-click within-doc anchor jumps
        /// and (slice 5) by incoming `NavigationRequest`s targeted at
        /// this open document.
        func scrollToByteOffset(_ byteOffset: Int) {
            guard let textView else { return }
            let range = CambiumCore.TextRange(
                start: TextSize(UInt32(max(0, byteOffset))),
                length: TextSize(0)
            )
            guard let nsRange = LiminalTextView.byteRangeToNSRange(range, in: textView.string)
            else { return }
            setCursorAt(utf16Location: nsRange.location)
            textView.scrollRangeToVisible(NSRange(location: nsRange.location, length: 0))
        }

        // MARK: - Cursor helpers

        private func currentCursorByteOffset() -> Int? {
            guard let textView else { return nil }
            // Use the head in visual modes so motion handlers (which
            // call into the byte-offset domain — structural, viewport,
            // display-line) advance from the moving end of the
            // selection, not from the anchor. See
            // `currentMotionCursorUTF16` for the full explanation.
            let utf16 = currentMotionCursorUTF16()
            let cursorNSRange = NSRange(location: utf16, length: 0)
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
            switch document.vimController.mode {
            case .normal:
                let length = (clampedLocation < textLength) ? 1 : 0
                textView.setSelectedRange(
                    NSRange(location: clampedLocation, length: length)
                )
            case .insert:
                textView.setSelectedRange(
                    NSRange(location: clampedLocation, length: 0)
                )
            case .visual:
                extendCharwiseSelection(toUTF16: clampedLocation)
            case .visualLine:
                extendLinewiseSelection(toUTF16: clampedLocation)
            case .visualBlock:
                extendBlockwiseSelection(toUTF16: clampedLocation)
            case .visualCST:
                // .visualCST owns the text-view selection via
                // mirrorCSTSelection. Generic UTF-16 cursor placement
                // doesn't apply here: text-cursor motions aren't bound
                // in .visualCST, so this path shouldn't fire — but if it
                // does (e.g. a future code path), preserve the forest's
                // range rather than collapse it.
                break
            }
        }

        // MARK: - Visual mode entry + selection extension

        /// Seed the visual-mode anchor and expand the selection for
        /// the kind we just entered. Called by the controller after
        /// it has flipped to the corresponding visual mode.
        func enterVisualMode(kind: VisualKind) {
            guard let textView else { return }
            let cursor = textView.selectedRange().location
            visualHeadUTF16 = cursor
            switch kind {
            case .charwise:
                visualAnchorUTF16 = cursor
                visualBlockAnchor = nil
                extendCharwiseSelection(toUTF16: cursor)
            case .linewise:
                visualAnchorUTF16 = cursor
                visualBlockAnchor = nil
                extendLinewiseSelection(toUTF16: cursor)
            case .blockwise:
                let (line, column) = lineAndColumn(
                    forUTF16: cursor,
                    in: textView.string as NSString
                )
                visualBlockAnchor = (line, column)
                visualAnchorUTF16 = nil
                extendBlockwiseSelection(toUTF16: cursor)
            }
        }

        /// Charwise selection: spans `[min(anchor, head), max + 1)`.
        /// Vim's visual is inclusive of the head cell, hence the +1.
        private func extendCharwiseSelection(toUTF16 head: Int) {
            guard let textView, let anchor = visualAnchorUTF16 else { return }
            let textLength = (textView.string as NSString).length
            let clampedHead = max(0, min(head, textLength))
            visualHeadUTF16 = clampedHead
            let lo = max(0, min(anchor, clampedHead))
            let hi = max(anchor, clampedHead)
            let endExclusive = min(hi + 1, textLength)
            let length = max(0, endExclusive - lo)
            textView.setSelectedRange(NSRange(location: lo, length: length))
        }

        /// Linewise selection: snap to whole-line range from the
        /// anchor's line.start to the head's line.end (inclusive of
        /// the trailing newline so multi-line yanks behave right).
        private func extendLinewiseSelection(toUTF16 head: Int) {
            guard let textView, let anchor = visualAnchorUTF16 else { return }
            let nsString = textView.string as NSString
            let clampedHead = max(0, min(head, nsString.length))
            visualHeadUTF16 = clampedHead
            let anchorLine = lineRange(at: anchor, in: nsString)
            let headLine = lineRange(at: clampedHead, in: nsString)
            let lo = min(anchorLine.start, headLine.start)
            let hi = max(anchorLine.end, headLine.end)
            textView.setSelectedRange(NSRange(location: lo, length: hi - lo))
        }

        /// Blockwise selection: per-row UTF-16 ranges between the
        /// anchor and head columns, clamped to each line's content
        /// length. Rendered as discontiguous selection.
        private func extendBlockwiseSelection(toUTF16 head: Int) {
            guard let textView, let anchor = visualBlockAnchor else { return }
            let nsString = textView.string as NSString
            let clampedHead = max(0, min(head, nsString.length))
            visualHeadUTF16 = clampedHead
            let (headLine, headCol) = lineAndColumn(forUTF16: clampedHead, in: nsString)
            let minLine = min(anchor.line, headLine)
            let maxLine = max(anchor.line, headLine)
            let minCol = min(anchor.column, headCol)
            let maxCol = max(anchor.column, headCol)

            var ranges: [NSValue] = []
            ranges.reserveCapacity(maxLine - minLine + 1)
            for ln in minLine...maxLine {
                guard let info = lineRange(forLineIndex: ln, in: nsString)
                else { continue }
                let lineLen = info.contentEnd - info.start
                let colStart = min(minCol, lineLen)
                let colEnd = min(maxCol + 1, lineLen)
                let length = max(0, colEnd - colStart)
                ranges.append(NSValue(range: NSRange(
                    location: info.start + colStart,
                    length: length
                )))
            }
            if !ranges.isEmpty {
                textView.selectedRanges = ranges
            }
        }

        // MARK: - Visual CST mode

        /// Build the entry-point forest at the cursor's byte offset and
        /// mirror its range into the text view. If no navigable forest
        /// covers the cursor (empty document, etc.) we force the
        /// controller back to normal so the user doesn't sit in an
        /// empty `.visualCST`.
        func enterCSTVisualMode() {
            guard let textView,
                  let tree = document.session.currentTree
            else {
                document.vimController.forceNormalMode()
                return
            }
            let utf16Cursor = textView.selectedRange().location
            let source = textView.string
            let byte = byteOffset(forUTF16: utf16Cursor, in: source)
            guard let forest = LiminalForest.cstVisualEntry(
                at: TextSize(UInt32(byte)),
                in: tree
            ) else {
                document.vimController.forceNormalMode()
                return
            }
            cstForest = forest
            mirrorCSTSelection()
        }

        /// Slide the forest to a new singleton via `motion`, repeated
        /// `count` times. Stops at the first step that has no successor
        /// (rather than failing the whole call) so `9j` on a list of
        /// five items lands on the last item instead of doing nothing.
        func cstNavigate(_ motion: CSTMotion, count: Int) {
            guard ensureForestIsLive(), var forest = cstForest else { return }
            for _ in 0..<max(1, count) {
                let next: LiminalForest?
                switch motion {
                case .parent:           next = forest.parentForest()
                case .firstChild:       next = forest.firstChildForest()
                case .nextSibling:      next = forest.slidForward()
                case .previousSibling:  next = forest.slidBackward()
                }
                guard let next else { break }
                forest = next
            }
            cstForest = forest
            mirrorCSTSelection()
        }

        /// Extend the forest's head endpoint `count` siblings in
        /// `motion`'s direction. Anchor stays fixed. Parent/firstChild
        /// don't extend (no meaning), so those cases are no-ops.
        func extendCSTSelection(_ motion: CSTMotion, count: Int) {
            guard ensureForestIsLive(), var forest = cstForest else { return }
            for _ in 0..<max(1, count) {
                let next: LiminalForest?
                switch motion {
                case .nextSibling:      next = forest.extendedForward()
                case .previousSibling:  next = forest.extendedBackward()
                case .parent, .firstChild:
                    return
                }
                guard let next else { break }
                forest = next
            }
            cstForest = forest
            mirrorCSTSelection()
        }

        /// Swap anchor and head endpoints. The visible byte range is
        /// unchanged for symmetric ends — we still re-mirror so any
        /// future cursor-at-head polish (vim's `o` jumps the caret to
        /// the other end of the selection) has a hook.
        func swapCSTEnds() {
            guard ensureForestIsLive(), let forest = cstForest else { return }
            cstForest = forest.withEndsSwapped()
            mirrorCSTSelection()
        }

        // MARK: - Visual CST helpers

        /// Validate that the active forest still references the document's
        /// current tree. The Coordinator clears the forest on mode-leave,
        /// but a programmatic edit that swapped the tree without flipping
        /// the mode would leave a stale `SyntaxNodeHandle` in
        /// `cstForest`. Returns `false` (and clears the field) when the
        /// tree identity has changed.
        @discardableResult
        private func ensureForestIsLive() -> Bool {
            guard let forest = cstForest else { return false }
            guard let liveTreeID = document.session.currentTree?.treeID,
                  forest.treeID == liveTreeID
            else {
                cstForest = nil
                return false
            }
            return true
        }

        /// Push the active forest's byte range to `VimTextView`'s
        /// dedicated overlay property and park the system caret at the
        /// selection's start.
        ///
        /// We deliberately do *not* mirror the forest into
        /// `textView.setSelectedRange(_:)`: AppKit's native selection
        /// background would paint on top of our teal overlay, doubling
        /// the highlight, and the existing `selectedTextAttributes`
        /// machinery is hard to override without breaking other modes
        /// (it's how the normal-mode block cursor draws its fill).
        /// Operators in `.visualCST` read directly from `cstForest`
        /// instead of `textView.selectedRange` (see
        /// `snapshotVisualSelection`).
        private func mirrorCSTSelection() {
            guard let textView, let forest = cstForest else { return }
            let map = OffsetMap(source: textView.string)
            let byteRange = forest.byteRange
            let nsRange = map.nsRange(
                forByteStart: byteRange.start.rawValue,
                length: byteRange.length.rawValue
            )
            textView.cstSelectionRange = nsRange
            // Park the system caret at the overlay's start so AppKit's
            // blinking insertion point sits at one edge of the
            // structural selection rather than blinking inside it.
            if let nsRange {
                textView.setSelectedRange(NSRange(location: nsRange.location, length: 0))
            }
        }

        /// Convert a UTF-16 cursor location to a UTF-8 byte offset by
        /// walking the source's UTF-8 view. Called once per CST entry,
        /// so the O(cursor position) walk is acceptable; if a hot path
        /// ever needs this, fold it into `OffsetMap` as the reverse
        /// direction.
        private func byteOffset(forUTF16 utf16Cursor: Int, in source: String) -> Int {
            let utf16View = source.utf16
            let clamped = max(0, min(utf16Cursor, utf16View.count))
            let idx16 = utf16View.index(utf16View.startIndex, offsetBy: clamped)
            return source.utf8.distance(from: source.utf8.startIndex, to: idx16)
        }

        // MARK: - Line geometry helpers (UTF-16, NSString-based)

        private func lineRange(
            at utf16Location: Int,
            in nsString: NSString
        ) -> (start: Int, contentEnd: Int, end: Int) {
            var start = 0
            var contentEnd = 0
            var end = 0
            let safe = max(0, min(utf16Location, nsString.length))
            nsString.getLineStart(
                &start, end: &end, contentsEnd: &contentEnd,
                for: NSRange(location: safe, length: 0)
            )
            return (start, contentEnd, end)
        }

        /// (line index, column) for a UTF-16 offset. Line index is
        /// 0-based; column is 0-based UTF-16 offset within the line.
        private func lineAndColumn(
            forUTF16 utf16Location: Int,
            in nsString: NSString
        ) -> (line: Int, column: Int) {
            let safe = max(0, min(utf16Location, nsString.length))
            var line = 0
            var cursor = 0
            while cursor < safe {
                var s = 0, e = 0
                nsString.getLineStart(
                    &s, end: &e, contentsEnd: nil,
                    for: NSRange(location: cursor, length: 0)
                )
                if e <= cursor || e > safe { break }
                cursor = e
                line += 1
            }
            // Column: distance from this line's start.
            var lineStart = 0
            nsString.getLineStart(
                &lineStart, end: nil, contentsEnd: nil,
                for: NSRange(location: safe, length: 0)
            )
            return (line, safe - lineStart)
        }

        /// Walk to the Nth line from the start of the document and
        /// return its (start, contentEnd, end). Returns nil when N
        /// exceeds the document's line count.
        private func lineRange(
            forLineIndex target: Int,
            in nsString: NSString
        ) -> (start: Int, contentEnd: Int, end: Int)? {
            guard target >= 0, nsString.length > 0 else {
                return target == 0 ? (0, 0, 0) : nil
            }
            var cursor = 0
            var current = 0
            while cursor < nsString.length {
                var s = 0, c = 0, e = 0
                nsString.getLineStart(
                    &s, end: &e, contentsEnd: &c,
                    for: NSRange(location: cursor, length: 0)
                )
                if current == target { return (s, c, e) }
                if e <= cursor { return nil }
                cursor = e
                current += 1
            }
            // Past the last line terminator: a trailing empty line
            // exists if the doc ends in `\n`. Otherwise no more
            // lines.
            if current == target {
                return (nsString.length, nsString.length, nsString.length)
            }
            return nil
        }

        /// Re-apply highlights to the entire text storage from the current
        /// parse result. Called after every user edit, on initial display,
        /// and when the source is replaced externally (document load).
        /// Repaint syntax highlights. When `editedRange` is non-nil the
        /// pass is scoped to the line(s) around the edit (plus one line
        /// of buffer on each side) — typing into a paragraph in a
        /// 1.2 MB doc no longer rewrites attributes across the whole
        /// document. With `editedRange == nil` (initial load, preference
        /// toggle, programmatic source replace) we still highlight the
        /// full range.
        func applyHighlights(in editedRange: NSRange? = nil) {
            if editedRange != nil {
                applyHighlights(scope: .parserDirtyRange)
            } else {
                applyHighlights(scope: .fullDocument)
            }
        }

        private func applyHighlights(inTargetByteRanges ranges: [CambiumCore.TextRange]) {
            applyHighlights(scope: .explicitByteRanges(ranges))
        }

        private func applyHighlights(scope: HighlightRepaintScope) {
            guard let textView,
                  let storage = textView.textStorage
            else { return }

            let storageLen = storage.length
            let source = storage.string
            let parsed = document.session.parseResult
            let root = document.currentRootSyntax

            let paintScopes: [HighlightPaintScope]
            switch scope {
            case .fullDocument:
                paintScopes = [
                    HighlightPaintScope(
                        byteRange: nil,
                        nsRange: NSRange(location: 0, length: storageLen),
                        offsetMap: OffsetMap(source: source)
                    )
                ]
            case .parserDirtyRange:
                if let changed = parsed?.changedByteRange,
                   let paintScope = Self.makeHighlightPaintScope(
                    source: source,
                    byteRange: changed
                   )
                {
                    paintScopes = [paintScope]
                } else {
                    paintScopes = [
                        HighlightPaintScope(
                            byteRange: nil,
                            nsRange: NSRange(location: 0, length: storageLen),
                            offsetMap: OffsetMap(source: source)
                        )
                    ]
                }
            case .explicitByteRanges(let ranges):
                paintScopes = ranges.map { range in
                    guard let paintScope = Self.makeHighlightPaintScope(
                        source: source,
                        byteRange: range
                    ) else {
                        preconditionFailure("Explicit highlight repaint range is outside the text storage")
                    }
                    return paintScope
                }
            }
            guard !paintScopes.isEmpty else {
                textView.typingAttributes = theme.defaultAttributes
                return
            }

            isApplyingProgrammaticEdit = true
            storage.beginEditing()
            for paintScope in paintScopes {
                // Reset to base style first so toggling off cleanly
                // removes any previously-painted highlight attributes
                // within scope.
                storage.setAttributes(theme.defaultAttributes, range: paintScope.nsRange)

                guard EditorPreferences.shared.highlightingEnabled,
                      let root
                else { continue }

                let spans = paintScope.byteRange.map {
                    highlighter.spans(for: root, in: $0)
                } ?? highlighter.spans(for: root)
                for span in spans {
                    guard let nsRange = paintScope.offsetMap.nsRange(
                        forByteStart: span.range.start.rawValue,
                        length: span.range.length.rawValue
                    ) else { continue }
                    let attrs = theme.attributes(
                        for: span.category,
                        modifiers: span.modifiers
                    )
                    storage.addAttributes(attrs, range: nsRange)
                }
            }

            storage.endEditing()
            isApplyingProgrammaticEdit = false

            textView.typingAttributes = theme.defaultAttributes
        }

        private static func makeHighlightPaintScope(
            source: String,
            byteRange: CambiumCore.TextRange
        ) -> HighlightPaintScope? {
            guard let map = makeScopedOffsetMap(source: source, byteRange: byteRange),
                  let nsRange = map.nsRange(
                    forByteStart: byteRange.start.rawValue,
                    length: byteRange.length.rawValue
                  )
            else { return nil }
            return HighlightPaintScope(
                byteRange: byteRange,
                nsRange: nsRange,
                offsetMap: map
            )
        }

        /// Build a scope-local OffsetMap covering exactly `byteRange`.
        /// Returns `nil` when `byteRange` is degenerate or falls outside
        /// the source's UTF-8 byte count — in which case
        /// ``applyHighlights(in:)`` falls back to a full-document map.
        private static func makeScopedOffsetMap(
            source: String,
            byteRange: CambiumCore.TextRange
        ) -> OffsetMap? {
            let lower = Int(byteRange.start.rawValue)
            let upper = lower + Int(byteRange.length.rawValue)
            guard lower >= 0, upper >= lower, upper <= source.utf8.count else {
                return nil
            }
            return OffsetMap(source: source, byteRange: lower..<upper)
        }

        /// Expand an NSRange to the line(s) it touches, plus one full
        /// line of buffer on each side. The buffer captures cross-line
        /// tokens (e.g., the closing fence of a code block on the next
        /// line) without re-touching the whole document.
        private static func lineNeighborhood(
            of range: NSRange,
            in source: NSString,
            storageLength: Int
        ) -> NSRange {
            var lineStart = 0
            var lineEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: nil,
                for: range
            )
            var beforeStart = lineStart
            if lineStart > 0 {
                var s = 0
                var e = 0
                source.getLineStart(
                    &s,
                    end: &e,
                    contentsEnd: nil,
                    for: NSRange(location: lineStart - 1, length: 0)
                )
                beforeStart = s
            }
            var afterEnd = lineEnd
            if lineEnd < storageLength {
                var s = 0
                var e = 0
                source.getLineStart(
                    &s,
                    end: &e,
                    contentsEnd: nil,
                    for: NSRange(location: lineEnd, length: 0)
                )
                afterEnd = e
            }
            return NSRange(
                location: beforeStart,
                length: afterEnd - beforeStart
            )
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

private final class AmbiguousNavigationChoice: NSObject {
    let url: URL
    let disposition: NavigationDisposition

    init(url: URL, disposition: NavigationDisposition) {
        self.url = url
        self.disposition = disposition
    }
}
