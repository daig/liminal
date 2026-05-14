import AppKit
import CambiumCore
import SwiftUI

/// Inspector panel: lists every reference into the current document
/// from elsewhere in the vault. Subscribes to `VaultEntry`'s
/// `linkIndex`, which is `@Published` and re-folded on every
/// per-doc reindex, so the panel stays live as the user edits.
///
/// Click a row → `NavigationRouter.navigate(to: sourceNoteID,
/// anchor: .sourceOffset(...))`. The existing within-doc anchor
/// jump in `LiminalTextView.Coordinator` resolves
/// `.sourceOffset` to the start of the containing block so the
/// cursor lands somewhere coherent.
struct BacklinkInspectorView: View {
    @ObservedObject var entry: VaultEntry
    let currentDocURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            BacklinkInspectorContent(
                entry: entry,
                currentDocURL: currentDocURL
            )
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Backlinks")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(sortedBacklinks.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sortedBacklinks: [ResolvedReference] {
        let canonical = currentDocURL.map(VaultRegistry.canonicalNoteURL)
        let raw = entry.linkIndex.backlinks(for: canonical)
        return BacklinkPresentation.sorted(raw, notes: entry.notes)
    }
}

struct BacklinkInspectorContent: View {
    @ObservedObject var entry: VaultEntry
    let currentDocURL: URL?

    @ViewBuilder
    var body: some View {
        if sortedBacklinks.isEmpty {
            VStack {
                Spacer()
                Text("No backlinks yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedBacklinks) { ref in
                        BacklinkRow(
                            reference: ref,
                            sourceLabel: BacklinkPresentation
                                .sourceDisplayLabel(for: ref, notes: entry.notes)
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    /// Recomputed per body evaluation. Lookup is O(1) and sort is
    /// O(k log k) over only this note's backlinks (typically tiny).
    /// Materialized once per render so the header count and the
    /// list see the same array.
    private var sortedBacklinks: [ResolvedReference] {
        let canonical = currentDocURL.map(VaultRegistry.canonicalNoteURL)
        let raw = entry.linkIndex.backlinks(for: canonical)
        return BacklinkPresentation.sorted(raw, notes: entry.notes)
    }
}

private struct BacklinkRow: View {
    let reference: ResolvedReference
    let sourceLabel: String

    var body: some View {
        Button(action: jumpToSource) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: reference.kind == .embed ? "doc.richtext" : "link")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(sourceLabel)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !reference.sourceSnippet.isEmpty {
                    Text(reference.sourceSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func jumpToSource() {
        NavigationRouter.shared.navigate(
            to: reference.sourceNoteID,
            anchor: .sourceOffset(reference.sourceRange.start),
            disposition: NavigationDisposition.click()
        )
    }
}
