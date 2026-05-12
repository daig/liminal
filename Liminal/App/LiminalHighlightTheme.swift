import AppKit

/// Maps `HighlightCategory` + `InlineModifiers` to NSAttributedString
/// attribute dicts suitable for `NSTextStorage.addAttributes(_:range:)`.
/// Uses NSColor's semantic palette so dark/light mode adaptation is
/// automatic.
struct LiminalHighlightTheme: @unchecked Sendable {
    let baseFont: NSFont

    static let `default` = LiminalHighlightTheme(
        baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
    )

    /// Attributes applied to the entire text storage before per-span
    /// overrides are layered. Resets foreground color to label and font
    /// to base; any traits/decorations from a prior pass are cleared by
    /// `setAttributes(_:range:)` replacing rather than merging.
    var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    /// Attributes for one span. Caller is responsible for setting the
    /// default attributes on the full range first; this dict only carries
    /// overrides.
    func attributes(
        for category: HighlightCategory,
        modifiers: InlineModifiers
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color(for: category),
            .font: font(for: modifiers),
        ]

        if modifiers.contains(.strikethrough) {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if modifiers.contains(.highlight) {
            attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.25)
        }

        switch category {
        case .linkText:
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.underlineColor] = NSColor.systemBlue
        case .error:
            attrs[.underlineStyle] = NSUnderlineStyle.thick.union(.patternDot).rawValue
            attrs[.underlineColor] = NSColor.systemRed
        default:
            break
        }

        return attrs
    }

    private func color(for category: HighlightCategory) -> NSColor {
        switch category {
        case .default:        return NSColor.labelColor
        case .delimiter:      return NSColor.tertiaryLabelColor
        case .typeName:       return NSColor.systemPurple
        case .identifier:     return NSColor.secondaryLabelColor
        case .stringLiteral:  return NSColor.systemRed
        case .numberLiteral:  return NSColor.systemOrange
        case .linkText:       return NSColor.systemBlue
        case .codeContent:    return NSColor.secondaryLabelColor
        case .rawContent:     return NSColor.secondaryLabelColor
        case .commentContent: return NSColor.tertiaryLabelColor
        case .interpolation:  return NSColor.systemTeal
        case .error:          return NSColor.systemRed
        }
    }

    /// Compose font traits from modifiers. `.heading` and `.strong` both
    /// request bold (idempotent when nested); `.emphasis` requests italic;
    /// they compose as bold-italic when both present.
    private func font(for modifiers: InlineModifiers) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if modifiers.contains(.strong) || modifiers.contains(.heading) {
            traits.insert(.bold)
        }
        if modifiers.contains(.emphasis) {
            traits.insert(.italic)
        }

        if traits.isEmpty {
            return baseFont
        }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }
}
