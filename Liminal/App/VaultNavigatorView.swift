import CambiumCore
import SwiftUI

/// Sidebar view: hierarchical file tree of the vault, with each file
/// row expandable to its CST-derived heading TOC.
///
/// Click a file row → `NavigationRouter.navigate` (focuses an
/// existing window if open, otherwise opens a new one). Click a
/// heading → same path with the heading as anchor. The current
/// document highlights so the user can locate themselves while
/// browsing.
struct VaultNavigatorView: View {
    @ObservedObject var entry: VaultEntry
    let currentDocURL: URL?

    var body: some View {
        List {
            OutlineGroup(entry.fileTree, children: \.children) { node in
                if node.isFolder {
                    Label(node.name, systemImage: "folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    FileNavigatorRow(
                        node: node,
                        entry: entry,
                        isCurrent: isCurrent(node)
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(entry.rootURL.lastPathComponent)
    }

    private func isCurrent(_ node: FileTreeNode) -> Bool {
        guard let currentDocURL, let nodeURL = node.url else { return false }
        return VaultRegistry.canonicalNoteURL(for: currentDocURL) == nodeURL
    }
}

/// One file row. Files with at least one heading get a
/// `DisclosureGroup` showing their TOC, indented per heading level;
/// files with no headings render as a flat row (no chevron).
struct FileNavigatorRow: View {
    let node: FileTreeNode
    @ObservedObject var entry: VaultEntry
    let isCurrent: Bool

    @State private var expanded = false

    var body: some View {
        let headings = currentHeadings
        if headings.isEmpty {
            fileLabel
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(headings, id: \.sourceOffset) { heading in
                    headingRow(heading)
                }
            } label: {
                fileLabel
            }
        }
    }

    private var fileLabel: some View {
        Button(action: openFile) {
            Label(displayName, systemImage: "doc.text")
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headingRow(_ heading: HeadingAnchor) -> some View {
        Button {
            jumpToHeading(heading)
        } label: {
            Text(heading.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, CGFloat((heading.level - 1) * 10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        (node.name as NSString).deletingPathExtension
    }

    private var currentHeadings: [HeadingAnchor] {
        guard let url = node.url else { return [] }
        return entry.indexes[url]?.headings ?? []
    }

    private func openFile() {
        guard let url = node.url else { return }
        NavigationRouter.shared.navigate(to: url, anchor: nil)
    }

    private func jumpToHeading(_ heading: HeadingAnchor) {
        guard let url = node.url else { return }
        NavigationRouter.shared.navigate(to: url, anchor: .heading(heading.title))
    }
}
