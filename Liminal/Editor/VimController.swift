import Combine
import Foundation

/// Single source of truth for vim state — mode, pending keys, pending
/// count. SwiftUI views subscribe to it; the NSTextView subclass
/// forwards keys to it. The controller dispatches resolved commands via
/// a delegate (the document, in production).
///
/// Design notes vs the reference implementation:
/// - Mode is owned here only. The view reads, never writes.
/// - `resetPending()` is the **single** function that clears pending
///   state. Called from exactly three sites: after a successful dispatch,
///   after a mode change, and after an unmatched key. No scattered
///   defensive clearing.
/// - The command interpreter is a focused switch over `VimCommand`, not
///   a god-function. New commands just add a case + a binding entry.
/// - Derived presentation (`statusPresentation`, `visibleHintSnapshot`)
///   is recomputed exactly once per `handle(_:)` via a `defer`, so every
///   pending-state mutation path is covered without scattering refresh
///   calls.
@MainActor
public final class VimController: ObservableObject {
    @Published public private(set) var mode: VimMode = .normal
    @Published public private(set) var pendingKeys: [VimKey] = []
    @Published public private(set) var pendingCount: Int?

    /// Mode + pending detail formatted for the status bar.
    @Published public private(set) var statusPresentation =
        VimStatusPresentation(mode: .normal, detailText: nil)

    /// The hint snapshot the overlay should display, or `nil` to hide
    /// the overlay. Driven by the onset-delay state machine: a new
    /// prefix becomes visible only after `hintOnsetDelay`, but
    /// extending an already-visible prefix updates the snapshot
    /// immediately (no flicker).
    @Published public private(set) var visibleHintSnapshot: VimHintSnapshot?

    public weak var delegate: VimControllerDelegate?

    private nonisolated(unsafe) let bindings: VimBindingTree
    private nonisolated let hintOnsetDelay: Duration

    private var hintShowTask: Task<Void, Never>?

    public nonisolated init(
        bindings: VimBindingTree,
        hintOnsetDelay: Duration = .milliseconds(200)
    ) {
        self.bindings = bindings
        self.hintOnsetDelay = hintOnsetDelay
    }

    public nonisolated convenience init() {
        self.init(bindings: VimController.defaultBindings())
    }

    // MARK: - Key handling

    /// Process one key. In Normal mode, all keys are `.consumed` so the
    /// NSTextView never sees them as input. In Insert mode, keys the
    /// controller doesn't claim (the only one it does is `<Esc>` →
    /// Normal) return `.passthrough` so NSTextView's regular typing
    /// pipeline handles them.
    public func handle(_ key: VimKey) -> KeyHandled {
        // Every path through `handle` mutates pendingKeys / pendingCount /
        // mode at least once (or leaves them unchanged in the count-zero
        // no-op case). Recomputing derived state at the boundary covers
        // them all uniformly.
        defer { refreshDerived() }

        switch mode {
        case .normal:
            return handleNormal(key)
        case .insert:
            return handleInsert(key)
        }
    }

    private func handleNormal(_ key: VimKey) -> KeyHandled {
        // Count digits before any pending keys: build pendingCount.
        // Bare leading `0` falls through to the binding tree as the
        // line-start motion in vim; once a count is already started,
        // `0` is the trailing digit (e.g., `30`).
        if pendingKeys.isEmpty,
           let digit = key.asCountDigit,
           !(digit == 0 && pendingCount == nil) {
            pendingCount = (pendingCount ?? 0) * 10 + digit
            return .consumed
        }

        let tentative = pendingKeys + [key]
        switch bindings.resolve(tentative, mode: .normal, count: pendingCount) {
        case .command(let command):
            resetPending()
            dispatch(command)
        case .partial:
            pendingKeys = tentative
        case .none:
            resetPending()
        }
        return .consumed
    }

    private func handleInsert(_ key: VimKey) -> KeyHandled {
        let tentative = pendingKeys + [key]
        switch bindings.resolve(tentative, mode: .insert, count: pendingCount) {
        case .command(let command):
            resetPending()
            dispatch(command)
            return .consumed
        case .partial:
            pendingKeys = tentative
            return .consumed
        case .none:
            resetPending()
            return .passthrough
        }
    }

    // MARK: - State management

    /// The single function that clears pending state. Don't inline this
    /// logic anywhere else.
    private func resetPending() {
        pendingKeys = []
        pendingCount = nil
    }

    /// Single mode-change point.
    private func setMode(_ newMode: VimMode) {
        mode = newMode
        resetPending()
    }

    // MARK: - Derived state

    /// Recompute `statusPresentation` and schedule / replace the hint
    /// snapshot. Called once per `handle(_:)` invocation via `defer`.
    private func refreshDerived() {
        statusPresentation = VimStatusPresentation.make(
            mode: mode,
            pendingKeys: pendingKeys,
            pendingCount: pendingCount
        )
        refreshHintSnapshot()
    }

