import SwiftUI

struct ContentView: View {
    @State private var vaultViewModel = VaultViewModel()
    @State private var editorViewModel: EditorViewModel?
    @State private var showPreview = false
    @State private var previewFontSize: CGFloat = 16

    var body: some View {
        Group {
            if vaultViewModel.vault != nil {
                NavigationSplitView {
                    SidebarView(vaultViewModel: vaultViewModel)
                } detail: {
                    if let editorVM = editorViewModel, editorVM.currentNote != nil {
                        Group {
                            if showPreview {
                                RenderedDocumentView(document: editorVM.document, baseFontSize: $previewFontSize)
                            } else {
                                ZStack(alignment: .bottom) {
                                    EditorView(editorViewModel: editorVM)

                                    if let hintSnapshot = editorVM.vimHintSnapshot {
                                        VimHintOverlayView(snapshot: hintSnapshot)
                                            .transition(.opacity)
                                            .zIndex(1)
                                    }
                                }
                            }
                        }
                        .toolbar {
                            if !showPreview {
                                ToolbarItem(placement: .automatic) {
                                    HStack(spacing: 6) {
                                        Text(editorVM.vimMode.rawValue.uppercased())
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .foregroundStyle(
                                                editorVM.vimMode == .normal ? .orange : .secondary
                                            )
                                            .background(
                                                editorVM.vimMode == .normal
                                                    ? Color.orange.opacity(0.15)
                                                    : Color.secondary.opacity(0.1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 4))

                                        if let detailText = editorVM.vimStatus.detailText {
                                            Text(detailText)
                                                .font(
                                                    .system(
                                                        size: 11,
                                                        weight: .medium,
                                                        design: .monospaced
                                                    )
                                                )
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .foregroundStyle(.secondary)
                                                .background(Color.secondary.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                }
                            }
                            ToolbarItem(placement: .automatic) {
                                Button {
                                    showPreview.toggle()
                                } label: {
                                    Image(
                                        systemName: showPreview
                                            ? "pencil.line" : "eye"
                                    )
                                }
                                .keyboardShortcut("e", modifiers: .command)
                                .help(showPreview ? "Edit" : "Preview")
                            }
                        }
                    } else {
                        Text("Select a note")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                WelcomeView(onOpenVault: { vaultViewModel.openVault() })
            }
        }
        .onAppear {
            editorViewModel = EditorViewModel(fileService: vaultViewModel.fileService)
            vaultViewModel.restorePreviousVault()
        }
        .onChange(of: vaultViewModel.selectedNoteID) { _, _ in
            if let note = vaultViewModel.selectedNote {
                editorViewModel?.openNote(note)
            }
        }
        .onChange(of: showPreview) { _, _ in
            editorViewModel?.clearVimHints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVault)) { _ in
            vaultViewModel.openVault()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
