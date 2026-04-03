import SwiftUI

/// Renders a parsed Document as rich, readable content.
struct RenderedDocumentView: View {
    let document: Document

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
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
