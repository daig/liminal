import SwiftUI

struct SidebarView: View {
    @Bindable var vaultViewModel: VaultViewModel

    var body: some View {
        List(selection: $vaultViewModel.selectedNoteID) {
            if let vault = vaultViewModel.vault {
                Section(vault.name) {
                    ForEach(vault.notes) { note in
                        Text(note.title)
                            .tag(note.id)
                            .lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: { vaultViewModel.createNote(titled: "Untitled") }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Note")
            }
        }
    }
}
