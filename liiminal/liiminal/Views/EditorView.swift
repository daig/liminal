import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    let editorViewModel: EditorViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer()
        textContainer.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textLayoutManager.textContainer = textContainer

        let textView = VimTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false  // starts in normal mode
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = HighlightTheme.defaultFont
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.delegate = context.coordinator
        textView.vimDelegate = context.coordinator
        context.coordinator.textView = textView

        if let note = editorViewModel.currentNote {
            textView.loadDocumentText(
                note.content,
                undoHistory: editorViewModel.undoHistory(for: note)
            )
            context.coordinator.currentNoteID = note.id
            context.coordinator.applyHighlighting()
        } else {
            textView.loadDocumentText(
                "",
                undoHistory: editorViewModel.undoHistory(for: nil)
            )
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let newNoteID = editorViewModel.currentNote?.id
        if context.coordinator.currentNoteID != newNoteID {
            context.coordinator.currentNoteID = newNoteID
            textView.loadDocumentText(
                editorViewModel.currentNote?.content ?? "",
                undoHistory: editorViewModel.undoHistory(for: editorViewModel.currentNote)
            )
            textView.scrollToBeginningOfDocument(nil)
            context.coordinator.applyHighlighting()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(editorViewModel: editorViewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, VimTextViewDelegate {
        var textView: VimTextView?
        var currentNoteID: URL?
        let editorViewModel: EditorViewModel
        private var isHighlighting = false
        private var isEditing = false

        /// Cell content ranges within tables, sorted by location.
        /// Cursor positions from range.location through NSMaxRange(range) are valid.
        var tableCellRanges: [NSRange] = []
        /// Full table block ranges, sorted by location.
        var tableFramingRanges: [NSRange] = []

        init(editorViewModel: EditorViewModel) {
            self.editorViewModel = editorViewModel
        }

        // MARK: - Vim Delegate

        func vimTextView(_ textView: VimTextView, didChangeMode mode: VimMode) {
            editorViewModel.vimMode = mode
        }

        func vimTextView(_ textView: VimTextView, didChangeStatus status: VimStatusPresentation) {
            editorViewModel.vimStatus = status
            editorViewModel.vimMode = status.mode
        }

        func vimTextView(_ textView: VimTextView, didChangeHintCandidate candidate: VimHintCandidate?) {
            editorViewModel.updateVimHintCandidate(candidate)
        }

        // MARK: - Table Position Queries

        /// Is this cursor position inside a table?
        private func isInTable(at pos: Int) -> Bool {
            tableFramingRanges.contains { pos >= $0.location && pos < NSMaxRange($0) }
        }

        /// Is this cursor position inside cell content (or at its boundary)?
        /// Uses inclusive end so cursor can rest at the end of cell content.
        private func isInCellContent(at pos: Int) -> Bool {
            tableCellRanges.contains { pos >= $0.location && pos <= NSMaxRange($0) }
        }

        /// Is this position in a table but NOT in cell content?
        private func isInTableFraming(at pos: Int) -> Bool {
            isInTable(at: pos) && !isInCellContent(at: pos)
        }

        /// Next cell start strictly after `pos`.
        private func nextCellStart(after pos: Int) -> Int? {
            for range in tableCellRanges where range.location > pos {
                return range.location
            }
            // Past last cell — return end of table
            for tr in tableFramingRanges where pos < NSMaxRange(tr) {
                return NSMaxRange(tr)
            }
            return nil
        }

        /// Previous cell end strictly before `pos`.
        private func prevCellEnd(before pos: Int) -> Int? {
            for range in tableCellRanges.reversed() {
                if NSMaxRange(range) < pos {
                    return NSMaxRange(range)
                }
            }
            // Before first cell — return start of table (which is before framing)
            for tr in tableFramingRanges where pos > tr.location {
                return max(tr.location - 1, 0)
            }
            return nil
        }

        // MARK: - Command Handling

        func textView(
            _ textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText(
                    "    ", replacementRange: textView.selectedRange())
                return true
            }

            let pos = textView.selectedRange().location

            // Right arrow at end of cell → skip framing to next cell start
            if commandSelector == #selector(NSResponder.moveRight(_:)) {
                for range in tableCellRanges {
                    if pos == NSMaxRange(range) {
                        if let next = nextCellStart(after: pos) {
                            setSelection(in: textView, to: next)
                            return true
                        }
                    }
                }
            }

            // Left arrow at start of cell → skip framing to prev cell end
            if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                for range in tableCellRanges {
                    if pos == range.location {
                        if let prev = prevCellEnd(before: pos) {
                            setSelection(in: textView, to: prev)
                            return true
                        }
                    }
                }
            }

            // Backspace at start of cell → jump to prev cell end, no deletion
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                for range in tableCellRanges {
                    if pos == range.location {
                        if let prev = prevCellEnd(before: pos) {
                            setSelection(in: textView, to: prev)
                        }
                        return true  // always consume — never delete into framing
                    }
                }
            }

            return false
        }

        private func setSelection(in textView: NSTextView, to pos: Int) {
            textView.setSelectedRange(NSRange(location: pos, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting else { return }
            guard let textView = notification.object as? NSTextView else { return }
            editorViewModel.textDidChange(textView.string)
            applyHighlighting()
        }

        // MARK: - Highlighting

        func applyHighlighting() {
            guard let textView = textView else { return }
            guard let textStorage = textView.textStorage else { return }
            let document = editorViewModel.document
            let length = textStorage.length
            guard length > 0 else { return }

            isHighlighting = true

            // Rebuild table cell map from the document model
            tableCellRanges.removeAll()
            tableFramingRanges.removeAll()
            var mapOffset = 0
            for block in document.blocks {
                if case .table(let t) = block {
                    buildTableCellMap(t, at: mapOffset)
                }
                mapOffset += block.sourceLength
            }

            textStorage.beginEditing()

            // Reset to defaults
            let fullRange = NSRange(location: 0, length: length)
            textStorage.setAttributes(HighlightTheme.defaultAttributes, range: fullRange)

            // Walk the document tree and apply styles
            var offset = 0
            for block in document.blocks {
                let blockLen = block.sourceLength
                guard offset + blockLen <= length else { break }
                highlightBlock(block, at: offset, in: textStorage)
                offset += blockLen
            }

            // Flag special whitespace characters
            highlightSpecialWhitespace(in: textStorage, length: length)

            textStorage.endEditing()
            isHighlighting = false
        }

        private func highlightSpecialWhitespace(
            in storage: NSTextStorage, length: Int
        ) {
            let nsText = storage.string as NSString
            for i in 0..<nsText.length {
                let ch = nsText.character(at: i)
                guard let info = HighlightTheme.specialWhitespace[ch] else { continue }
                let range = NSRange(location: i, length: 1)

                if info.zeroWidth {
                    // Zero-width characters: red underline spanning adjacent chars
                    // so there's a visible marker even though the glyph has no width
                    let markerStart = max(0, i - 1)
                    let markerEnd = min(length, i + 2)
                    let markerRange = NSRange(
                        location: markerStart, length: markerEnd - markerStart)
                    storage.addAttribute(
                        .underlineStyle,
                        value: NSUnderlineStyle.thick.rawValue,
                        range: markerRange)
                    storage.addAttribute(
                        .underlineColor,
                        value: NSColor.systemRed.withAlphaComponent(0.6),
                        range: markerRange)
                } else {
                    // Visible-width characters: red background
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemRed.withAlphaComponent(0.25),
                        range: range)
                }

                // Tooltip for all — shows name + codepoint on hover
                storage.addAttribute(.toolTip, value: info.name, range: range)
            }
        }

        private func highlightBlock(
            _ block: BlockNode, at offset: Int, in storage: NSTextStorage
        ) {
            switch block {
            case .heading(let h):
                highlightHeading(h, at: offset, in: storage)
            case .paragraph(let p):
                highlightInlines(p.content, at: offset, in: storage)
            case .fencedCode(let c):
                highlightFencedCode(c, at: offset, in: storage)
            case .frontmatter(let f):
                highlightFrontmatter(f, at: offset, in: storage)
            case .thematicBreak(let t):
                let range = NSRange(location: offset, length: t.sourceLength)
                storage.addAttributes(HighlightTheme.syntaxAttributes, range: range)
            case .blockquote(let bq):
                highlightBlockquote(bq, at: offset, in: storage)
            case .list(let l):
                highlightList(l, at: offset, in: storage)
            case .table(let t):
                highlightTable(t, at: offset, in: storage)
            case .displayLatex(let d):
                let range = NSRange(location: offset, length: d.sourceLength)
                storage.addAttributes(HighlightTheme.latexAttributes, range: range)
            case .htmlBlock(let h):
                let range = NSRange(location: offset, length: h.sourceLength)
                storage.addAttributes(HighlightTheme.htmlBlockAttributes, range: range)
            case .blankLine:
                break
            }
        }

        private func highlightHeading(
            _ h: HeadingBlock, at offset: Int, in storage: NSTextStorage
        ) {
            // Style the prefix (## )
            let prefixRange = NSRange(location: offset, length: h.prefixLength)
            storage.addAttributes(HighlightTheme.syntaxAttributes, range: prefixRange)

            // Style the entire heading line with heading font
            let headingFont = HighlightTheme.headingFont(level: h.level)
            let fullRange = NSRange(location: offset, length: h.sourceLength)
            storage.addAttribute(.font, value: headingFont, range: fullRange)

            // Highlight inline content within the heading
            highlightInlines(h.content, at: offset + h.prefixLength, in: storage)
        }

        private func highlightFencedCode(
            _ c: FencedCodeBlock, at offset: Int, in storage: NSTextStorage
        ) {
            let range = NSRange(location: offset, length: c.sourceLength)
            storage.addAttributes(HighlightTheme.codeBlockAttributes, range: range)
        }

        private func highlightFrontmatter(
            _ f: FrontmatterBlock, at offset: Int, in storage: NSTextStorage
        ) {
            let range = NSRange(location: offset, length: f.sourceLength)
            storage.addAttributes(HighlightTheme.frontmatterAttributes, range: range)
        }

        private func highlightBlockquote(
            _ bq: BlockquoteBlock, at offset: Int, in storage: NSTextStorage
        ) {
            // Dim the > prefix on each line
            let range = NSRange(location: offset, length: bq.sourceLength)
            storage.addAttribute(
                .foregroundColor, value: HighlightTheme.blockquoteColor,
                range: range)
            // Highlight child blocks within the blockquote
            var pos = offset
            for child in bq.children {
                // Account for "> " prefix per line — approximate by highlighting children
                highlightBlock(child, at: pos, in: storage)
                pos += child.sourceLength
            }
        }

        private func highlightList(
            _ l: ListBlock, at offset: Int, in storage: NSTextStorage
        ) {
            var pos = offset
            for item in l.items {
                // Dim the marker (- , * , 1. , [ ] etc.)
                let markerRange = NSRange(location: pos, length: item.markerLength)
                storage.addAttributes(HighlightTheme.syntaxAttributes, range: markerRange)
                // Highlight checkbox if present
                if item.checked != nil {
                    storage.addAttribute(
                        .foregroundColor, value: HighlightTheme.checkboxColor,
                        range: markerRange)
                }
                // Highlight inline content
                highlightInlines(item.content, at: pos + item.markerLength, in: storage)
                pos += item.sourceLength
            }
        }

        private func buildTableCellMap(_ t: TableBlock, at offset: Int) {
            tableFramingRanges.append(
                NSRange(location: offset, length: t.sourceLength))
            let allCells = t.headerCells + t.bodyRows.flatMap { $0 }
            for cell in allCells {
                let start = offset + cell.sourceOffset
                let length = cell.content.totalSourceLength
                tableCellRanges.append(NSRange(location: start, length: length))
            }
        }

        private func highlightTable(
            _ t: TableBlock, at offset: Int, in storage: NSTextStorage
        ) {
            // Dim separator row
            let sepRange = NSRange(
                location: offset + t.separatorOffset, length: t.separatorLength)
            storage.addAttributes(HighlightTheme.syntaxAttributes, range: sepRange)

            // Highlight header cells
            for cell in t.headerCells {
                highlightInlines(
                    cell.content, at: offset + cell.sourceOffset, in: storage)
            }

            // Highlight body cells
            for row in t.bodyRows {
                for cell in row {
                    highlightInlines(
                        cell.content, at: offset + cell.sourceOffset, in: storage)
                }
            }

            // Align pipes across rows using kern spacing
            alignTablePipes(at: offset, sourceLength: t.sourceLength, in: storage)
        }

        private func alignTablePipes(
            at offset: Int, sourceLength: Int, in storage: NSTextStorage
        ) {
            let text = storage.string as NSString
            let charWidth = HighlightTheme.defaultFont.maximumAdvancement.width

            // Collect pipe positions per row (relative to row start)
            var rowRanges: [(start: Int, length: Int)] = []
            var rowPipes: [[Int]] = []
            var pos = offset

            while pos < offset + sourceLength {
                let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
                let lineStart = pos
                let lineLength = NSMaxRange(lineRange) - pos

                var pipes: [Int] = []
                for i in 0..<lineLength {
                    if text.character(at: lineStart + i)
                        == UInt16(UnicodeScalar("|").value)
                    {
                        pipes.append(i)
                    }
                }

                rowRanges.append((start: lineStart, length: lineLength))
                rowPipes.append(pipes)
                pos += lineLength
            }

            // Determine max column widths (chars between consecutive pipes)
            let maxColumns = rowPipes.map { max($0.count - 1, 0) }.max() ?? 0
            guard maxColumns > 0 else { return }
            var maxColumnWidths = [Int](repeating: 0, count: maxColumns)

            for pipes in rowPipes {
                for col in 0..<min(pipes.count - 1, maxColumns) {
                    let width = pipes[col + 1] - pipes[col] - 1
                    maxColumnWidths[col] = max(maxColumnWidths[col], width)
                }
            }

            // Apply kern to the character just before each closing pipe
            for (rowIdx, pipes) in rowPipes.enumerated() {
                let rowStart = rowRanges[rowIdx].start
                for col in 0..<min(pipes.count - 1, maxColumns) {
                    let currentWidth = pipes[col + 1] - pipes[col] - 1
                    let deficit = maxColumnWidths[col] - currentWidth
                    guard deficit > 0 else { continue }

                    // Kern goes on the character just before the pipe
                    let charBeforePipe = rowStart + pipes[col + 1] - 1
                    guard charBeforePipe >= offset else { continue }
                    let kernAmount = CGFloat(deficit) * charWidth

                    storage.addAttribute(
                        .kern, value: kernAmount,
                        range: NSRange(location: charBeforePipe, length: 1))

                    // Subtle indicator: faint background on the padded character
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.secondaryLabelColor.withAlphaComponent(0.06),
                        range: NSRange(location: charBeforePipe, length: 1))
                }
            }
        }

        private func highlightInlines(
            _ inlines: [InlineNode], at offset: Int, in storage: NSTextStorage
        ) {
            var pos = offset
            for node in inlines {
                let nodeLen = node.sourceLength
                highlightInline(node, at: pos, in: storage)
                pos += nodeLen
            }
        }

        private func highlightInline(
            _ node: InlineNode, at offset: Int, in storage: NSTextStorage
        ) {
            switch node {
            case .emphasis(let children, _):
                // Dim delimiters
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 1))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 1, length: 1))
                // Italic content
                let contentRange = NSRange(
                    location: offset + 1, length: children.totalSourceLength)
                storage.addAttribute(
                    .font, value: HighlightTheme.italicFont, range: contentRange)
                highlightInlines(children, at: offset + 1, in: storage)

            case .strong(let children, _):
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))
                let contentRange = NSRange(
                    location: offset + 2, length: children.totalSourceLength)
                storage.addAttribute(
                    .font, value: HighlightTheme.boldFont, range: contentRange)
                highlightInlines(children, at: offset + 2, in: storage)

            case .strikethrough(let children):
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))
                let contentRange = NSRange(
                    location: offset + 2, length: children.totalSourceLength)
                storage.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue, range: contentRange)
                highlightInlines(children, at: offset + 2, in: storage)

            case .highlight(let children):
                let contentRange = NSRange(
                    location: offset, length: node.sourceLength)
                storage.addAttribute(
                    .backgroundColor, value: HighlightTheme.highlightColor,
                    range: contentRange)
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))
                highlightInlines(children, at: offset + 2, in: storage)

            case .codeSpan(_, let n):
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.codeSpanAttributes, range: range)
                // Dim backticks
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: n))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - n, length: n))

            case .wikilink:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.wikilinkAttributes, range: range)
                // Dim brackets
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))

            case .embed:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.embedAttributes, range: range)
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 3))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))

            case .link(let children, _, _):
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.linkAttributes, range: range)
                highlightInlines(children, at: offset + 1, in: storage)

            case .image:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.linkAttributes, range: range)

            case .comment:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.commentAttributes, range: range)

            case .inlineLatex:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.latexAttributes, range: range)
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 1))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 1, length: 1))

            case .inlineFootnote(let children):
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 1, length: 1))
                highlightInlines(children, at: offset + 2, in: storage)

            case .blockReference:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.syntaxAttributes, range: range)

            case .autolink:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.linkAttributes, range: range)

            case .displayLatex:
                let range = NSRange(location: offset, length: node.sourceLength)
                storage.addAttributes(HighlightTheme.latexAttributes, range: range)
                // Dim $$ delimiters
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset, length: 2))
                storage.addAttributes(
                    HighlightTheme.syntaxAttributes,
                    range: NSRange(location: offset + node.sourceLength - 2, length: 2))

            case .text, .hardLineBreak, .softLineBreak:
                break
            }
        }
    }
}

