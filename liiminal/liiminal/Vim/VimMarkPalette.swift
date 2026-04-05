import Foundation

struct VimDisplayTint: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

enum VimMarkPalette {
    // Prime-step ordering keeps nearby mark names like a/b/c visually far apart.
    private static let hueOrder: [Int] = [
        0, 11, 22, 7, 18, 3, 14, 25, 10, 21, 6, 17, 2,
        13, 24, 9, 20, 5, 16, 1, 12, 23, 8, 19, 4, 15,
    ]

    static func tint(for mark: Character) -> VimDisplayTint {
        guard let scalar = mark.unicodeScalars.first else {
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
}
