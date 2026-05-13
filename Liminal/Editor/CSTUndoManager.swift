import Foundation

/// `UndoManager` subclass with a pre-undo hook so the document can
/// run setup before the standard undo flow fires. Used to commit any
/// active insert session before walking history — vim's `<Esc>u`
/// semantics for the ⌘Z path while the user is mid-typing.
///
/// Not class-level `@MainActor` so the document (which is itself
/// constructed off the MainActor by SwiftUI's `DocumentGroup`) can
/// hold one as a stored property. The Cocoa undo-action plumbing
/// always invokes `undo:` / `redo:` on the main thread, so the
/// `MainActor.assumeIsolated` inside `undo()` is safe in production.
public final class CSTUndoManager: UndoManager, @unchecked Sendable {
    /// Invoked synchronously at the top of `undo()`. Typical use:
    /// commit any active insert session so the upcoming undo lands at
    /// the pre-insert state rather than requiring two ⌘Zs.
    public var preUndoHook: (@MainActor () -> Void)?

    public override func undo() {
        if let hook = preUndoHook {
            MainActor.assumeIsolated { hook() }
        }
        super.undo()
    }
}
