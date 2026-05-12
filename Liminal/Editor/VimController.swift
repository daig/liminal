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
@MainActor
public final class VimController: ObservableObject {
    @Published public private(set) var mode: VimMode = .normal
    @Published public private(set) var pendingKeys: [VimKey] = []
    @Published public private(set) var pendingCount: Int?

    public weak var delegate: VimControllerDelegate?

    private nonisolated(unsafe) let bindings: VimBindingTree

    public nonisolated init(bindings: VimBindingTree) {
        self.bindings = bindings
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
        switch mode {
        case .normal:
            return handleNormal(key)
        case .insert:
            return handleInsert(key)
        }
    }

    private func handleNormal(_ key: VimKey) -> KeyHandled {
        // Count digits before any pending keys: build pendingCount.
        if pendingKeys.isEmpty, let digit = key.asCountDigit {
            if digit == 0 && pendingCount == nil {
                // Bare leading `0` is a motion in real vim (first column);
                // not yet bound in slice 3. Treat as no-op so it doesn't
                // get mistaken for "count zero."
                return .consumed
            }
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

    // MARK: - Hints

    public var hints: [VimBindingTree.HintEntry] {
        bindings.hints(after: pendingKeys, mode: mode)
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

    // MARK: - Command interpreter

    private func dispatch(_ command: VimCommand) {
        switch command {
        case .enterInsertMode:
            setMode(.insert)
        case .enterNormalMode:
            setMode(.normal)
        case .moveCursor(let direction, let count):
            delegate?.moveCursor(direction: direction, count: count)
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

        // Basic motion
        t.bind(.normal, [.char("h")], description: "Move left") {
            .moveCursor(.left, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("l")], description: "Move right") {
            .moveCursor(.right, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("j")], description: "Move down") {
            .moveCursor(.down, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("k")], description: "Move up") {
            .moveCursor(.up, count: $0 ?? 1)
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
    func moveCursor(direction: MoveDirection, count: Int)
    func structuralMotion(_ motion: StructuralMotion, count: Int)
    func toggleTaskAtCursor()
}
