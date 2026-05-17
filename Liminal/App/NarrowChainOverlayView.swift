import SwiftUI

/// Floating panel that visualizes the pending `:CSTNarrow` chain
/// (`VimController.narrowChainPreview`). One row per `NarrowChainEntry`,
/// rendered top-to-bottom in pop order — row 1 is what the next
/// `:CSTNarrow` press will land on, row 2 the press after that, etc.
///
/// Pure view: reads `entries` from the controller and renders. Material
/// + rounded-rect styling mirrors `CommandLinePopupView` so the two
/// surfaces feel cohesive.
///
/// Hidden when `entries.isEmpty` — the visualizer appears only while
/// the user has an active expand history.
struct NarrowChainOverlayView: View {
    let entries: [NarrowChainEntry]

    var body: some View {
        if !entries.isEmpty {
            panel
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(entries) { entry in
                row(entry)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.right.to.line.compact")
                .font(.system(size: 9, weight: .semibold))
            Text("Narrow chain (\(entries.count))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }

    private func row(_ entry: NarrowChainEntry) -> some View {
        HStack(spacing: 6) {
            Text("\(entry.ordinal)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.ordinal == 1 ? .primary : .tertiary)
                .frame(width: 14, alignment: .trailing)
            Text(entry.kindDisplay)
                .font(.system(size: 11, weight: entry.ordinal == 1 ? .semibold : .regular))
                .foregroundStyle(entry.ordinal == 1 ? .primary : .secondary)
            Text("[\(entry.childIndex)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }
}
