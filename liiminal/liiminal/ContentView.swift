import SwiftUI

struct ContentView: View {
    @State private var vaultViewModel = VaultViewModel()
    @State private var editorViewModel: EditorViewModel?

    var body: some View {
        Group {
            if vaultViewModel.vault != nil {
                NavigationSplitView {
                    SidebarView(vaultViewModel: vaultViewModel)
                } detail: {
                    if let editorVM = editorViewModel, editorVM.currentNote != nil {
                        EditorView(editorViewModel: editorVM)
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
