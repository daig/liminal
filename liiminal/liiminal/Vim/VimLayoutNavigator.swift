import AppKit

enum VimLayoutNavigator {
    static func destination(
        for motion: VimLayoutMotion,
        count: Int?,
        in textView: NSTextView,
        from position: Int
    ) -> Int {
        let text = textView.string as NSString
        guard text.length > 0 else { return 0 }

        switch motion {
        case .windowLine(let viewportPosition):
            return windowLineDestination(
                for: viewportPosition,
                count: count,
                in: textView,
                text: text
            )
        case .screenLineDown:
            return moveScreenLines(
                from: position,
                count: count ?? 1,
                direction: 1,
                in: textView,
                text: text
            )
        case .screenLineUp:
            return moveScreenLines(
                from: position,
                count: count ?? 1,
                direction: -1,
                in: textView,
                text: text
            )
        case .screenLineStart:
            let basePosition = moveScreenLines(
                from: position,
                count: max((count ?? 1) - 1, 0),
                direction: 1,
                in: textView,
                text: text
            )
            return screenLineAnchor(.start, at: basePosition, in: textView, text: text)
        case .screenLineFirstNonBlank:
            let basePosition = moveScreenLines(
                from: position,
                count: max((count ?? 1) - 1, 0),
                direction: 1,
                in: textView,
                text: text
            )
            return screenLineAnchor(.firstNonBlank, at: basePosition, in: textView, text: text)
        case .screenLineEnd:
            let basePosition = moveScreenLines(
                from: position,
                count: max((count ?? 1) - 1, 0),
                direction: 1,
                in: textView,
                text: text
            )
            return screenLineAnchor(.end, at: basePosition, in: textView, text: text)
        case .halfPageDown:
            return pageMotion(
                from: position,
                in: textView,
                text: text,
                deltaY: halfPageDelta(in: textView, position: position, count: count)
            )
        case .halfPageUp:
            return pageMotion(
                from: position,
                in: textView,
                text: text,
                deltaY: -halfPageDelta(in: textView, position: position, count: count)
            )
        case .fullPageDown:
            return pageMotion(
                from: position,
                in: textView,
                text: text,
                deltaY: textView.visibleRect.height * CGFloat(max(count ?? 1, 1))
            )
        case .fullPageUp:
            return pageMotion(
                from: position,
                in: textView,
                text: text,
                deltaY: -textView.visibleRect.height * CGFloat(max(count ?? 1, 1))
            )
        }
    }

    private enum ScreenLineAnchor {
        case start
        case firstNonBlank
        case end
    }

    private struct ScreenLineContext {
        let usedRect: NSRect
        let characterRange: NSRange
        let caretPoint: NSPoint
        let lineHeight: CGFloat
    }

    private static func windowLineDestination(
        for viewportPosition: VimViewportLinePosition,
        count: Int?,
        in textView: NSTextView,
        text: NSString
    ) -> Int {
        let visibleRect = textView.visibleRect
        let lineHeight = currentLineHeight(in: textView, position: 0)
        let clampedCount = max(count ?? 1, 1)

        let targetY: CGFloat
        switch viewportPosition {
        case .top:
            targetY = visibleRect.minY + (CGFloat(clampedCount) - 0.5) * lineHeight
        case .middle:
            targetY = visibleRect.midY
        case .bottom:
            targetY = visibleRect.maxY - (CGFloat(clampedCount) - 0.5) * lineHeight
        }

        let targetPoint = NSPoint(
            x: textView.textContainerOrigin.x + 1,
            y: clampPointY(targetY, in: textView)
        )
        let position = normalizedCursorPosition(
            insertionIndex(at: targetPoint, in: textView),
            in: text
        )

        return screenLineAnchor(.firstNonBlank, at: position, in: textView, text: text)
    }

    private static func moveScreenLines(
        from position: Int,
        count: Int,
        direction: Int,
        in textView: NSTextView,
        text: NSString
    ) -> Int {
        guard count > 0 else { return normalizedCursorPosition(position, in: text) }
        guard let currentContext = screenLineContext(at: position, in: textView, text: text) else {
            return normalizedCursorPosition(position, in: text)
        }

        let targetX = currentContext.caretPoint.x
        var currentPosition = normalizedCursorPosition(position, in: text)

        for _ in 0..<count {
            guard let context = screenLineContext(at: currentPosition, in: textView, text: text)
            else { break }

            let targetPoint = NSPoint(
                x: targetX,
                y: clampPointY(
                    context.caretPoint.y + (CGFloat(direction) * context.lineHeight),
                    in: textView
                )
            )
            let nextPosition = normalizedCursorPosition(
                insertionIndex(at: targetPoint, in: textView),
                in: text
            )

            if nextPosition == currentPosition {
                break
            }

            currentPosition = nextPosition
        }

        return currentPosition
    }

