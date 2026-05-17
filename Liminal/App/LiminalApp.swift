import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let liminalMarkup = UTType(exportedAs: "sub.dev.liminal.markup")
}

@main
struct LiminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: LiminalSourceDocument.init) { configuration in
            LiminalEditorView(
                document: configuration.document,
                fileURL: configuration.fileURL
            )
        }
        .commands {
            // SwiftUI's TextEditingCommands provides cut/copy/paste/undo/
            // select-all but not Find. Add a Find submenu wired to
            // NSResponder.performTextFinderAction(_:) so NSTextView's
            // built-in find bar lights up via Cmd-F / Cmd-G / Cmd-Shift-G.
            CommandGroup(after: .pasteboard) {
                Divider()
                FindMenu()
            }
            // Sandbox-friendly vault entry: picks a folder via
            // NSOpenPanel and registers the resulting security-scoped
            // bookmark. Sits right after File > New / Open so it
            // appears alongside the standard file actions.
            CommandGroup(after: .newItem) {
                OpenVaultMenuItem()
            }
            CommandMenu("View") {
                ViewMenu()
            }
        }
    }
}

/// Hooks `applicationWillTerminate` so every vault's warm-tier cache is
/// flushed to disk before the process exits — the debounced async flush
/// has no chance to run during termination.
///
/// Also restores security-scoped bookmarks at launch and observes the
/// folder-access-needed notification posted by `VaultRegistry` when a
/// cold-start scan hits an un-bookmarked vault.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var folderAccessObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Resolve every stored vault bookmark and start its
            // security-scoped session. Wikilink machinery in any
            // pre-existing recent document then works without a prompt.
            let registry = VaultRegistry.shared
            for root in VaultBookmarkStore.shared.allVaultRoots() {
                registry.ensureAccessing(root)
            }

            // Don't register the modal-prompt observer in test runs —
            // the test target shares the app's lifecycle, and a stray
            // requestFolderAccess from a test fixture would hang the
            // whole suite on NSOpenPanel.runModal(). Tests use the
            // sandbox-container temp dir (always enumerable without a
            // bookmark), so the upstream check in VaultEntry's
            // cold-start scan already short-circuits the request in
            // the common case — this is defense-in-depth.
            guard NSClassFromString("XCTest") == nil else { return }

            // Lazy prompt: VaultEntry.beginColdStartScanIfNeeded posts
            // this when it has no bookmark for a vault root. Pull the
            // URL out synchronously (NotificationCenter dispatches the
            // closure on the main queue when `queue: .main`), then hop
            // into MainActor isolation to drive the NSOpenPanel.
            folderAccessObserver = NotificationCenter.default.addObserver(
                forName: VaultRegistry.folderAccessNeededNotification,
                object: nil,
                queue: .main
            ) { notification in
                let root = notification.userInfo?[VaultRegistry.vaultRootKey] as? URL
                Task { @MainActor in
                    guard let root else { return }
                    Self.promptForVaultFolderAccess(at: root)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            VaultRegistry.shared.flushAllCachesSynchronously()
        }
    }

    /// Show `NSOpenPanel` pre-filled to the requested vault root,
    /// capture the resulting security-scoped bookmark, and register it
    /// with `VaultRegistry`. The newly-accessing session lets the
    /// caller's next cold-start-scan attempt actually enumerate the
    /// folder.
    @MainActor
    static func promptForVaultFolderAccess(at suggestedRoot: URL) {
        let panel = NSOpenPanel()
        panel.title = "Grant Liminal access to this vault folder"
        panel.message = "Liminal needs access to “\(suggestedRoot.lastPathComponent)” to follow wikilinks and build the backlink index."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggestedRoot
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        registerVaultFolder(chosen)
    }

    /// Show `NSOpenPanel` for an explicit user-driven "Open Vault…"
    /// action. Same machinery as the lazy prompt but with no
    /// suggested root.
    @MainActor
    static func runOpenVaultPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Vault"
        panel.message = "Choose the folder that contains your Liminal notes."
        panel.prompt = "Open Vault"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        registerVaultFolder(chosen)
    }

    @MainActor
    private static func registerVaultFolder(_ url: URL) {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            NSLog("Liminal: failed to create security-scoped bookmark for \(url.path)")
            return
        }
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        VaultRegistry.shared.registerBookmark(data, forVaultRoot: canonical)
        // Kick the cold-start scan so wikilinks light up immediately.
        VaultRegistry.shared.entry(forRoot: canonical).beginColdStartScanIfNeeded()
    }
}

/// SwiftUI button that triggers the explicit "Open Vault…" flow.
/// Lives in `.newItem` group so it sits alongside File > New.
private struct OpenVaultMenuItem: View {
    var body: some View {
        Button("Open Vault…") {
            AppDelegate.runOpenVaultPanel()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

/// View-menu commands: syntax-highlighting and backlinks-inspector toggles.
private struct ViewMenu: View {
    @ObservedObject private var prefs = EditorPreferences.shared

    var body: some View {
        Toggle(isOn: $prefs.highlightingEnabled) {
            Text("Syntax Highlighting")
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Toggle(isOn: $prefs.backlinksInspectorVisible) {
            Text("Backlinks Inspector")
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
    }
}

private struct FindMenu: View {
    var body: some View {
        Menu("Find") {
            Button("Find…") {
                sendTextFinderAction(.showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                sendTextFinderAction(.nextMatch)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") {
                sendTextFinderAction(.previousMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("Use Selection for Find") {
                sendTextFinderAction(.setSearchString)
            }
            .keyboardShortcut("e", modifiers: .command)
        }
    }

    /// Dispatch a text-finder action via the responder chain. NSTextView's
    /// `performTextFinderAction(_:)` reads the sender's `tag` to decide
    /// which action to perform, so we synthesize an NSMenuItem with the
    /// right tag and pass it as the sender.
    private func sendTextFinderAction(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(
            #selector(NSResponder.performTextFinderAction(_:)),
            to: nil,
            from: item
        )
    }
}
