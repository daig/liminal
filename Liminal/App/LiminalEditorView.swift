import SwiftUI

struct LiminalEditorView: View {
    @ObservedObject var document: LiminalSourceDocument

    var body: some View {
        VStack(spacing: 0) {
            LiminalTextView(document: document)
            Divider()
            StatusBar(document: document)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var document: LiminalSourceDocument

    var body: some View {
        HStack(spacing: 16) {
            Label("\(document.diagnosticsCount)", systemImage: "exclamationmark.triangle")
                .foregroundColor(document.diagnosticsCount == 0 ? .secondary : .orange)
            Label(
                "\(document.reuseSummary.acceptedReuses)/\(document.reuseSummary.queries) reused",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundColor(.secondary)
            Spacer()
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .labelStyle(.titleAndIcon)
    }
}
