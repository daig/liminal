import SwiftUI

struct WelcomeView: View {
    let onOpenVault: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a Vault")
                .font(.title2)
            Text("Select a folder containing your markdown notes")
                .foregroundStyle(.secondary)
            Button("Open Folder...", action: onOpenVault)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
