import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    let editorViewModel: EditorViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textLayoutManager.textContainer = textContainer

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
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
        context.coordinator.textView = textView

        if let note = editorViewModel.currentNote {
            textView.string = note.content
            context.coordinator.currentNoteID = note.id
            context.coordinator.applyHighlighting()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let newNoteID = editorViewModel.currentNote?.id
        if context.coordinator.currentNoteID != newNoteID {
            context.coordinator.currentNoteID = newNoteID
            textView.string = editorViewModel.currentNote?.content ?? ""
            textView.scrollToBeginningOfDocument(nil)
            context.coordinator.applyHighlighting()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(editorViewModel: editorViewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var currentNoteID: URL?
        let editorViewModel: EditorViewModel
        private var isHighlighting = false

        init(editorViewModel: EditorViewModel) {
            self.editorViewModel = editorViewModel
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

            textStorage.endEditing()
            isHighlighting = false
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
            case .blankLine, .htmlBlock:
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
}
