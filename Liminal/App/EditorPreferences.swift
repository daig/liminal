import Combine
import Foundation

/// App-wide editor preferences, persisted to `UserDefaults`. Singleton
/// so the SwiftUI command builder can bind a toggle to the same
/// instance that every document's coordinator observes.
@MainActor
final class EditorPreferences: ObservableObject {
    static let shared = EditorPreferences()

    private static let highlightingKey = "editor.highlightingEnabled"

    /// Default `false` — opening a large document is much faster when
    /// the highlight pass is skipped. Flip on via the View menu (or its
    /// keyboard shortcut) to re-enable.
    @Published var highlightingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highlightingEnabled, forKey: Self.highlightingKey)
        }
    }

    private init() {
        // `bool(forKey:)` returns false for missing keys, which matches
        // our intended default.
        self.highlightingEnabled = UserDefaults.standard.bool(forKey: Self.highlightingKey)
    }
}
