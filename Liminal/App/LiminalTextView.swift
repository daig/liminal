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
        textView.delegate = context.coordinator
        textView.vimController = document.vimController
        textView.linkActivationDelegate = context.coordinator
        textView.linkHoverDelegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.hoverPreviewController.attach(to: textView)
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
    final class Coordinator: NSObject, NSTextStorageDelegate, NSTextViewDelegate, VimControllerDelegate, VimTextViewLinkActivationDelegate, VimTextViewLinkHoverDelegate, NavigationSubscriber {
        let document: LiminalSourceDocument
        weak var textView: VimTextView?
        var isApplyingProgrammaticEdit = false

        let highlighter = LiminalHighlighter()
        let theme = LiminalHighlightTheme.default

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
            modeObservation = controller.$mode.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCursorStyle()
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
                document.applyTextEdits([edit])
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
        /// Slice 3 wires within-doc anchor jumps and external URIs.
        /// Cross-document targets (`open(noteID, anchor)` with
        /// `noteID != currentURL`), `createNote`, and `showAmbiguous`
        /// claim the click but no-op until the navigation router and
        /// ambiguity popover land.
        func vimTextView(_ view: VimTextView, didCmdClickAt utf16Index: Int) -> Bool {
            // Click takes over from hover; close any visible popover
            // so it doesn't linger over the action.
            hoverPreviewController.cancelForClick()
            guard let textView,
                  let url = document.fileURL,
                  let byteRange = LiminalTextView.utf16RangeToByteRange(
                      NSRange(location: utf16Index, length: 0),
                      in: textView.string
                  ),
                  let docIndex = currentDocumentIndex()
            else { return false }

            let canonicalURL = VaultRegistry.canonicalNoteURL(for: url)
            let entry = VaultRegistry.shared.entry(for: url)
            guard let result = CmdClickHandler.decision(
                atByteOffset: TextSize(UInt32(byteRange.lowerBound)),
                documentURL: canonicalURL,
                documentIndex: docIndex,
                vaultLinkIndex: entry.linkIndex
            ) else { return false }

            return activate(
                decision: result.decision,
                in: docIndex,
                currentURL: canonicalURL,
                clickUTF16Index: utf16Index
            )
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
            clickUTF16Index: Int
        ) -> Bool {
            switch decision {
            case .openExternal(let url):
                NSWorkspace.shared.open(url)
                return true

            case .open(let noteID, let anchor):
                if noteID == currentURL {
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
                NavigationRouter.shared.navigate(to: noteID, anchor: anchor)
                return true

            case .createNote(let relativePath):
                createAndOpenNote(
                    relativePath: relativePath,
                    vaultRoot: VaultRegistry.canonicalVaultRoot(for: currentURL)
                )
                return true

            case .showAmbiguous(let candidates):
                showAmbiguityMenu(
                    candidates: candidates,
                    at: clickUTF16Index,
                    currentURL: currentURL
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
            currentURL: URL
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
                item.representedObject = url
                menu.addItem(item)
            }
            let anchor = pointForCharacter(utf16Index, in: textView)
            menu.popUp(positioning: nil, at: anchor, in: textView)
        }

        @objc private func activateAmbiguousCandidate(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            NavigationRouter.shared.navigate(to: url, anchor: nil)
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
        private func createAndOpenNote(relativePath: String, vaultRoot: URL) {
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
            NavigationRouter.shared.navigate(to: newFileURL, anchor: nil)
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
        /// Repaint syntax highlights. When `editedRange` is non-nil the
        /// pass is scoped to the line(s) around the edit (plus one line
        /// of buffer on each side) — typing into a paragraph in a
        /// 1.2 MB doc no longer rewrites attributes across the whole
        /// document. With `editedRange == nil` (initial load, preference
        /// toggle, programmatic source replace) we still highlight the
        /// full range.
        func applyHighlights(in editedRange: NSRange? = nil) {
            guard let textView,
                  let storage = textView.textStorage
            else { return }

            let storageLen = storage.length
            let source = storage.string
            let parsed = document.session.parseResult

            // Scope decision: the parse already knows which contiguous
            // byte range it just re-walked (skip-clean-regions' dirty
            // span, plus boundary halo and sentinel expansion). When the
            // call site signals a keystroke (`editedRange != nil`) and
            // the parse produced a `changedByteRange`, use it as the
            // repaint scope. Otherwise repaint the whole document —
            // initial display, preference toggle, cold parse, or any
            // path where the parse fell back to a full rewrite.
            let scopedByteRange: CambiumCore.TextRange?
            let offsetMap: OffsetMap
            let scopeNSRange: NSRange
            if editedRange != nil,
               let changed = parsed?.changedByteRange,
               let map = Self.makeScopedOffsetMap(source: source, byteRange: changed),
               let nsRange = map.nsRange(
                forByteStart: changed.start.rawValue,
                length: changed.length.rawValue
               )
            {
                scopedByteRange = changed
                offsetMap = map
                scopeNSRange = nsRange
            } else {
                scopedByteRange = nil
                offsetMap = OffsetMap(source: source)
                scopeNSRange = NSRange(location: 0, length: storageLen)
            }

            isApplyingProgrammaticEdit = true
            storage.beginEditing()
            // Reset to base style first so toggling off cleanly removes
            // any previously-painted highlight attributes within scope.
            storage.setAttributes(theme.defaultAttributes, range: scopeNSRange)

            if EditorPreferences.shared.highlightingEnabled,
               let parsed
            {
                let spans: [HighlightSpan]
                if let scope = scopedByteRange {
                    spans = highlighter.spans(for: parsed.rootSyntax, in: scope)
                } else {
                    spans = highlighter.spans(for: parsed.rootSyntax)
                }
                for span in spans {
                    guard let nsRange = offsetMap.nsRange(
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
