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
            CommandMenu("View") {
                ViewMenu()
            }
        }
    }
}

/// Hooks `applicationWillTerminate` so every vault's warm-tier cache is
/// flushed to disk before the process exits — the debounced async flush
/// has no chance to run during termination.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            VaultRegistry.shared.flushAllCachesSynchronously()
        }
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
