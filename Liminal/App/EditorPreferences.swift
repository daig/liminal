import Combine
import Foundation

/// App-wide editor preferences, persisted to `UserDefaults`. Singleton
/// so the SwiftUI command builder can bind a toggle to the same
/// instance that every document's coordinator observes.
@MainActor
final class EditorPreferences: ObservableObject {
    static let shared = EditorPreferences()

    private static let highlightingKey = "editor.highlightingEnabled"
    private static let backlinksKey = "editor.backlinksInspectorVisible"

    /// Default `false` — opening a large document is much faster when
    /// the highlight pass is skipped. Flip on via the View menu (or its
    /// keyboard shortcut) to re-enable.
    @Published var highlightingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highlightingEnabled, forKey: Self.highlightingKey)
        }
    }

    /// Default `true` — surface backlinks while editing so the user
    /// discovers what references the current note. Toggleable from
    /// the View menu when the panel feels cramped.
    @Published var backlinksInspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(backlinksInspectorVisible, forKey: Self.backlinksKey)
        }
    }

    private init() {
        // `bool(forKey:)` returns false for missing keys, which matches
        // our intended default for highlighting.
        self.highlightingEnabled = UserDefaults.standard.bool(forKey: Self.highlightingKey)
        // For the backlinks panel we want default-on, so coerce a
        // missing key to `true` instead of UserDefaults' default of false.
        if UserDefaults.standard.object(forKey: Self.backlinksKey) == nil {
            self.backlinksInspectorVisible = true
        } else {
            self.backlinksInspectorVisible = UserDefaults.standard.bool(forKey: Self.backlinksKey)
        }
    }
}
