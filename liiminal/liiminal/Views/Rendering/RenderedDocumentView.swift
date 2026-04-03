import SwiftUI

/// Renders a parsed Document as rich, readable content.
struct RenderedDocumentView: View {
    let document: Document
    @Binding var baseFontSize: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(document.blocks.enumerated()), id: \.offset
                ) { _, block in
                    BlockView(block: block)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .environment(\.baseFontSize, baseFontSize)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Button {
                        baseFontSize = max(baseFontSize - 2, 10)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    .help("Decrease font size")

                    Button {
                        baseFontSize = 16
                    } label: {
                        Text("\(Int(baseFontSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("0", modifiers: .command)
                    .help("Reset font size")

                    Button {
                        baseFontSize = min(baseFontSize + 2, 40)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .keyboardShortcut("=", modifiers: .command)
                    .help("Increase font size")
                }
            }
        }
    }
}
