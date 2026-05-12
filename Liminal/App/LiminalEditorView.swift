import SwiftUI

struct LiminalEditorView: View {
    @ObservedObject var viewModel: LiminalEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            LiminalTextView(viewModel: viewModel)
            Divider()
            StatusBar(viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var viewModel: LiminalEditorViewModel

    var body: some View {
        HStack(spacing: 16) {
            Label("\(viewModel.diagnosticsCount)", systemImage: "exclamationmark.triangle")
                .foregroundColor(viewModel.diagnosticsCount == 0 ? .secondary : .orange)
            Label(
                "\(viewModel.reuseSummary.acceptedReuses)/\(viewModel.reuseSummary.queries) reused",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundColor(.secondary)
            Spacer()
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .labelStyle(.titleAndIcon)
    }
}
