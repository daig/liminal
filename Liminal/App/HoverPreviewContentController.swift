import AppKit

/// View controller hosted inside the hover-preview `NSPopover`. Owns
/// a small header (target title) and a non-editable, scrollable
/// `NSTextView` for the highlighted preview body.
@MainActor
final class HoverPreviewContentController: NSViewController {
    private let theme: LiminalHighlightTheme
    private var titleField: NSTextField!
    private var scrollView: NSScrollView!
    private var bodyTextView: NSTextView!

    init(theme: LiminalHighlightTheme) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        let initialSize = NSSize(width: 520, height: 320)
        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        self.titleField = title

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.typingAttributes = theme.defaultAttributes
        self.bodyTextView = textView

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        self.scrollView = scroll

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
        preferredContentSize = initialSize
    }

    /// Replace the header + body with a new snapshot. Resets the
    /// scroll position to the top so the user always sees the
    /// anchor's surroundings, not where they last scrolled.
    /// Resizes the hosting popover to fit the actual rendered
    /// content height (capped) rather than always reserving a fixed
    /// height — short previews get short popovers.
    func updateContent(snapshot: HoverPreviewSnapshot) {
        loadViewIfNeeded()
        titleField.stringValue = snapshot.title
        bodyTextView.textStorage?.setAttributedString(snapshot.attributedBody)
        bodyTextView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        resizeToFitContent()
    }

    /// Update `preferredContentSize` based on the actual layout
    /// height of the body text. NSPopover observes that property and
    /// reflows its window. Width is fixed; only height varies.
    private func resizeToFitContent() {
        guard let layoutManager = bodyTextView.layoutManager,
              let textContainer = bodyTextView.textContainer
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        let textRect = layoutManager.usedRect(for: textContainer)
        let inset = bodyTextView.textContainerInset
        let bodyHeight = ceil(textRect.height + inset.height * 2)

        let titleHeight = titleField.intrinsicContentSize.height
        let titleAreaHeight = titleHeight + 18  // top + spacing
        let totalHeight = min(360, titleAreaHeight + bodyHeight + 4)

        preferredContentSize = NSSize(width: 520, height: totalHeight)
    }
}
