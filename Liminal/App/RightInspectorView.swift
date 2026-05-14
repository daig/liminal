import SwiftUI

struct RightInspectorView: View {
    @State private var selectedTab: RightInspectorTab = .backlinks
    let entry: VaultEntry?
    let currentDocURL: URL?

    private var tabs: [RightInspectorTab] {
        entry == nil ? [.clipboard] : RightInspectorTab.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear(perform: normalizeSelection)
        .onChange(of: entry == nil) { _, _ in
            normalizeSelection()
        }
    }

    private var header: some View {
        Picker("Inspector", selection: $selectedTab) {
            ForEach(tabs) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .backlinks:
            if let entry {
                BacklinkInspectorContent(
                    entry: entry,
                    currentDocURL: currentDocURL
                )
            } else {
                ClipboardInspectorView()
            }
        case .clipboard:
            ClipboardInspectorView()
        }
    }

    private func normalizeSelection() {
        if !tabs.contains(selectedTab) {
            selectedTab = tabs.first ?? .clipboard
        }
    }
}

private enum RightInspectorTab: String, CaseIterable, Identifiable {
    case backlinks
    case clipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .backlinks: return "Links"
        case .clipboard: return "Clipboard"
        }
    }

    var systemImage: String {
        switch self {
        case .backlinks: return "link"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}
