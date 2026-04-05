import SwiftUI

struct VimHintOverlayView: View {
    let snapshot: VimHintSnapshot

    private let columns = [
        GridItem(.adaptive(minimum: 220), alignment: .topLeading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(snapshot.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(keyForegroundColor(for: item))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(keyBackgroundColor(for: item))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(
                                            keyBorderColor(for: item),
                                            lineWidth: item.tint == nil ? 0 : 1
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            Text(displayDescription(for: item))
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    item.kind == .argument ? .secondary : .primary
                                )
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            Text("Esc close")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: 840, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func displayDescription(for item: VimHintItem) -> String {
        switch item.kind {
        case .group:
            return "+ \(item.description)"
        case .action, .argument:
            return item.description
        }
    }

    private func keyForegroundColor(for item: VimHintItem) -> Color {
        if let tint = item.tint {
            return color(for: tint)
        }

        return .primary
    }

    private func keyBackgroundColor(for item: VimHintItem) -> Color {
        if let tint = item.tint {
            return color(for: tint).opacity(0.14)
        }

        return Color.secondary.opacity(0.12)
    }

    private func keyBorderColor(for item: VimHintItem) -> Color {
        if let tint = item.tint {
            return color(for: tint).opacity(0.4)
        }

        return .clear
    }

    private func color(for tint: VimDisplayTint) -> Color {
        Color(
            hue: tint.hue,
            saturation: tint.saturation,
            brightness: tint.brightness
        )
    }
}