// MARK: - Highlight Theme

enum HighlightTheme {
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    static let italicFont: NSFont = {
        let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: 14) ?? defaultFont
    }()

    static func headingFont(level: Int) -> NSFont {
        let sizes: [Int: CGFloat] = [1: 28, 2: 24, 3: 20, 4: 18, 5: 16, 6: 14]
        let size = sizes[level] ?? 14
        return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static let syntaxColor = NSColor.secondaryLabelColor
    static let wikilinkColor = NSColor.systemBlue
    static let linkColor = NSColor.systemCyan
    static let codeColor = NSColor.systemGreen.withAlphaComponent(0.8)
    static let commentColor = NSColor.systemGray
    static let latexColor = NSColor.systemOrange
    static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.3)
    static let frontmatterColor = NSColor.systemPurple.withAlphaComponent(0.8)
    static let blockquoteColor = NSColor.secondaryLabelColor
    static let checkboxColor = NSColor.systemBlue
    static let tableColor = NSColor.systemIndigo

    // MARK: - Special Whitespace

    struct WhitespaceInfo {
        let name: String
        let zeroWidth: Bool
    }

    /// Lookup by UTF-16 code unit for special whitespace characters.
    static let specialWhitespace: [UInt16: WhitespaceInfo] = [
        0x0009: WhitespaceInfo(name: "Tab (U+0009)", zeroWidth: false),
        0x00A0: WhitespaceInfo(name: "No-Break Space (U+00A0)", zeroWidth: false),
        0x2002: WhitespaceInfo(name: "En Space (U+2002)", zeroWidth: false),
        0x2003: WhitespaceInfo(name: "Em Space (U+2003)", zeroWidth: false),
        0x2007: WhitespaceInfo(name: "Figure Space (U+2007)", zeroWidth: false),
        0x2008: WhitespaceInfo(name: "Punctuation Space (U+2008)", zeroWidth: false),
        0x2009: WhitespaceInfo(name: "Thin Space (U+2009)", zeroWidth: false),
        0x200A: WhitespaceInfo(name: "Hair Space (U+200A)", zeroWidth: false),
        0x200B: WhitespaceInfo(name: "Zero-Width Space (U+200B)", zeroWidth: true),
        0x202F: WhitespaceInfo(name: "Narrow No-Break Space (U+202F)", zeroWidth: false),
        0x205F: WhitespaceInfo(name: "Medium Math Space (U+205F)", zeroWidth: false),
        0x3000: WhitespaceInfo(name: "Ideographic Space (U+3000)", zeroWidth: false),
        0xFEFF: WhitespaceInfo(name: "BOM / Zero-Width No-Break Space (U+FEFF)", zeroWidth: true),
    ]
    static let embedColor = NSColor.systemTeal

    static let defaultAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: NSColor.textColor,
    ]

    static let syntaxAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: syntaxColor,
    ]

    static let codeSpanAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: codeColor,
        .backgroundColor: NSColor.quaternaryLabelColor,
    ]

    static let codeBlockAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: codeColor,
        .backgroundColor: NSColor.quaternaryLabelColor,
    ]

    static let wikilinkAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: wikilinkColor,
    ]

    static let embedAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: embedColor,
    ]

    static let linkAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]

    static let commentAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: commentColor,
    ]

    static let latexAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: latexColor,
    ]

    static let frontmatterAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: frontmatterColor,
    ]

    static let htmlColor = NSColor.systemPink.withAlphaComponent(0.8)

    static let htmlBlockAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: htmlColor,
        .backgroundColor: NSColor.quaternaryLabelColor,
    ]
}
