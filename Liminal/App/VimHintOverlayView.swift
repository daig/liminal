import SwiftUI

/// Floating hint panel that surfaces the next-key choices available
/// from the controller's current pending prefix. Anchored at the
/// bottom of the editor; shows nothing when `snapshot` is `nil`. Layout
/// (LazyVGrid + ScrollView + material background) is cribbed from the
/// reference editor's `VimHintOverlayView`; data types are ours.
struct VimHintOverlayView: View {
    let snapshot: VimHintSnapshot?

    private let columns = [
        GridItem(.adaptive(minimum: 220), alignment: .topLeading)
    ]

    var body: some View {
        if let snapshot {
            panel(for: snapshot)
                .transition(.hintPop)
        }
    }

    private func panel(for snapshot: VimHintSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = snapshot.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(snapshot.items) { item in
                        HintRow(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            Text("Esc to dismiss")
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
}

private struct HintRow: View {
    let item: VimHintItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.key.displayString)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(displayDescription)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayDescription: String {
        switch item.kind {
        case .group:
            return "+ \(item.description)"
        case .action:
            return item.description
        }
    }
}

private extension AnyTransition {
    /// Subtle lift + fade. The 12pt offset gives motion interest without
    /// the long travel of a full edge slide.
    static var hintPop: AnyTransition {
        .modifier(
            active: HintPopModifier(offsetY: 12, opacity: 0),
            identity: HintPopModifier(offsetY: 0, opacity: 1)
        )
    }
}

private struct HintPopModifier: ViewModifier {
    let offsetY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}
