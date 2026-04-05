import SwiftUI

/// Renders a parsed Document as rich, readable content.
struct RenderedDocumentView: View {
    let document: Document
    let documentIndex: DocumentIndex
    let currentNoteID: URL?
    let navigationRequest: NoteNavigationRequest?
    let onOpenWikiTarget: (WikiTarget) -> Void
    @Binding var baseFontSize: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(indexedBlocks, id: \.offset) { indexedBlock in
                        BlockView(
                            block: indexedBlock.block,
                            onOpenWikiTarget: onOpenWikiTarget
                        )
                        .id(indexedBlock.offset)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .environment(\.baseFontSize, baseFontSize)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "wikilink" else {
                    return .systemAction(url)
                }
                let rawTarget = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .removingPercentEncoding ?? ""
                onOpenWikiTarget(WikiTarget.parse(rawTarget))
                return .handled
            })
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
            .onAppear {
                scrollIfNeeded(with: proxy)
            }
            .onChange(of: navigationRequest?.nonce) { _, _ in
                scrollIfNeeded(with: proxy)
            }
        }
    }

    private var indexedBlocks: [(offset: Int, block: BlockNode)] {
        var offset = 0
        return document.blocks.map { block in
            defer { offset += block.sourceLength }
            return (offset, block)
        }
    }

    private func scrollIfNeeded(with proxy: ScrollViewProxy) {
        guard navigationRequest?.noteID == currentNoteID else { return }
        guard let anchor = navigationRequest?.anchor else { return }
        guard let blockOffset = documentIndex.blockOffset(for: anchor) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(blockOffset, anchor: .top)
        }
    }
}
