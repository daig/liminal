import CambiumCore
import SwiftUI

/// Collapsible inspection pane that surfaces the CST context of the
/// current cursor. The header (always visible) shows a breadcrumb of
/// node kinds from root to the innermost containing node. The body
/// (revealed by clicking the header) shows the cursor's line/column,
/// the node's range, its `childIndexPath`, its structural hash, and a
/// short preview of its source text.
struct CSTInspectorView: View {
    @ObservedObject var inspector: CSTInspector
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider()
                detailBody
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.12)) {
                expanded.toggle()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            breadcrumb
            Spacer(minLength: 8)
            if let cursor = inspector.snapshot?.cursor {
                Text("\(cursor.line):\(cursor.column)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var breadcrumb: some View {
        if let snapshot = inspector.snapshot, !snapshot.breadcrumb.isEmpty {
            BreadcrumbView(steps: snapshot.breadcrumb)
        } else {
            Text("Inspector")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        if let node = inspector.snapshot?.node {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Range", value: rangeString(node.textRange))
                DetailRow(label: "Path", value: pathString(node.path))
                DetailRow(
                    label: "Hash",
                    value: String(format: "0x%016llx", node.structuralHash)
                )
                DetailRow(
                    label: "Text",
                    value: node.preview.isEmpty ? "(empty)" : "\u{201C}\(node.preview)\u{201D}"
                )
            }
        } else {
            Text("No CST data — document not parsed.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func rangeString(_ range: CambiumCore.TextRange) -> String {
        let start = range.start.rawValue
        let end = start + range.length.rawValue
        return "\(start)..<\(end) (\(range.length.rawValue) bytes)"
    }

    private func pathString(_ path: [UInt32]) -> String {
        path.isEmpty ? "[]" : "[" + path.map(String.init).joined(separator: ", ") + "]"
    }
}

private struct BreadcrumbView: View {
    let steps: [CSTBreadcrumbStep]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                if idx > 0 {
                    Text("\u{203A}") // ›
                        .foregroundStyle(.tertiary)
                }
                Text(step.displayName)
                    .foregroundStyle(idx == steps.count - 1 ? .primary : .secondary)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