    private static func screenLineAnchor(
        _ anchor: ScreenLineAnchor,
        at position: Int,
        in textView: NSTextView,
        text: NSString
    ) -> Int {
        guard let context = screenLineContext(at: position, in: textView, text: text) else {
            return normalizedCursorPosition(position, in: text)
        }

        switch anchor {
        case .start:
            return normalizedCursorPosition(context.characterRange.location, in: text)
        case .firstNonBlank:
            return firstNonBlank(in: context.characterRange, text: text)
        case .end:
            return lastCharacterIndex(in: context.characterRange, text: text)
        }
    }

    private static func pageMotion(
        from position: Int,
        in textView: NSTextView,
        text: NSString,
        deltaY: CGFloat
    ) -> Int {
        guard let context = screenLineContext(at: position, in: textView, text: text) else {
            return normalizedCursorPosition(position, in: text)
        }

        scrollViewport(by: deltaY, in: textView)

        let targetPoint = NSPoint(
            x: context.caretPoint.x,
            y: clampPointY(context.caretPoint.y + deltaY, in: textView)
        )

        return normalizedCursorPosition(insertionIndex(at: targetPoint, in: textView), in: text)
    }

    private static func halfPageDelta(
        in textView: NSTextView,
        position: Int,
        count: Int?
    ) -> CGFloat {
        if let count {
            return CGFloat(max(count, 1)) * currentLineHeight(in: textView, position: position)
        }

        return textView.visibleRect.height / 2
    }

    private static func scrollViewport(by deltaY: CGFloat, in textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else { return }

        let visibleRect = textView.visibleRect
        let maxOriginY = max(documentRect(in: textView).maxY - visibleRect.height, 0)
        let newOriginY = max(0, min(visibleRect.origin.y + deltaY, maxOriginY))
        let clipView = scrollView.contentView

        clipView.scroll(to: NSPoint(x: visibleRect.origin.x, y: newOriginY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private static func screenLineContext(
        at position: Int,
        in textView: NSTextView,
        text: NSString
    ) -> ScreenLineContext? {
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return nil
        }

        let safePosition = max(0, min(position, text.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safePosition)
        var glyphRange = NSRange(location: 0, length: 0)
        let usedRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &glyphRange
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let containerOrigin = textView.textContainerOrigin

        _ = textContainer

        return ScreenLineContext(
            usedRect: usedRect,
            characterRange: characterRange,
            caretPoint: NSPoint(
                x: containerOrigin.x + usedRect.origin.x + glyphLocation.x,
                y: containerOrigin.y + usedRect.midY
            ),
            lineHeight: max(usedRect.height, 1)
        )
    }

    private static func currentLineHeight(in textView: NSTextView, position: Int) -> CGFloat {
        let text = textView.string as NSString
        return screenLineContext(at: position, in: textView, text: text)?.lineHeight
            ?? max(textView.font?.boundingRectForFont.height ?? 0, 1)
    }

    private static func insertionIndex(at point: NSPoint, in textView: NSTextView) -> Int {
        textView.characterIndexForInsertion(at: point)
    }

    private static func documentRect(in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return textView.bounds
        }

        let usedRect = layoutManager.usedRect(for: textContainer)
        return usedRect.offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
    }

    private static func clampPointY(_ y: CGFloat, in textView: NSTextView) -> CGFloat {
        let documentRect = documentRect(in: textView)
        let minimum = documentRect.minY + 1
        let maximum = max(documentRect.maxY - 1, minimum)
        return max(minimum, min(y, maximum))
    }

    private static func lineContentUpperBound(of range: NSRange, in text: NSString) -> Int {
        guard range.length > 0 else { return range.location }

        let lastIndex = NSMaxRange(range) - 1
        let endsWithNewline = text.character(at: lastIndex) == 0x0A
        return endsWithNewline ? lastIndex : NSMaxRange(range)
    }

    private static func firstNonBlank(in range: NSRange, text: NSString) -> Int {
        let upperBound = lineContentUpperBound(of: range, in: text)
        var currentIndex = range.location

        while currentIndex < upperBound {
            let character = text.character(at: currentIndex)
            guard let scalar = Unicode.Scalar(character) else { break }
            if !CharacterSet.whitespaces.contains(scalar) {
                return currentIndex
            }
            currentIndex += 1
        }

        return normalizedCursorPosition(range.location, in: text)
    }

    private static func lastCharacterIndex(in range: NSRange, text: NSString) -> Int {
        let upperBound = lineContentUpperBound(of: range, in: text)
        return upperBound > range.location
            ? normalizedCursorPosition(upperBound - 1, in: text)
            : normalizedCursorPosition(range.location, in: text)
    }

    private static func normalizedCursorPosition(_ position: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }

        var normalized = max(0, min(position, text.length - 1))

        if text.character(at: normalized) == 0x0A, normalized > 0 {
            let lineRange = text.lineRange(for: NSRange(location: normalized, length: 0))
            if normalized > lineRange.location {
                normalized -= 1
            }
        }

        return normalized
    }
}
