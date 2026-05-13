import SwiftUI

/// Tabbed sidebar for the editor window. Picks between the file
/// navigator (file tree + per-file TOC) and the force-directed
/// vault graph. Both share the same `VaultEntry` so switching tabs
/// is just a view swap — neither view tears down its cached state
/// (the navigator's expansion state, the graph's positions).
struct VaultSidebarView: View {
    @ObservedObject var entry: VaultEntry
    let currentDocURL: URL?

    @State private var tab: SidebarTab = .files

    enum SidebarTab: String, CaseIterable, Identifiable {
        case files = "Files"
        case graph = "Graph"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                ForEach(SidebarTab.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Both subviews are kept in the view tree (via opacity
            // toggles inside a ZStack) so neither resets its
            // internal state when the tab switches. The simulator's
            // node positions and the navigator's expanded folders
            // both survive across tab swaps.
            ZStack {
                VaultNavigatorView(entry: entry, currentDocURL: currentDocURL)
                    .opacity(tab == .files ? 1 : 0)
                    .allowsHitTesting(tab == .files)

                VaultGraphView(entry: entry, currentDocURL: currentDocURL)
                    .opacity(tab == .graph ? 1 : 0)
                    .allowsHitTesting(tab == .graph)
            }
        }
    }
}
