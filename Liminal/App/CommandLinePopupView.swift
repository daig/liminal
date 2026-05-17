import SwiftUI

/// Floating popup that surfaces command-name and argument completions
/// while the controller is in `.commandLine` mode. Mirrors the visual
/// design of `VimHintOverlayView` (material background, rounded rect,
/// shadow) so the two surfaces feel like one design system.
///
/// Pure view: reads `entries` + `highlightedIndex` from the controller
/// and renders. Highlight navigation and dispatch live in
/// `VimController.handleCommandLine`.
struct CommandLinePopupView: View {
    let entries: [CompletionEntry]
    let highlightedIndex: Int?
    /// Invoked when the user clicks a row. Sets the highlight to that
    /// row and accepts (same as pressing Enter on it).
    let onRowAccepted: (Int) -> Void

    var body: some View {
        if !entries.isEmpty {
            panel
                .transition(.popupPop)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                CommandLineRow(
                    entry: entry,
                    isHighlighted: index == highlightedIndex
                )
                .contentShape(Rectangle())
                .onTapGesture { onRowAccepted(index) }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

private struct CommandLineRow: View {
    let entry: CompletionEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(highlightedDisplay)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 160, alignment: .leading)
                .lineLimit(1)

            Text(entry.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let chord = entry.chordHint {
                Text(chord)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isHighlighted
            ? Color.accentColor.opacity(0.22)
            : Color.clear
        )
    }

    /// AttributedString of `entry.display` with the matched character
    /// positions rendered bold + accent-colored.
    private var highlightedDisplay: AttributedString {
        var attributed = AttributedString(entry.display)
        let matchSet = Set(entry.matchedIndices)
        for (idx, _) in entry.display.enumerated() where matchSet.contains(idx) {
            // Locate the AttributedString range for the (idx)-th UTF-16
            // unit. For our ASCII command names this is character-aligned.
            let start = attributed.index(attributed.startIndex, offsetByCharacters: idx)
            let end = attributed.index(start, offsetByCharacters: 1)
            attributed[start..<end].font = .system(
                size: 12, weight: .bold, design: .monospaced
            )
            attributed[start..<end].foregroundColor = .accentColor
        }
        return attributed
    }
}

private extension AnyTransition {
    /// Subtle lift + fade, same shape as `VimHintOverlayView`'s
    /// `.hintPop`. Keeps the two overlays visually cohesive.
    static var popupPop: AnyTransition {
        .modifier(
            active: PopupPopModifier(offsetY: 8, opacity: 0),
            identity: PopupPopModifier(offsetY: 0, opacity: 1)
        )
    }
}

private struct PopupPopModifier: ViewModifier {
    let offsetY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

private extension AttributedString {
    /// Helper to advance an `AttributedString.Index` by `n` characters.
    func index(_ idx: Index, offsetByCharacters n: Int) -> Index {
        var current = idx
        for _ in 0..<n {
            current = characters.index(after: current)
        }
        return current
    }
}
