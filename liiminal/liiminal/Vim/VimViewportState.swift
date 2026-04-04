import AppKit

struct VimViewportState {
    let visibleRect: NSRect
    let documentRect: NSRect

    var maxOriginY: CGFloat {
        max(documentRect.maxY - visibleRect.height, 0)
    }

    func clampedOriginY(_ y: CGFloat) -> CGFloat {
        max(0, min(y, maxOriginY))
    }

    func clampedPointY(_ y: CGFloat) -> CGFloat {
        let minimum = documentRect.minY + 1
        let maximum = max(documentRect.maxY - 1, minimum)
        return max(minimum, min(y, maximum))
    }

    func originYAligning(lineRect: NSRect, to placement: VimViewportLinePosition) -> CGFloat {
        let targetOriginY: CGFloat

        switch placement {
        case .top:
            targetOriginY = lineRect.minY
        case .middle:
            targetOriginY = lineRect.midY - (visibleRect.height / 2)
        case .bottom:
            targetOriginY = lineRect.maxY - visibleRect.height
        }

        return clampedOriginY(targetOriginY)
    }
}

enum VimViewportController {
    static func state(in textView: NSTextView) -> VimViewportState? {
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
        let minimumDocumentRect = NSRect(origin: .zero, size: textView.bounds.size)

        return VimViewportState(
            visibleRect: textView.visibleRect,
            documentRect: minimumDocumentRect.union(usedRect)
        )
    }

    static func ensurePositionVisible(_ position: Int, in textView: NSTextView) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let safePosition = max(0, min(position, text.length - 1))
        textView.scrollRangeToVisible(NSRange(location: safePosition, length: 1))
    }

    static func scroll(by deltaY: CGFloat, in textView: NSTextView) {
        guard let state = state(in: textView),
            let scrollView = textView.enclosingScrollView
        else {
            return
        }

        let newOriginY = state.clampedOriginY(state.visibleRect.origin.y + deltaY)
        scroll(toOriginY: newOriginY, in: scrollView, currentVisibleRect: state.visibleRect)
    }

    static func alignCursorLine(
        at position: Int,
        to placement: VimViewportLinePosition,
        in textView: NSTextView
    ) {
        guard let state = state(in: textView),
            let scrollView = textView.enclosingScrollView,
            let lineRect = lineFragmentRect(at: position, in: textView)
        else {
            return
        }

        let newOriginY = state.originYAligning(lineRect: lineRect, to: placement)
        scroll(toOriginY: newOriginY, in: scrollView, currentVisibleRect: state.visibleRect)
    }

    static func lineFragmentRect(at position: Int, in textView: NSTextView) -> NSRect? {
        let text = textView.string as NSString
        guard text.length > 0 else { return nil }
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)

        let safePosition = max(0, min(position, text.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safePosition)
        let usedRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )

        return usedRect.offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
    }

    private static func scroll(
        toOriginY originY: CGFloat,
        in scrollView: NSScrollView,
        currentVisibleRect: NSRect
    ) {
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: currentVisibleRect.origin.x, y: originY))
        scrollView.reflectScrolledClipView(clipView)
    }
}
