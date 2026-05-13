import Foundation

/// Linear undo history of `CSTUndoSnapshot`s. One per document.
///
/// Layout: `snapshots[0]` is the document's initial state, snapshots
/// after that are post-transaction states. `currentIndex` points at
/// the snapshot the document is currently equal to.
///
/// Insert sessions are special — we don't snapshot per-keystroke,
/// only on commit (Esc out of insert). The `insertSessionEntry`
/// field caches the pre-insert snapshot during the session in case
/// it's needed (currently unused, but kept for future "rollback
/// to entry" semantics in case the session is cancelled).
///
/// No branching for v1: pushing a snapshot after an undo truncates
/// the forward history. Future work can swap the linear array for
/// a tree of nodes (the prototype's shape) without changing the
/// snapshot type or the install path.
@MainActor
public final class CSTUndoHistory {
    public private(set) var snapshots: [CSTUndoSnapshot] = []
    public private(set) var currentIndex: Int = -1

    private var insertSessionEntry: CSTUndoSnapshot?

    /// `nonisolated` so the document — which is constructed off the
    /// MainActor by SwiftUI's `DocumentGroup` — can hold one as a
    /// stored property. All mutating methods stay MainActor-bound.
    public nonisolated init() {}

    public var canUndo: Bool { currentIndex > 0 }
    public var canRedo: Bool {
        currentIndex >= 0 && currentIndex < snapshots.count - 1
    }
    public var insertSessionActive: Bool { insertSessionEntry != nil }
    public var depth: Int { snapshots.count }

    /// Reset the history to a single initial snapshot. Called at
    /// document load. Discards any prior history wholesale.
    public func reset(initial: CSTUndoSnapshot) {
        snapshots = [initial]
        currentIndex = 0
        insertSessionEntry = nil
    }

    /// Append a post-transaction snapshot. If we're not at the tip
    /// (e.g., after an undo), the forward history is truncated —
    /// linear semantics, no branching for v1.
    ///
    /// No-op detection: if the new snapshot's `source` matches the
    /// snapshot at `currentIndex`, the call is dropped. Prevents
    /// pure-read paths (visual `y` with no edit, or operator
    /// dispatches that resolved to an empty range) from cluttering
    /// the history with redundant entries.
    ///
    /// Returns `true` if the snapshot was appended; `false` for the
    /// no-op case. Callers (e.g., the document) use this to decide
    /// whether to register a Cocoa undo entry — there's no point
    /// registering one that does nothing.
    @discardableResult
    public func snapshot(_ snap: CSTUndoSnapshot) -> Bool {
        if currentIndex >= 0,
           snapshots[currentIndex].source == snap.source {
            return false
        }
        if currentIndex < snapshots.count - 1 {
            snapshots.removeSubrange((currentIndex + 1)...)
        }
        snapshots.append(snap)
        currentIndex = snapshots.count - 1
        return true
    }

    /// Open an insert-session bracket. The entry-point snapshot is
    /// remembered so we can either commit a single transaction on
    /// session close, or (future) roll back to entry on cancellation.
    public func beginInsertSession(at entry: CSTUndoSnapshot) {
        insertSessionEntry = entry
    }

    /// Close an insert session. If the post-session source differs
    /// from the entry-point's source, append a single transaction
    /// and return `true`; otherwise the session was a no-op (entered
    /// insert and pressed Esc without typing) and is dropped
    /// silently, returning `false`. Returns `false` when no session
    /// was open.
    @discardableResult
    public func commitInsertSession(commit: CSTUndoSnapshot) -> Bool {
        guard let entry = insertSessionEntry else { return false }
        insertSessionEntry = nil
        if entry.source == commit.source { return false }
        return snapshot(commit)
    }

    /// Walk back `count` snapshots; clamp at index 0. Returns nil if
    /// no movement happened (already at oldest).
    public func undo(count: Int = 1) -> CSTUndoSnapshot? {
        let steps = max(1, count)
        let target = max(0, currentIndex - steps)
        guard target != currentIndex else { return nil }
        currentIndex = target
        return snapshots[currentIndex]
    }

    /// Walk forward `count` snapshots; clamp at the tip. Returns nil
    /// if no movement happened (already at newest).
    public func redo(count: Int = 1) -> CSTUndoSnapshot? {
        let steps = max(1, count)
        let target = min(snapshots.count - 1, currentIndex + steps)
        guard target != currentIndex else { return nil }
        currentIndex = target
        return snapshots[currentIndex]
    }
}
