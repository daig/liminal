import AppKit
import SwiftUI

struct LiminalEditorView: View {
    @ObservedObject private var document: LiminalSourceDocument
    @StateObject private var workspace: WorkspaceWindowController
    @ObservedObject private var prefs = EditorPreferences.shared

    /// File URL passed down from the `DocumentGroup`'s
    /// `ReferenceFileDocumentConfiguration.fileURL`. Nil for untitled
    /// documents. Forwarded to the document so workspace components
    /// (vault registration, navigation) can reach it.
    let fileURL: URL?

    init(document: LiminalSourceDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _workspace = StateObject(
            wrappedValue: WorkspaceWindowController(
                initialDocument: document,
                initialFileURL: fileURL
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(WorkspaceWindowActivationBridge(workspace: workspace))
        .onAppear {
            workspace.updateHostDocument(document, fileURL: fileURL)
            NavigationRouter.shared.activateWorkspace(workspace)
        }
        .onChange(of: fileURL) { _, newValue in
            workspace.updateHostDocument(document, fileURL: newValue)
        }
        .onDisappear {
            NavigationRouter.shared.deactivateWorkspace(workspace)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if let tab = workspace.activeTab {
            WorkspaceSidebar(tab: tab)
        } else {
            EmptyWorkspaceSidebar()
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(
                tabs: workspace.tabs,
                selectedTabID: Binding(
                    get: { workspace.selectedTabID },
                    set: { newValue in
                        if let newValue {
                            workspace.selectTab(newValue)
                        }
                    }
                ),
                close: { workspace.closeTab($0) }
            )
            Divider()
            if let tab = workspace.activeTab {
                WorkspaceDetail(tab: tab, prefs: prefs)
            }
        }
    }
}

private struct WorkspaceSidebar: View {
    @ObservedObject var tab: WorkspaceTab

    var body: some View {
        if let url = tab.fileURL {
            VaultSidebarView(
                entry: VaultRegistry.shared.entry(for: url),
                currentDocURL: url
            )
            .frame(minWidth: 240, idealWidth: 320)
        } else {
            EmptyWorkspaceSidebar()
        }
    }
}

private struct EmptyWorkspaceSidebar: View {
    var body: some View {
        VStack {
            Text("Save the document to enable\nthe vault navigator.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(minWidth: 240, idealWidth: 320)
    }
}

private struct WorkspaceDetail: View {
    @ObservedObject var tab: WorkspaceTab
    @ObservedObject var prefs: EditorPreferences

    var body: some View {
        HStack(spacing: 0) {
            editorContent
            if prefs.backlinksInspectorVisible {
                Divider()
                RightInspectorView(
                    entry: tab.fileURL.map { VaultRegistry.shared.entry(for: $0) },
                    currentDocURL: tab.fileURL
                )
            }
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            LiminalTextView(
                document: tab.document,
                navigationRequest: tab.navigationRequest
            )
            .id(tab.contentIdentity)
            .overlay(alignment: .bottom) {
                HintOverlayHost(controller: tab.document.vimController)
            }
            .overlay(alignment: .bottom) {
                CommandLinePopupHost(controller: tab.document.vimController)
            }
            .overlay(alignment: .bottomTrailing) {
                NarrowChainOverlayHost(controller: tab.document.vimController)
            }
            Divider()
            StatusBar(document: tab.document, controller: tab.document.vimController)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Divider()
            CSTInspectorView(inspector: tab.document.cstInspector)
        }
    }
}

/// Observer wrapper around `VimController` for the command-line popup.
/// Mirrors the `HintOverlayHost` pattern — SwiftUI needs the
/// `@ObservedObject` declared on the consuming view (not on a parent)
/// for nested-controller publishes to drive re-renders.
private struct CommandLinePopupHost: View {
    @ObservedObject var controller: VimController

    var body: some View {
        CommandLinePopupView(
            entries: controller.commandLineCompletions,
            highlightedIndex: controller.commandLineHighlightedIndex,
            onRowAccepted: { _ in
                // Click-to-select isn't wired through the controller's
                // dispatch in v1 — the popup is keyboard-driven. A
                // future slice can add `controller.acceptCompletion(at:)`
                // and route the click through it.
            }
        )
        .animation(.easeOut(duration: 0.11),
                   value: controller.commandLineCompletions)
    }
}

/// Observer wrapper around `VimController` for the narrow-chain
/// visualizer. Same pattern as `CommandLinePopupHost` — SwiftUI needs
/// the `@ObservedObject` declared on the consuming view so the
/// controller's `@Published narrowChainPreview` actually drives
/// re-renders.
private struct NarrowChainOverlayHost: View {
    @ObservedObject var controller: VimController

    var body: some View {
        NarrowChainOverlayView(entries: controller.narrowChainPreview)
            .animation(.easeOut(duration: 0.11),
                       value: controller.narrowChainPreview)
    }
}

private struct WorkspaceTabBar: View {
    let tabs: [WorkspaceTab]
    @Binding var selectedTabID: WorkspaceTab.ID?
    let close: (WorkspaceTab.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(tabs) { tab in
                    WorkspaceTabButton(
                        tab: tab,
                        isSelected: selectedTabID == tab.id,
                        canClose: tabs.count > 1,
                        select: { selectedTabID = tab.id },
                        close: { close(tab.id) }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorkspaceTabButton: View {
    @ObservedObject var tab: WorkspaceTab
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text(tab.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 72, maxWidth: 180, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if canClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close Tab")
            }
        }
    }

    private var background: Color {
        isSelected
            ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
            : Color.clear
    }
}

private struct WorkspaceWindowActivationBridge: NSViewRepresentable {
    let workspace: WorkspaceWindowController

    func makeNSView(context: Context) -> ActivationView {
        let view = ActivationView()
        view.onBecomeKey = { [weak workspace] in
            Task { @MainActor in
                guard let workspace else { return }
                NavigationRouter.shared.activateWorkspace(workspace)
            }
        }
        return view
    }

    func updateNSView(_ nsView: ActivationView, context: Context) {
        nsView.onBecomeKey = { [weak workspace] in
            Task { @MainActor in
                guard let workspace else { return }
                NavigationRouter.shared.activateWorkspace(workspace)
            }
        }
    }

    final class ActivationView: NSView {
        var onBecomeKey: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: nil
            )
            guard let window else { return }
            if window.isKeyWindow {
                onBecomeKey?()
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window,
            )
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            onBecomeKey?()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
            if let commandLine = controller.statusPresentation.commandLineInput {
                // `:` mode — replace diagnostics / reuse summary with
                // the live typed command. Underscore acts as a static
                // caret cue without the complexity of a blinking one.
                Text(":\(commandLine)_")
                    .foregroundColor(.primary)
                Spacer()
            } else {
                Label("\(document.diagnosticsCount)", systemImage: "exclamationmark.triangle")
                    .foregroundColor(document.diagnosticsCount == 0 ? .secondary : .orange)
                Label(
                    "\(document.reuseSummary.acceptedReuses)/\(document.reuseSummary.queries) reused",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .foregroundColor(.secondary)
                Spacer()
                if document.ubiquityDownloadInProgress {
                    Label("Downloading from iCloud…", systemImage: "icloud.and.arrow.down")
                        .foregroundColor(.blue)
                }
                if let detail = controller.statusPresentation.detailText {
                    Text("(\(detail))")
                        .foregroundColor(.secondary)
                }
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
        case .normal:      return "NORMAL"
        case .insert:      return "INSERT"
        case .visual:      return "VISUAL"
        case .visualLine:  return "V-LINE"
        case .visualBlock: return "V-BLOCK"
        case .visualCST:   return "V-CST"
        case .commandLine: return "COMMAND"
        }
    }

    private var background: Color {
        switch mode {
        case .normal:      return .blue
        case .insert:      return .green
        case .visual:      return .purple
        case .visualLine:  return .pink
        case .visualBlock: return .orange
        case .visualCST:   return .teal
        case .commandLine: return .yellow
        }
    }
}