    /// Hint-onset state machine. Cancel any in-flight delay task; if
    /// the prefix is empty, clear the snapshot. Otherwise build the
    /// snapshot from the binding tree's hints. If a snapshot is already
    /// visible (we're extending an existing chord), replace immediately
    /// — no delay, no flicker. Otherwise schedule the replacement
    /// after `hintOnsetDelay` so transient chord input doesn't briefly
    /// flash the overlay.
    private func refreshHintSnapshot() {
        hintShowTask?.cancel()
        hintShowTask = nil

        guard !pendingKeys.isEmpty else {
            visibleHintSnapshot = nil
            return
        }

        let items = bindings.hints(after: pendingKeys, mode: mode)
        guard !items.isEmpty else {
            visibleHintSnapshot = nil
            return
        }

        let title = pendingKeys.map(\.displayString).joined()
        let snapshot = VimHintSnapshot(title: title, items: items)

        // Already-visible snapshot: replace synchronously so chord
        // extensions feel continuous.
        if visibleHintSnapshot != nil {
            visibleHintSnapshot = snapshot
            return
        }

        // First-appearance: with zero delay, set synchronously so tests
        // (which inject `.zero`) don't need to await. Otherwise schedule
        // an awaitable task that re-checks the prefix before firing.
        if hintOnsetDelay == .zero {
            visibleHintSnapshot = snapshot
            return
        }

        let prefixAtSchedule = pendingKeys
        let delay = hintOnsetDelay
        hintShowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Drop the snapshot if the prefix changed under us.
            guard self.pendingKeys == prefixAtSchedule else { return }
            self.visibleHintSnapshot = snapshot
            self.hintShowTask = nil
        }
    }

    // MARK: - Command interpreter

    private func dispatch(_ command: VimCommand) {
        switch command {
        case .enterInsertMode:
            setMode(.insert)
        case .enterNormalMode:
            setMode(.normal)
        case .moveCursor(let motion, let count):
            delegate?.moveCursor(motion: motion, count: count)
        case .structuralMotion(let motion, let count):
            delegate?.structuralMotion(motion, count: count)
        case .toggleTaskAtCursor:
            delegate?.toggleTaskAtCursor()
        }
    }

    // MARK: - Default bindings

    public nonisolated static func defaultBindings() -> VimBindingTree {
        var t = VimBindingTree()

        // Mode transitions
        t.bind(.normal, [.char("i")], description: "Insert at cursor") { _ in
            .enterInsertMode
        }
        t.bind(.insert, [.special(.escape)], description: "Back to Normal") { _ in
            .enterNormalMode
        }

        // Basic motion — h/j/k/l and arrows are aliases for the same
        // commands; arrow keys also work in Insert mode (they fall through
        // to NSTextView's normal handling since they're unbound there).
        let leftMotion:  @Sendable (Int?) -> VimCommand = { .moveCursor(.left,  count: $0 ?? 1) }
        let rightMotion: @Sendable (Int?) -> VimCommand = { .moveCursor(.right, count: $0 ?? 1) }
        let downMotion:  @Sendable (Int?) -> VimCommand = { .moveCursor(.down,  count: $0 ?? 1) }
        let upMotion:    @Sendable (Int?) -> VimCommand = { .moveCursor(.up,    count: $0 ?? 1) }

        t.bind(.normal, [.char("h")],            description: "Move left",  command: leftMotion)
        t.bind(.normal, [.special(.left)],       description: "Move left",  command: leftMotion)
        t.bind(.normal, [.char("l")],            description: "Move right", command: rightMotion)
        t.bind(.normal, [.special(.right)],      description: "Move right", command: rightMotion)
        t.bind(.normal, [.char("j")],            description: "Move down",  command: downMotion)
        t.bind(.normal, [.special(.down)],       description: "Move down",  command: downMotion)
        t.bind(.normal, [.char("k")],            description: "Move up",    command: upMotion)
        t.bind(.normal, [.special(.up)],         description: "Move up",    command: upMotion)

        // Line motion (within the current line — count is ignored).
        t.bind(.normal, [.char("0")], description: "Line start") { _ in
            .moveCursor(.lineStart, count: 1)
        }
        t.bind(.normal, [.char("^")], description: "First non-blank") { _ in
            .moveCursor(.lineFirstNonBlank, count: 1)
        }
        t.bind(.normal, [.char("$")], description: "Line end") { _ in
            .moveCursor(.lineEnd, count: 1)
        }

        // Word motion (count = number of words).
        t.bind(.normal, [.char("w")], description: "Next word") {
            .moveCursor(.wordForwardStart, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("b")], description: "Previous word") {
            .moveCursor(.wordBackward, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("e")], description: "Word end") {
            .moveCursor(.wordForwardEnd, count: $0 ?? 1)
        }

        // Document jumps. `gg` defaults to line 1; `G` defaults to the
        // last line. With an explicit count, both jump to that absolute
        // line. The Int.max sentinel encodes "no count given" for `G`.
        t.bind(.normal, [.char("g"), .char("g")],
               description: "First line / line N") {
            .moveCursor(.documentStart, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("G")], description: "Last line / line N") {
            .moveCursor(.documentEnd, count: $0 ?? Int.max)
        }

        // Structural sibling motion
        t.bind(.normal, [.char("{")], description: "Previous sibling block") {
            .structuralMotion(.previousSibling, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("}")], description: "Next sibling block") {
            .structuralMotion(.nextSibling, count: $0 ?? 1)
        }

        // Leader chord
        t.bind(.normal, [.special(.space), .char("t")],
               description: "Toggle task checkbox") { _ in
            .toggleTaskAtCursor
        }

        return t
    }
}

public enum KeyHandled: Sendable, Equatable {
    /// Controller claimed the key; NSTextView should not see it.
    case consumed
    /// Controller didn't claim the key; NSTextView should handle as normal.
    case passthrough
}

/// Adapter the controller calls into for side effects. The document is
/// the production conformer; tests provide spies.
@MainActor
public protocol VimControllerDelegate: AnyObject {
    func moveCursor(motion: CursorMotion, count: Int)
    func structuralMotion(_ motion: StructuralMotion, count: Int)
    func toggleTaskAtCursor()
}
