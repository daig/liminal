import AppKit

/// Hue + saturation + brightness for a mark letter. Lifted from the
/// reference editor's palette unchanged — the prime-step hue ordering
/// keeps neighboring mark names (a/b/c) visually far apart while still
/// spreading the full alphabet around the hue circle.
struct VimDisplayTint: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

enum VimMarkPalette {
    /// Prime-step ordering keeps nearby mark names (a/b/c) visually far
    /// apart. Stable across runs since it's hardcoded.
    private static let hueOrder: [Int] = [
        0, 11, 22, 7, 18, 3, 14, 25, 10, 21, 6, 17, 2,
        13, 24, 9, 20, 5, 16, 1, 12, 23, 8, 19, 4, 15,
    ]

    static func tint(for mark: Character) -> VimDisplayTint {
        guard let scalar = mark.lowercased().unicodeScalars.first else {
            return VimDisplayTint(hue: 0.0, saturation: 0.0, brightness: 0.65)
        }
        let index = max(0, min(Int(scalar.value) - 0x61, hueOrder.count - 1))
        let orderedIndex = hueOrder[index]
        let hue = (Double(orderedIndex) + 0.35) / Double(hueOrder.count)
        return VimDisplayTint(
            hue: hue.truncatingRemainder(dividingBy: 1.0),
            saturation: 0.52,
            brightness: 0.74
        )
    }

    /// Convenience: directly hand back an NSColor with the reference's
    /// alpha. Painted by `VimTextView.drawMarkIndicators`.
    static func color(for mark: Character) -> NSColor {
        let t = tint(for: mark)
        return NSColor(
            calibratedHue: CGFloat(t.hue),
            saturation: CGFloat(t.saturation),
            brightness: CGFloat(t.brightness),
            alpha: 0.92
        )
    }
}
