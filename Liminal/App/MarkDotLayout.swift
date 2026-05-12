import CoreGraphics

/// Layout math for mark indicator dots. Returns one rect per dot and a
/// union bounding rect for dirty-rect intersection checks. Pure
/// function — testable without AppKit, painted by `VimTextView`.
///
/// Each row of dots is **horizontally centered** on the glyph's midX
/// and stacks outward from the glyph (downward in flipped coordinates,
/// upward otherwise). Lifted from the reference's `markIndicatorLayout`
/// shape.
enum MarkDotLayout {
    static let dotDiameter: CGFloat = 4.0
    static let dotGap: CGFloat = 2.0
    static let columnsPerRow: Int = 3
    static let dotOffset: CGFloat = 1.5

    struct Result {
        let bounds: CGRect
        let dotRects: [CGRect]
    }

    static func layout(
        forCount count: Int,
        anchoredTo glyphRect: CGRect,
        flipped: Bool
    ) -> Result? {
        guard count > 0 else { return nil }

        // Slice the count into rows of up to columnsPerRow.
        var rowSizes: [Int] = []
        var remaining = count
        while remaining > 0 {
            let r = min(columnsPerRow, remaining)
            rowSizes.append(r)
            remaining -= r
        }

        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        var bounds = CGRect.null
        let stride = dotDiameter + dotGap

        for (rowIndex, rowCount) in rowSizes.enumerated() {
            let rowWidth = CGFloat(rowCount) * dotDiameter
                + CGFloat(max(0, rowCount - 1)) * dotGap
            let rowOriginX = glyphRect.midX - (rowWidth / 2)
            let rowOriginY: CGFloat
            if flipped {
                rowOriginY = glyphRect.maxY + dotOffset
                    + CGFloat(rowIndex) * stride
            } else {
                rowOriginY = glyphRect.minY - dotOffset - dotDiameter
                    - CGFloat(rowIndex) * stride
            }
            for column in 0..<rowCount {
                let frame = CGRect(
                    x: rowOriginX + CGFloat(column) * stride,
                    y: rowOriginY,
                    width: dotDiameter,
                    height: dotDiameter
                )
                rects.append(frame)
                bounds = bounds.union(frame)
            }
        }
        return Result(bounds: bounds, dotRects: rects)
    }
}
