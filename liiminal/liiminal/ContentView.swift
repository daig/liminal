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
                                EditorView(editorViewModel: editorVM)
                            }
                        }
                        .toolbar {
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
        .onReceive(NotificationCenter.default.publisher(for: .openVault)) { _ in
            vaultViewModel.openVault()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
