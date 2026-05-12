import SwiftUI

struct LiminalEditorView: View {
    @ObservedObject var document: LiminalSourceDocument

    var body: some View {
        VStack(spacing: 0) {
            LiminalTextView(document: document)
            Divider()
            StatusBar(document: document, controller: document.vimController)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var document: LiminalSourceDocument
    @ObservedObject var controller: VimController

    var body: some View {
        HStack(spacing: 16) {
            ModeBadge(mode: controller.mode)
            Label("\(document.diagnosticsCount)", systemImage: "exclamationmark.triangle")
                .foregroundColor(document.diagnosticsCount == 0 ? .secondary : .orange)
            Label(
                "\(document.reuseSummary.acceptedReuses)/\(document.reuseSummary.queries) reused",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundColor(.secondary)
            Spacer()
            PendingChord(controller: controller)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .labelStyle(.titleAndIcon)
    }
}

private struct ModeBadge: View {
    let mode: VimMode

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background)
            .cornerRadius(3)
    }

    private var label: String {
        switch mode {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        }
    }

    private var background: Color {
        switch mode {
        case .normal: return .blue
        case .insert: return .green
        }
    }
}

private struct PendingChord: View {
    @ObservedObject var controller: VimController

    var body: some View {
        if !controller.pendingKeys.isEmpty {
            let prefix = controller.pendingKeys.map(\.displayString).joined()
            let hints = controller.hints
                .prefix(6)
                .map { "\($0.key.displayString): \($0.description)" }
                .joined(separator: "  ")
            Text("(\(prefix)) → \(hints)")
        } else if let count = controller.pendingCount {
            Text("(\(count))")
        } else {
            EmptyView()
        }
    }
}
