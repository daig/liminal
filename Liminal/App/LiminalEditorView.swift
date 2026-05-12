import SwiftUI

struct LiminalEditorView: View {
    @ObservedObject var document: LiminalSourceDocument

    var body: some View {
        VStack(spacing: 0) {
            LiminalTextView(document: document)
                .overlay(alignment: .bottom) {
                    HintOverlayHost(controller: document.vimController)
                }
            Divider()
            StatusBar(document: document, controller: document.vimController)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Divider()
            CSTInspectorView(inspector: document.cstInspector)
        }
    }
}

/// Subscribes to the controller so the overlay actually updates when
/// `visibleHintSnapshot` changes. SwiftUI's `@ObservedObject` only
/// propagates `objectWillChange` for the directly-observed object —
/// reading `document.vimController.visibleHintSnapshot` from the parent
/// view won't trigger a re-render when only the nested controller's
/// state changes.
private struct HintOverlayHost: View {
    @ObservedObject var controller: VimController

    var body: some View {
        VimHintOverlayView(snapshot: controller.visibleHintSnapshot)
            .animation(.easeOut(duration: 0.11),
                       value: controller.visibleHintSnapshot)
            .allowsHitTesting(false)
    }
}

private struct StatusBar: View {
    @ObservedObject var document: LiminalSourceDocument
    @ObservedObject var controller: VimController

    var body: some View {
        HStack(spacing: 16) {
            ModeBadge(mode: controller.statusPresentation.mode)
            Label("\(document.diagnosticsCount)", systemImage: "exclamationmark.triangle")
                .foregroundColor(document.diagnosticsCount == 0 ? .secondary : .orange)
            Label(
                "\(document.reuseSummary.acceptedReuses)/\(document.reuseSummary.queries) reused",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundColor(.secondary)
            Spacer()
            if let detail = controller.statusPresentation.detailText {
                Text("(\(detail))")
                    .foregroundColor(.secondary)
            }
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
