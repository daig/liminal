import CambiumCore
import CambiumIncremental
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

    /// Set when a command (currently `m` / `` ` ``) is waiting for the
    /// next key as a character argument. While non-nil, `handle(_:)`
    /// routes the next key into the consumer instead of the binding
    /// tree.
    @Published public private(set) var pendingCharArgument: PendingCharArgument?

    /// Set after `d` / `c` / `y` in normal mode: an operator is waiting
    /// for its target. Subsequent keys still route through the binding
    /// tree (so digit counts and chord prefixes work normally), but the
    /// dispatch interceptor wraps the resolved command into an
    /// `.applyOperator(...)` and routes that to the delegate instead.
    @Published public private(set) var pendingOperator: PendingOperator?

    /// Per-document mark store (`m<a-z>` / `` `<a-z> ``). Owned here so
    /// SwiftUI views observing the controller pick up mark changes
    /// automatically.
    @Published public private(set) var marks = MarkRegistry()

    /// Live buffer accumulated during `.commandLine` mode. SwiftUI
    /// status views observe this to render `:input` as the user types.
    /// Cleared on Enter (after dispatch) or Esc.
    @Published public private(set) var commandLineInput: String = ""

    /// Completion entries for the current `commandLineInput`, in display
    /// order. The popup view consumes this directly. Recomputed whenever
    /// `commandLineInput` mutates.
    @Published public private(set) var commandLineCompletions: [CompletionEntry] = []

    /// Index of the currently-highlighted entry in `commandLineCompletions`,
    /// or `nil` for "no selection" (which is the default state when the
    /// popup first appears on empty input). Driven by Down/Up/Tab/Shift-Tab.
    @Published public private(set) var commandLineHighlightedIndex: Int? = nil

    public weak var delegate: VimControllerDelegate?

    private nonisolated(unsafe) let bindings: VimBindingTree
    private nonisolated let hintOnsetDelay: Duration
    private nonisolated(unsafe) let commands: CommandRegistry

    private var hintShowTask: Task<Void, Never>?

    /// Mode to restore when `.commandLine` exits (via Enter dispatch
    /// or Esc cancel). Captured when entering, defaulted to .normal
    /// for safety. Internal — UI doesn't need to observe it.
    private var commandLineReturnMode: VimMode = .normal

    /// Lazily-computed reverse map from command name → chord display
    /// strings (e.g. `"CSTParent" → ["h"]`). Built on first access by
    /// scanning `bindings.enumerateBindings(...)` across every mode.
    /// Used by the popup to surface chord shortcuts next to each
    /// command. Bindings don't change at runtime, so a single computation
    /// suffices for the controller's lifetime.
    private var chordHintMapCache: [String: [String]]? = nil

    public nonisolated init(
        bindings: VimBindingTree,
        commands: CommandRegistry = VimController.defaultCommands(),
        hintOnsetDelay: Duration = .milliseconds(200)
    ) {
        self.bindings = bindings
        self.commands = commands
        self.hintOnsetDelay = hintOnsetDelay
    }

    public nonisolated convenience init() {
        self.init(
            bindings: VimController.defaultBindings(),
            commands: VimController.defaultCommands()
        )
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

        // `.commandLine` mode consumes every key into the typed input
        // buffer, regardless of pending operators or char args (those
        // were cleared when entering .commandLine via setMode).
        if mode == .commandLine {
            return handleCommandLine(key)
        }

        // Char-argument-pending state takes precedence: the next key is
        // consumed verbatim and dispatched as the synthesized command.
        if let pending = pendingCharArgument {
            pendingCharArgument = nil
            // <Esc> cancels the pending argument silently.
            if key == .special(.escape) {
                return .consumed
            }
            if let cmd = pending.resolve(key) {
                dispatch(cmd)
            }
            return .consumed
        }

        // Operator-pending Esc cancels silently. Any other key flows
        // through normal dispatch — counts still accumulate, chords
        // still resolve — and the interceptor in `dispatch(_:)`
        // post-processes the resolved command.
        if pendingOperator != nil, key == .special(.escape) {
            pendingOperator = nil
            resetPending()
            return .consumed
        }

        switch mode {
        case .normal, .visual, .visualLine, .visualBlock, .visualCST:
            // Visual modes share normal mode's key-handling shape:
            // count digits, then binding-tree resolution. The
            // binding tree itself segregates per-mode bindings, so
            // motions in visual dispatch their own commands and
            // y/d/c only resolve when actually in a visual mode.
            // (.visualCST gets its own binding table; the dispatch
            // shape is identical.)
            return handleNormal(key)
        case .insert:
            return handleInsert(key)
        case .commandLine:
            // Unreachable — handled in the early return above. Defensive.
            return .consumed
        }
    }

    /// Collects characters into ``commandLineInput`` while in
    /// `.commandLine` mode. Drives the completion popup state too:
    /// every input mutation refreshes `commandLineCompletions`;
    /// Down/Up/Tab/Shift-Tab navigate the popup; Enter dispatches the
    /// highlighted entry (with arg-stage advance for commands that
    /// take args). `<Esc>` cancels; `<BS>` deletes the last char (or
    /// cancels if the buffer is empty — vim convention).
    private func handleCommandLine(_ key: VimKey) -> KeyHandled {
        switch key.payload {
        case .special(.escape):
            commandLineInput = ""
            commandLineCompletions = []
            commandLineHighlightedIndex = nil
            setMode(commandLineReturnMode)
        case .special(.returnKey):
            acceptCommandLineEntry()
        case .special(.backspace), .special(.delete):
            if commandLineInput.isEmpty {
                // Vim convention: backspace on empty input cancels.
                commandLineCompletions = []
                commandLineHighlightedIndex = nil
                setMode(commandLineReturnMode)
            } else {
                commandLineInput.removeLast()
                refreshCommandLineCompletions()
            }
        case .special(.space):
            commandLineInput.append(" ")
            refreshCommandLineCompletions()
        case .character(let ch):
            // Reject control-modified chars (Ctrl-C etc.); accept any
            // printable bare character.
            guard !key.modifiers.contains(.control),
                  !key.modifiers.contains(.command)
            else { return .consumed }
            commandLineInput.append(ch)
            refreshCommandLineCompletions()
        case .special(.tab):
            // Shift-Tab moves up, plain Tab moves down — wraps around.
            let delta = key.modifiers.contains(.shift) ? -1 : 1
            moveCommandLineHighlight(by: delta)
        case .special(.up):
            moveCommandLineHighlight(by: -1)
        case .special(.down):
            moveCommandLineHighlight(by: 1)
        case .special(.left), .special(.right):
            // Defer: cursor-within-line editing is v2.
            break
        }
        return .consumed
    }

    /// Accept the currently-highlighted completion (Enter pressed).
    /// Behavior depends on the entry:
    /// - Highlighted command WITH args (e.g. `:CSTFind`): replace the
    ///   buffer with `<name> ` and stay in command-line mode so the
    ///   user picks an arg next. Refreshes completions to show the
    ///   arg options.
    /// - Highlighted command WITHOUT args, OR highlighted arg option:
    ///   replace the buffer with the full dispatchable string,
    ///   dispatch it, and return to the prior mode.
    /// - No highlight (empty input, no matches, or just-arrived in
    ///   arg stage without typing): fall back to dispatching whatever
    ///   was literally typed (which silently no-ops on bogus input).
    private func acceptCommandLineEntry() {
        let returnMode = commandLineReturnMode
        if let entry = highlightedCompletionEntry() {
            let (stage, _) = parseCommandLineStage()
            switch stage {
            case .commandName:
                if entry.isExecutable {
                    commandLineInput = entry.acceptValue
                    finalizeCommandLineDispatch(returnMode: returnMode)
                } else {
                    // Advance to arg stage: append `<name> `, recompute.
                    commandLineInput = entry.acceptValue + " "
                    refreshCommandLineCompletions()
                    // Stay in .commandLine — user types/picks arg next.
                }
            case .arg:
                // Replace the arg portion only (keep `<name> ` prefix).
                if let spaceIdx = commandLineInput.firstIndex(of: " ") {
                    let prefix = commandLineInput[...spaceIdx]
                    commandLineInput = String(prefix) + entry.acceptValue
                }
                finalizeCommandLineDispatch(returnMode: returnMode)
            }
        } else {
            // Fallback: dispatch what was literally typed.
            finalizeCommandLineDispatch(returnMode: returnMode)
        }
    }

    /// Snapshot the buffer, clear state, dispatch via the registry,
    /// then return to `returnMode` if the dispatched command didn't
    /// flip somewhere else. Same care taken as the original .returnKey
    /// handler around the .commandLine → returnMode → newMode race.
    private func finalizeCommandLineDispatch(returnMode: VimMode) {
        let input = commandLineInput
        commandLineInput = ""
        commandLineCompletions = []
        commandLineHighlightedIndex = nil
        dispatchNamedCommandInput(input)
        if mode == .commandLine {
            setMode(returnMode)
        }
    }

    /// Move the popup highlight up or down with wrap-around. From the
    /// "no highlight" state, Down lands on the first entry and Up on
    /// the last.
    private func moveCommandLineHighlight(by delta: Int) {
        guard !commandLineCompletions.isEmpty else { return }
        let n = commandLineCompletions.count
        let current = commandLineHighlightedIndex ?? (delta > 0 ? -1 : n)
        var next = (current + delta) % n
        if next < 0 { next += n }
        commandLineHighlightedIndex = next
    }

    private func highlightedCompletionEntry() -> CompletionEntry? {
        guard let idx = commandLineHighlightedIndex,
              idx >= 0,
              idx < commandLineCompletions.count
        else { return nil }
        return commandLineCompletions[idx]
    }

    // MARK: - Command-line completion

    /// Recompute `commandLineCompletions` and `commandLineHighlightedIndex`
    /// from the current `commandLineInput`. Called on entry to
    /// `.commandLine` and after every input mutation.
    private func refreshCommandLineCompletions() {
        let (stage, query) = parseCommandLineStage()
        let entries: [CompletionEntry]
        switch stage {
        case .commandName:
            entries = buildCommandNameCompletions(query: query)
        case .arg:
            let commandName = commandLineInput
                .split(separator: " ", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? ""
            if let cmd = commands.command(named: commandName),
               case .single(_, let options) = cmd.argSpec {
                entries = buildArgCompletions(query: query, options: options)
            } else {
                entries = []
            }
        }
        commandLineCompletions = entries
        // Highlight the first entry as soon as the user starts typing
        // a query; leave nil on empty query so empty `:` shows the
        // list without committing to a default.
        if entries.isEmpty || query.isEmpty {
            commandLineHighlightedIndex = nil
        } else {
            commandLineHighlightedIndex = 0
        }
    }

    /// Parse the current `commandLineInput` into `(stage, query)` —
    /// determines whether the popup should match command names or
    /// argument options for the leading command.
    private func parseCommandLineStage() -> (stage: CompletionStage, query: String) {
        let input = commandLineInput
        if let spaceIdx = input.firstIndex(of: " ") {
            let commandPart = String(input[..<spaceIdx])
            let argPart = String(input[input.index(after: spaceIdx)...])
            if let cmd = commands.command(named: commandPart),
               case .single(let label, _) = cmd.argSpec {
                return (.arg(label: label), argPart)
            }
            // Either the leading token isn't a command, or it takes no
            // args — fall back to commandName stage (popup will show
            // "no matches" for whatever's typed, which is the truthful
            // signal).
            return (.commandName, input)
        }
        return (.commandName, input)
    }

    private func buildCommandNameCompletions(query: String) -> [CompletionEntry] {
        var results: [(LiminalCommand, MatchResult)] = []
        for cmd in commands.allCommands() {
            if let match = FuzzyMatcher.match(query: query, against: cmd.name) {
                results.append((cmd, match))
            }
        }
        results.sort { a, b in
            if a.1.score != b.1.score { return a.1.score > b.1.score }
            if a.0.name.count != b.0.name.count {
                return a.0.name.count < b.0.name.count
            }
            return a.0.name < b.0.name
        }
        return results.map { cmd, match in
            // matchedIndices are in `cmd.name`; the display string is
            // ":\(cmd.name)" so we shift indices by +1 to keep them
            // aligned for popup highlighting.
            let displayIndices = match.matchedIndices.map { $0 + 1 }
            let isExec: Bool
            switch cmd.argSpec {
            case .none:        isExec = true
            case .single:      isExec = false
            }
            return CompletionEntry(
                display: ":\(cmd.name)",
                acceptValue: cmd.name,
                description: cmd.description,
                chordHint: chordsForCommand(named: cmd.name).first,
                matchedIndices: displayIndices,
                isExecutable: isExec
            )
        }
    }

    private func buildArgCompletions(
        query: String,
        options: [ArgOption]
    ) -> [CompletionEntry] {
        var results: [(ArgOption, MatchResult)] = []
        for opt in options {
            if let match = FuzzyMatcher.match(query: query, against: opt.value) {
                results.append((opt, match))
            }
        }
        results.sort { a, b in
            if a.1.score != b.1.score { return a.1.score > b.1.score }
            if a.0.value.count != b.0.value.count {
                return a.0.value.count < b.0.value.count
            }
            return a.0.value < b.0.value
        }
        return results.map { opt, match in
            CompletionEntry(
                display: opt.value,
                acceptValue: opt.value,
                description: opt.description,
                chordHint: nil,
                matchedIndices: match.matchedIndices,
                isExecutable: true
            )
        }
    }

    /// Chord display strings (e.g. `["h"]`) for `name`. Built lazily
    /// on first call by scanning every mode's bindings for
    /// `.executeNamedCommand(name, _, _)`. Subsequent calls hit the
    /// cache.
    public func chordsForCommand(named name: String) -> [String] {
        if let cached = chordHintMapCache?[name] { return cached }
        if chordHintMapCache == nil {
            chordHintMapCache = computeChordHintMap()
        }
        return chordHintMapCache?[name] ?? []
    }

    private func computeChordHintMap() -> [String: [String]] {
        var map: [String: [String]] = [:]
        let modes: [VimMode] = [
            .normal, .visual, .visualLine, .visualBlock, .visualCST, .insert,
        ]
        for mode in modes {
            for binding in bindings.enumerateBindings(mode: mode) {
                if case .executeNamedCommand(let name, _, _) = binding.command {
                    let display = binding.sequence.map(\.displayString).joined()
                    var existing = map[name] ?? []
                    if !existing.contains(display) {
                        existing.append(display)
                    }
                    map[name] = existing
                }
            }
        }
        for key in map.keys {
            map[key]?.sort { $0.count < $1.count }
        }
        return map
    }

    /// Parse a typed `:` line and dispatch the resolved command. Silent
    /// no-op for empty input or unknown command names — error surfacing
    /// is a planned follow-up.
    private func dispatchNamedCommandInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let name = parts.first else { return }
        let args = Array(parts.dropFirst())
        if let cmd = commands.resolve(name: name, args: args, count: nil) {
            dispatch(cmd)
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
        // Resolve under the current mode so visual modes pick up
        // their own bindings (y/d/c/Esc) and motions registered
        // across all motion-accepting modes still match.
        switch bindings.resolve(tentative, mode: mode, count: pendingCount) {
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
        pendingCharArgument = nil
        pendingOperator = nil
    }

    // MARK: - Derived state

    /// Recompute `statusPresentation` and schedule / replace the hint
    /// snapshot. Called once per `handle(_:)` invocation via `defer`.
    private func refreshDerived() {
        statusPresentation = VimStatusPresentation.make(
            mode: mode,
            pendingKeys: pendingKeys,
            pendingCount: pendingCount,
            pendingCharArgument: pendingCharArgument,
            pendingOperator: pendingOperator,
            commandLineInput: commandLineInput
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
        // Operator-pending interceptor: when an operator is armed, the
        // resolved command is wrapped into an .applyOperator(...) and
        // dispatched as that. Three cases:
        //   1) Same operator key again (`dd` / `cc` / `yy`) → linewise
        //   2) Resolved command maps to an OperatorTarget (a motion) →
        //      operator + motion. Vim's `cw → ce` quirk is applied here.
        //   3) Anything else → silently cancel pending; the original
        //      command is NOT executed (matches vim).
        if let pending = pendingOperator {
            // Doubling check first: enterPendingOperator with the same
            // kind means the user typed the operator twice. The pre-
            // count from the second operator entry (e.g., `2dd`'s
            // second `d`) is multiplied with our existing preCount.
            if case let .enterPendingOperator(kind, postPreCount) = command,
               kind == pending.kind {
                let count = combineCounts(pending.preCount, postPreCount)
                pendingOperator = nil
                resetPending()
                dispatchResolvedOperator(
                    pending.kind, target: .currentLine, count: count
                )
                return
            }
            if let target = operatorTarget(from: command) {
                // Counts for motions are baked into the resolved
                // command by the binding closure (which already
                // consumed pendingCount); extract from the command,
                // then multiply with our pre-operator count.
                let postCount = countFromCommand(command) ?? 1
                let count = combineCounts(pending.preCount, postCount)
                let resolvedTarget = applyChangeWordQuirk(pending.kind, target)
                pendingOperator = nil
                resetPending()
                dispatchResolvedOperator(
                    pending.kind, target: resolvedTarget, count: count
                )
                return
            }
            // Unrecognized continuation: cancel pending, drop the key.
            pendingOperator = nil
            resetPending()
            return
        }
        switch command {
        case .enterInsertMode(let position):
            // Flip mode FIRST so any text inserts the delegate
            // performs land in insert-mode context (cursor styling,
            // `insertText` override checks, etc.). The delegate's
            // `prepareForInsert` then applies any pre-edit (for
            // `o` / `O` / `s` / `S`) and positions the cursor.
            setMode(.insert)
            delegate?.prepareForInsert(at: position)
        case .enterNormalMode:
            // If we were in insert, commit the active insert session
            // BEFORE flipping mode (so the delegate sees mode == .insert
            // and uses the right cursor / pre-edit context).
            if mode == .insert {
                delegate?.commitInsertSession()
            }
            setMode(.normal)
        case .enterVisualMode(let kind):
            // Flip mode FIRST so the Coordinator's visual-mode
            // selection logic (anchor + initial selection) runs in
            // the right context. The delegate seeds the anchor and
            // expands the selection appropriately for the kind.
            switch kind {
            case .charwise:  setMode(.visual)
            case .linewise:  setMode(.visualLine)
            case .blockwise: setMode(.visualBlock)
            }
            delegate?.enterVisualMode(kind: kind)
        case .yankSelection:
            delegate?.yankSelection()
            setMode(.normal)
        case .deleteSelection:
            delegate?.deleteSelection()
            setMode(.normal)
        case .changeSelection:
            // Delete first, then enter insert mode. Mode flip lives
            // here so the delegate's `prepareForInsert` runs in
            // insert context (consistent with the i/a/I/A path).
            delegate?.changeSelection()
            setMode(.insert)
            delegate?.prepareForInsert(at: .atCursor)
        case .paste(let after):
            delegate?.paste(after: after)
        case .pasteCSTSplice(let after):
            delegate?.pasteCSTSplice(after: after)
        case .pasteCSTNest(let after):
            delegate?.pasteCSTNest(after: after)
        case .moveCursor(let motion, let count):
            delegate?.moveCursor(motion: motion, count: count)
        case .structuralMotion(let motion, let count):
            delegate?.structuralMotion(motion, count: count)
        case .viewportMotion(let motion, let count):
            delegate?.viewportMotion(motion, count: count)
        case .displayLineMotion(let motion, let count):
            delegate?.displayLineMotion(motion, count: count)
        case .goToDefinitionAtCursor:
            delegate?.goToDefinitionAtCursor()
        case .toggleTaskAtCursor:
            delegate?.toggleTaskAtCursor()
        case .awaitMarkName(let op):
            pendingCharArgument = (op == .set) ? .setMark : .jumpToMark
        case .setMark(let name):
            delegate?.setMark(name)
        case .jumpToMark(let name):
            delegate?.jumpToMark(name)
        case .enterPendingOperator(let kind, let preCount):
            // Arm the operator. The interceptor at the top of dispatch
            // takes over from here; this case is only reached when the
            // operator is being entered fresh (no existing pending).
            pendingOperator = PendingOperator(kind: kind, preCount: preCount)
        case .applyOperator(let op, let target, let count):
            // Direct operator dispatch (single-key shortcuts: x/X/D/C/Y).
            dispatchResolvedOperator(op, target: target, count: count)
        case .undo(let count):
            delegate?.undo(count: count)
        case .redo(let count):
            delegate?.redo(count: count)
        case .enterCSTVisualMode:
            // Flip mode FIRST so the delegate can publish the new mode
            // before mirroring the forest into the text view.
            setMode(.visualCST)
            delegate?.enterCSTVisualMode()
        case .cstNavigate(let motion, let count):
            delegate?.cstNavigate(motion, count: count)
        case .extendCSTSelection(let motion, let count):
            delegate?.extendCSTSelection(motion, count: count)
        case .swapCSTEnds:
            delegate?.swapCSTEnds()
        case .awaitFindKind(let direction):
            pendingCharArgument = (direction == .forward) ? .findKindForward : .findKindBackward
        case .cstFindKind(let direction, let kind, let count):
            delegate?.cstFindKind(direction: direction, kind: kind, count: count)
        case .enterCommandLine:
            commandLineReturnMode = mode
            setMode(.commandLine)
            commandLineInput = ""
            refreshCommandLineCompletions()
        case .executeNamedCommand(let name, let args, let count):
            if let resolved = commands.resolve(name: name, args: args, count: count) {
                dispatch(resolved)
            }
            // Unknown name or handler nil → silently drop in v1.
        }
    }

    /// Forward an operator+target+count to the delegate. `c` flips into
    /// insert mode after the delete-portion completes (mirroring the
    /// existing visual-mode `changeSelection` flow).
    private func dispatchResolvedOperator(
        _ op: VimOperator,
        target: OperatorTarget,
        count: Int
    ) {
        delegate?.applyOperator(op, target: target, count: count)
        if op == .change {
            setMode(.insert)
            delegate?.prepareForInsert(at: .atCursor)
        }
    }

    /// Map a resolved binding-tree command to an `OperatorTarget`, or
    /// nil if the command isn't a motion the operator can consume.
    private func operatorTarget(from command: VimCommand) -> OperatorTarget? {
        switch command {
        case .moveCursor(let motion, _):
            return .motion(motion)
        case .displayLineMotion(let motion, _):
            return .displayLineMotion(motion)
        case .structuralMotion(let motion, _):
            return .structuralMotion(motion)
        case .viewportMotion(let motion, _):
            return .viewportMotion(motion)
        default:
            return nil
        }
    }

    /// Extract the count baked into a motion command by the binding
    /// closure. Returns nil for non-motion commands.
    private func countFromCommand(_ command: VimCommand) -> Int? {
        switch command {
        case .moveCursor(_, let count),
             .displayLineMotion(_, let count),
             .structuralMotion(_, let count),
             .viewportMotion(_, let count):
            return count
        default:
            return nil
        }
    }

    /// Combine a pre-operator count and a post-operator count (`3d2w`
    /// → 6). The Int.max sentinel that `G` uses for "no explicit
    /// count" passes through unchanged so it doesn't overflow.
    private func combineCounts(_ pre: Int, _ post: Int) -> Int {
        if post == Int.max || pre == Int.max { return Int.max }
        return pre * post
    }

    /// Vim's traditional ergonomic quirk: `cw` behaves like `ce` (and
    /// `cW` like `cE`) — the change operator with a "next word" motion
    /// includes the word's last char and stops there, instead of
    /// devouring the trailing whitespace before the next word. The
    /// substitution happens here so the rest of the pipeline doesn't
    /// have to know about it.
    private func applyChangeWordQuirk(
        _ op: VimOperator, _ target: OperatorTarget
    ) -> OperatorTarget {
        guard op == .change, case .motion(.wordForwardStart) = target else {
            return target
        }
        return .motion(.wordForwardEnd)
    }

    // MARK: - Default bindings

    public nonisolated static func defaultBindings() -> VimBindingTree {
        var t = VimBindingTree()

        // Mode transitions
        t.bind(.normal, [.char("i")], description: "Insert at cursor") { _ in
            .enterInsertMode(at: .atCursor)
        }
        t.bind(.normal, [.char("a")], description: "Append after cursor") { _ in
            .enterInsertMode(at: .afterCursor)
        }
        t.bind(.normal, [.char("I")], description: "Insert at first non-blank") { _ in
            .enterInsertMode(at: .atLineFirstNonBlank)
        }
        t.bind(.normal, [.char("A")], description: "Append at end of line") { _ in
            .enterInsertMode(at: .atLineEnd)
        }
        t.bind(.normal, [.char("o")], description: "Open line below") { _ in
            .enterInsertMode(at: .openLineBelow)
        }
        t.bind(.normal, [.char("O")], description: "Open line above") { _ in
            .enterInsertMode(at: .openLineAbove)
        }
        t.bind(.normal, [.char("s")], description: "Substitute char") { _ in
            .enterInsertMode(at: .substituteChar)
        }
        t.bind(.normal, [.char("S")], description: "Substitute line") { _ in
            .enterInsertMode(at: .substituteLine)
        }
        t.bind(.insert, [.special(.escape)], description: "Back to Normal") { _ in
            .enterNormalMode
        }

        // Visual mode entry from normal. Ctrl-v uses VimKey's
        // modifier-tagged character form.
        t.bind(.normal, [.char("v")], description: "Visual (charwise)") { _ in
            .enterVisualMode(.charwise)
        }
        t.bind(.normal, [.char("V")], description: "Visual line") { _ in
            .enterVisualMode(.linewise)
        }
        t.bind(.normal, [.char("v", modifiers: [.control])],
               description: "Visual block") { _ in
            .enterVisualMode(.blockwise)
        }

        // Esc returns to normal from any visual mode.
        let visualModes: [VimMode] = [.visual, .visualLine, .visualBlock]
        for mode in visualModes {
            t.bind(mode, [.special(.escape)],
                   description: "Back to Normal") { _ in .enterNormalMode }
            t.bind(mode, [.char("y")],
                   description: "Yank selection") { _ in .yankSelection }
            t.bind(mode, [.char("d")],
                   description: "Delete selection") { _ in .deleteSelection }
            t.bind(mode, [.char("c")],
                   description: "Change selection") { _ in .changeSelection }
        }

        // Paste in normal mode.
        t.bind(.normal, [.char("p")],
               description: "Paste after cursor") { _ in .paste(after: true) }
        t.bind(.normal, [.char("P")],
               description: "Paste before cursor") { _ in .paste(after: false) }

        // Operator-pending entries. `d` / `c` / `y` arm the controller's
        // pendingOperator; the dispatch interceptor consumes the next
        // motion (or doubled operator) and routes a single
        // `.applyOperator` to the delegate. The visual-mode bindings
        // for `y` / `d` / `c` (registered earlier) take precedence in
        // visual modes — these here are normal-only.
        t.bind(.normal, [.char("d")], description: "Delete operator") {
            .enterPendingOperator(.delete, preCount: $0 ?? 1)
        }
        t.bind(.normal, [.char("c")], description: "Change operator") {
            .enterPendingOperator(.change, preCount: $0 ?? 1)
        }
        t.bind(.normal, [.char("y")], description: "Yank operator") {
            .enterPendingOperator(.yank, preCount: $0 ?? 1)
        }

        // Single-key edit shortcuts. These dispatch directly through
        // `.applyOperator(...)` without arming the operator-pending
        // state — they're sugar for a fixed (op, target) pair.
        t.bind(.normal, [.char("x")], description: "Delete char at cursor") {
            .applyOperator(.delete, target: .charsAtCursor(before: false), count: $0 ?? 1)
        }
        t.bind(.normal, [.char("X")], description: "Delete char before cursor") {
            .applyOperator(.delete, target: .charsAtCursor(before: true), count: $0 ?? 1)
        }
        t.bind(.normal, [.char("D")], description: "Delete to line end") {
            .applyOperator(.delete, target: .toLineEnd, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("C")], description: "Change to line end") {
            .applyOperator(.change, target: .toLineEnd, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("Y")], description: "Yank line") {
            .applyOperator(.yank, target: .currentLine, count: $0 ?? 1)
        }

        // Motions register across normal + every visual mode. In
        // visual modes the same key sequence extends the selection
        // instead of moving the cursor (the Coordinator's
        // `setCursorAt` chokepoint dispatches on mode). The
        // `motionAccepting` set lives on `VimMode`.
        let motionModes = VimMode.motionAccepting

        // Basic motion — h/j/k/l and arrows are aliases for the same
        // commands; arrow keys also work in Insert mode (they fall through
        // to NSTextView's normal handling since they're unbound there).
        let leftMotion:  @Sendable (Int?) -> VimCommand = { .moveCursor(.left,  count: $0 ?? 1) }
        let rightMotion: @Sendable (Int?) -> VimCommand = { .moveCursor(.right, count: $0 ?? 1) }
        let downMotion:  @Sendable (Int?) -> VimCommand = { .moveCursor(.down,  count: $0 ?? 1) }
        let upMotion:    @Sendable (Int?) -> VimCommand = { .moveCursor(.up,    count: $0 ?? 1) }

        t.bindInModes(motionModes, [.char("h")],       description: "Move left",  command: leftMotion)
        t.bindInModes(motionModes, [.special(.left)],  description: "Move left",  command: leftMotion)
        t.bindInModes(motionModes, [.char("l")],       description: "Move right", command: rightMotion)
        t.bindInModes(motionModes, [.special(.right)], description: "Move right", command: rightMotion)
        t.bindInModes(motionModes, [.char("j")],       description: "Move down",  command: downMotion)
        t.bindInModes(motionModes, [.special(.down)],  description: "Move down",  command: downMotion)
        t.bindInModes(motionModes, [.char("k")],       description: "Move up",    command: upMotion)
        t.bindInModes(motionModes, [.special(.up)],    description: "Move up",    command: upMotion)

        // Line motion (within the current line — count is ignored).
        t.bindInModes(motionModes, [.char("0")], description: "Line start") { _ in
            .moveCursor(.lineStart, count: 1)
        }
        t.bindInModes(motionModes, [.char("^")], description: "First non-blank") { _ in
            .moveCursor(.lineFirstNonBlank, count: 1)
        }
        t.bindInModes(motionModes, [.char("$")], description: "Line end") { _ in
            .moveCursor(.lineEnd, count: 1)
        }

        // Word motion (count = number of words).
        t.bindInModes(motionModes, [.char("w")], description: "Next word") {
            .moveCursor(.wordForwardStart, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("b")], description: "Previous word") {
            .moveCursor(.wordBackward, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("e")], description: "Word end") {
            .moveCursor(.wordForwardEnd, count: $0 ?? 1)
        }

        // Document jumps. `gg` defaults to line 1; `G` defaults to the
        // last line. With an explicit count, both jump to that absolute
        // line. The Int.max sentinel encodes "no count given" for `G`.
        t.bindInModes(motionModes, [.char("g"), .char("g")],
                      description: "First line / line N") {
            .moveCursor(.documentStart, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("G")], description: "Last line / line N") {
            .moveCursor(.documentEnd, count: $0 ?? Int.max)
        }

        // Structural sibling motion
        t.bindInModes(motionModes, [.char("{")], description: "Previous sibling block") {
            .structuralMotion(.previousSibling, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("}")], description: "Next sibling block") {
            .structuralMotion(.nextSibling, count: $0 ?? 1)
        }

        // Screen-relative motion. Vim convention: `H` and `L` accept
        // a count meaning "N lines from top / bottom of viewport";
        // `M` ignores any count.
        t.bindInModes(motionModes, [.char("H")], description: "Top of screen / N from top") {
            .viewportMotion(.screenTop, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("M")], description: "Middle of screen") { _ in
            .viewportMotion(.screenMiddle, count: 1)
        }
        t.bindInModes(motionModes, [.char("L")], description: "Bottom of screen / N from bottom") {
            .viewportMotion(.screenBottom, count: $0 ?? 1)
        }

        // CST-aware "go to" motions under the `g` prefix. These join
        // `gg` / `gj` / `gk` / `g0` / `g^` / `g$` already bound
        // below — `g` is vim's polymorphic "given my cursor, take me
        // somewhere related" namespace. `gh` is a motion (extends in
        // visual); `gd` is an action (normal-only — there's no
        // "extend to a navigated link" semantic).
        t.bindInModes(motionModes, [.char("g"), .char("h")],
                      description: "Enclosing heading") {
            .structuralMotion(.enclosingHeading, count: $0 ?? 1)
        }
        t.bind(.normal, [.char("g"), .char("d")],
               description: "Follow reference at cursor (incl. URLs)") { _ in
            .goToDefinitionAtCursor
        }

        // Bracket-prefix sequential navigation: `[<x>` / `]<x>` walk
        // previous/next of category X. Counts repeat. Letters chosen
        // to avoid widely-deployed plugin bindings (vim-unimpaired,
        // gitsigns, treesitter-textobjects, LSP). Reservations:
        //   `[d` / `]d` — LSP-canonical for diagnostics. Bind when
        //                 schema validation surfaces in the UI.
        //   `[z` / `]z` — vim-canonical for fold start/end. Bind
        //                 when CST folding lands.
        // Don't claim those letters for anything else.
        t.bindInModes(motionModes, [.char("["), .char("[")],
                      description: "Previous heading") {
            .structuralMotion(.previousHeading, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("]"), .char("]")],
                      description: "Next heading") {
            .structuralMotion(.nextHeading, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("["), .char("r")],
                      description: "Previous reference") {
            .structuralMotion(.previousReference, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("]"), .char("r")],
                      description: "Next reference") {
            .structuralMotion(.nextReference, count: $0 ?? 1)
        }

        // Display-line ("visual") motion. Like j/k/0/^/$ but
        // operating on soft-wrapped display rows instead of logical
        // source lines. The chord-prefix machinery already accepts
        // `g` because `gg` is bound below.
        t.bindInModes(motionModes, [.char("g"), .char("j")],
                      description: "Down one display line") {
            .displayLineMotion(.down, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("g"), .char("k")],
                      description: "Up one display line") {
            .displayLineMotion(.up, count: $0 ?? 1)
        }
        t.bindInModes(motionModes, [.char("g"), .char("0")],
                      description: "Display line start") { _ in
            .displayLineMotion(.start, count: 1)
        }
        t.bindInModes(motionModes, [.char("g"), .char("^")],
                      description: "Display line first non-blank") { _ in
            .displayLineMotion(.firstNonBlank, count: 1)
        }
        t.bindInModes(motionModes, [.char("g"), .char("$")],
                      description: "Display line end") { _ in
            .displayLineMotion(.end, count: 1)
        }

        // Marks. `m<a-z>` sets a mark; `` `<a-z> `` jumps to it. Both
        // commands arm `pendingCharArgument` so the next key is read
        // as the mark name rather than the start of another chord.
        t.bind(.normal, [.char("m")], description: "Set mark a-z") { _ in
            .awaitMarkName(.set)
        }
        t.bind(.normal, [.char("`")], description: "Jump to mark a-z") { _ in
            .awaitMarkName(.jump)
        }

        // Leader chord — CST-aware commands route through the registry.
        // The chord is a shortcut to a `:`-mode command name; the canonical
        // implementation lives in `defaultCommands()`.
        t.bind(.normal, [.special(.space), .char("t")],
               description: "Toggle task checkbox") { _ in
            .executeNamedCommand(name: "ToggleTask", args: [], count: nil)
        }
        t.bind(.normal, [.special(.space), .char("p")],
               description: "Splice CST paste") { _ in
            .executeNamedCommand(name: "CSTPasteSplice", args: [], count: nil)
        }
        t.bind(.normal, [.special(.space), .char("n")],
               description: "Nest CST paste") { _ in
            .executeNamedCommand(name: "CSTPasteNest", args: [], count: nil)
        }

        // CST-aware undo / redo. Routed to the delegate, which walks
        // the document-owned transaction history. Counts loop the call.
        t.bind(.normal, [.char("u")], description: "Undo") {
            .undo(count: $0 ?? 1)
        }
        t.bind(.normal, [.char("r", modifiers: [.control])],
               description: "Redo") {
            .redo(count: $0 ?? 1)
        }

        // Visual CST mode. Entry chord (gC) intentionally avoids the
        // `motionAccepting` list so structural motions (h/l/j/k below)
        // can be rebound under `.visualCST` without colliding with the
        // text-cursor motions used in normal/visual/visualLine/
        // visualBlock. The chord dispatches `:CSTEnter` through the
        // command registry — same code path as typing `:CSTEnter<CR>`.
        t.bind(.normal, [.char("g"), .char("C")],
               description: "Visual CST") { _ in
            .executeNamedCommand(name: "CSTEnter", args: [], count: nil)
        }

        // Esc and operators in visualCST reuse the same dispatch as
        // text-visual modes; the Coordinator's snapshotVisualSelection
        // branches on .visualCST to source the byte range from the
        // active LiminalForest.
        t.bind(.visualCST, [.special(.escape)],
               description: "Back to Normal") { _ in .enterNormalMode }
        t.bind(.visualCST, [.char("y")],
               description: "Yank selection") { _ in .yankSelection }
        t.bind(.visualCST, [.char("d")],
               description: "Delete selection") { _ in .deleteSelection }
        t.bind(.visualCST, [.char("c")],
               description: "Change selection") { _ in .changeSelection }

        // CST navigation. Each chord is bound *only* under .visualCST so
        // it doesn't shadow normal-mode motions. Slides collapse the
        // selection to a singleton; extends move only the head. The
        // chord-to-command-name layer routes through the registry —
        // canonical implementations live in `defaultCommands()`.
        t.bind(.visualCST, [.char("h")],
               description: "Parent") { _ in
            .executeNamedCommand(name: "CSTParent", args: [], count: nil)
        }
        t.bind(.visualCST, [.char("l")],
               description: "First child") { _ in
            .executeNamedCommand(name: "CSTFirstChild", args: [], count: nil)
        }
        t.bind(.visualCST, [.char("j")],
               description: "Next sibling") {
            .executeNamedCommand(name: "CSTNextSibling", args: [], count: $0)
        }
        t.bind(.visualCST, [.char("k")],
               description: "Previous sibling") {
            .executeNamedCommand(name: "CSTPreviousSibling", args: [], count: $0)
        }
        t.bind(.visualCST, [.char("J")],
               description: "Extend forward") {
            .executeNamedCommand(name: "CSTExtendForward", args: [], count: $0)
        }
        t.bind(.visualCST, [.char("K")],
               description: "Extend backward") {
            .executeNamedCommand(name: "CSTExtendBackward", args: [], count: $0)
        }
        t.bind(.visualCST, [.char("o")],
               description: "Swap ends") { _ in
            .executeNamedCommand(name: "CSTSwapEnds", args: [], count: nil)
        }

        // Typed descent within the current subtree. `f<letter>` finds
        // the first match in source order; `F<letter>` finds the last.
        // The letter argument is consumed via `pendingCharArgument` —
        // see `TypedDescentKind(letter:)` for the mapping.
        t.bind(.visualCST, [.char("f")],
               description: "Find kind in subtree") { _ in
            .awaitFindKind(direction: .forward)
        }
        t.bind(.visualCST, [.char("F")],
               description: "Find last kind in subtree") { _ in
            .awaitFindKind(direction: .backward)
        }

        // `:` enters command-line mode from every "normal-like" mode
        // (including visual variants so the user can dispatch a `:`
        // command without losing the current selection).
        let commandLineEntryModes: [VimMode] = [
            .normal, .visual, .visualLine, .visualBlock, .visualCST,
        ]
        for entryMode in commandLineEntryModes {
            t.bind(entryMode, [.char(":")],
                   description: "Command line") { _ in .enterCommandLine }
        }

        return t
    }

    // MARK: - Default commands

    /// Registers every CST-aware command behind the chord shortcuts.
    /// Adding a new `:` command means adding a `register(...)` block
    /// here — chord wiring is optional and orthogonal.
    public nonisolated static func defaultCommands() -> CommandRegistry {
        let registry = CommandRegistry()

        registry.register(.init(
            name: "CSTEnter",
            description: "Enter visual CST mode at cursor"
        ) { _, _ in .enterCSTVisualMode })

        registry.register(.init(
            name: "CSTParent",
            description: "Ascend to parent forest (glue-skipped)"
        ) { _, count in .cstNavigate(.parent, count: count ?? 1) })

        registry.register(.init(
            name: "CSTFirstChild",
            description: "Descend to first navigable child (glue-skipped)"
        ) { _, count in .cstNavigate(.firstChild, count: count ?? 1) })

        registry.register(.init(
            name: "CSTNextSibling",
            description: "Slide forest to next sibling"
        ) { _, count in .cstNavigate(.nextSibling, count: count ?? 1) })

        registry.register(.init(
            name: "CSTPreviousSibling",
            description: "Slide forest to previous sibling"
        ) { _, count in .cstNavigate(.previousSibling, count: count ?? 1) })

        registry.register(.init(
            name: "CSTExtendForward",
            description: "Extend forest head to next sibling"
        ) { _, count in .extendCSTSelection(.nextSibling, count: count ?? 1) })

        registry.register(.init(
            name: "CSTExtendBackward",
            description: "Extend forest head to previous sibling"
        ) { _, count in .extendCSTSelection(.previousSibling, count: count ?? 1) })

        registry.register(.init(
            name: "CSTSwapEnds",
            description: "Swap forest anchor and head endpoints"
        ) { _, _ in .swapCSTEnds })

        let kindArgSpec = ArgSpec.single(
            label: "kind",
            options: TypedDescentKind.argOptions
        )

        registry.register(.init(
            name: "CSTFind",
            description: "Find first node of given kind in current subtree",
            argSpec: kindArgSpec
        ) { args, count in
            guard let arg = args.first,
                  let kind = TypedDescentKind(commandArgument: arg)
            else { return nil }
            return .cstFindKind(direction: .forward, kind: kind, count: count ?? 1)
        })

        registry.register(.init(
            name: "CSTFindLast",
            description: "Find last node of given kind in current subtree",
            argSpec: kindArgSpec
        ) { args, count in
            guard let arg = args.first,
                  let kind = TypedDescentKind(commandArgument: arg)
            else { return nil }
            return .cstFindKind(direction: .backward, kind: kind, count: count ?? 1)
        })

        registry.register(.init(
            name: "CSTPasteSplice",
            description: "Splice CST clipboard payload after cursor"
        ) { _, _ in .pasteCSTSplice(after: true) })

        registry.register(.init(
            name: "CSTPasteNest",
            description: "Nest CST clipboard payload after cursor"
        ) { _, _ in .pasteCSTNest(after: true) })

        registry.register(.init(
            name: "ToggleTask",
            description: "Toggle the task checkbox at the cursor"
        ) { _, _ in .toggleTaskAtCursor })

        return registry
    }

    // MARK: - Mark registry plumbing

    /// Register a CST-anchored mark. Called by the coordinator after
    /// the controller dispatches `.setMark(name)` (the coordinator owns
    /// the cursor offset → anchor mapping).
    public func setMark(_ name: Character, anchor: CSTAnchor) {
        marks.set(name, anchor: anchor)
    }

    /// Called by the document after each tree-mutating edit. Forwards
    /// to the registry so all marks track the latest tree.
    public func reanchorMarks(
        oldRoot: RootSyntax,
        edits: [TextEdit],
        newRoot: RootSyntax
    ) {
        marks.reanchor(oldRoot: oldRoot, edits: edits, newRoot: newRoot)
    }

    /// Replace the entire mark store with a snapshot. Used by undo /
    /// redo: the snapshot's marks point into the snapshot's tree (which
    /// is being reinstalled at the same time), so they're valid by
    /// construction — no re-anchoring needed.
    public func restoreMarks(_ marks: MarkRegistry) {
        self.marks = marks
    }

    /// Force normal mode without dispatching `.enterNormalMode`
    /// (which would invoke the insert-session commit hook). Used by
    /// the undo/redo install path to land in a predictable mode after
    /// an arbitrary snapshot is restored, and by the Coordinator's
    /// `enterCSTVisualMode` when no navigable forest covers the
    /// cursor (the controller has already flipped to `.visualCST`
    /// optimistically and we need to undo that without firing a
    /// re-entry into normal-mode side effects).
    public func forceNormalMode() {
        setMode(.normal)
    }
}

/// State held while an operator (`d` / `c` / `y`) is waiting for its
/// target. The next motion command resolves into an `.applyOperator`;
/// the same operator typed again resolves into the linewise variant.
/// `Esc` or any unrelated command silently cancels.
public struct PendingOperator: Sendable, Equatable, Hashable {
    public let kind: VimOperator
    public let preCount: Int

    public init(kind: VimOperator, preCount: Int = 1) {
        self.kind = kind
        self.preCount = preCount
    }
}

/// What kind of character argument the controller is currently waiting
/// for. Synthesized from the previous command's dispatch (e.g.
/// `.awaitMarkName(.set)` arms `.setMark`). Consumed by the next
/// keypress in `handle(_:)`.
public enum PendingCharArgument: Sendable, Equatable {
    case setMark
    case jumpToMark
    /// `.visualCST` `f<letter>` — typed descent forward in subtree.
    case findKindForward
    /// `.visualCST` `F<letter>` — typed descent backward in subtree.
    case findKindBackward

    /// Human-readable prefix label shown in the status bar (e.g. "m"
    /// when waiting for the mark name after `m`).
    public var statusLabel: String {
        switch self {
        case .setMark:          return "m"
        case .jumpToMark:       return "`"
        case .findKindForward:  return "f"
        case .findKindBackward: return "F"
        }
    }

    /// Map the user's next keypress to the final command. Returns nil
    /// for keypresses that aren't a valid argument (modifier-laden,
    /// special, or non-letter); the controller silently drops these
    /// rather than dispatching nonsense.
    func resolve(_ key: VimKey) -> VimCommand? {
        guard case .character(let ch) = key.payload,
              key.modifiers.isEmpty
        else { return nil }
        switch self {
        case .setMark:
            return MarkRegistry.isValidMarkName(ch) ? .setMark(ch) : nil
        case .jumpToMark:
            return MarkRegistry.isValidMarkName(ch) ? .jumpToMark(ch) : nil
        case .findKindForward:
            return TypedDescentKind(letter: ch).map { kind in
                .executeNamedCommand(
                    name: "CSTFind",
                    args: [kind.commandArgument],
                    count: nil
                )
            }
        case .findKindBackward:
            return TypedDescentKind(letter: ch).map { kind in
                .executeNamedCommand(
                    name: "CSTFindLast",
                    args: [kind.commandArgument],
                    count: nil
                )
            }
        }
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
    func viewportMotion(_ motion: ViewportMotion, count: Int)
    func displayLineMotion(_ motion: DisplayLineMotion, count: Int)
    func goToDefinitionAtCursor()
    /// Apply the position-specific work (cursor move, optional
    /// pre-edit) for the variant of `enterInsertMode` that just
    /// fired. The controller has already flipped to insert mode by
    /// the time this is called.
    func prepareForInsert(at position: InsertPosition)
    /// Seed the visual-mode anchor and expand the selection
    /// appropriately for `kind`. The controller has already flipped
    /// to the corresponding visual mode by the time this is called.
    func enterVisualMode(kind: VisualKind)
    /// Copy the current visual selection to the system pasteboard.
    /// Caller (controller) is responsible for the mode transition
    /// back to normal afterwards.
    func yankSelection()
    /// Yank then delete the current visual selection. Cursor lands
    /// at the start of the previous selection.
    func deleteSelection()
    /// Yank then delete the current visual selection as the opening
    /// edit of an insert-session transaction.
    func changeSelection()
    /// Paste from the system pasteboard. `after` is `true` for `p`
    /// (after cursor / below line) and `false` for `P`.
    func paste(after: Bool)
    /// Explicit target-intent paste for splicing compatible CST payloads
    /// into a strict child-sequence target.
    func pasteCSTSplice(after: Bool)
    /// Explicit target-intent paste for nesting compatible CST payloads
    /// inside a strict container target.
    func pasteCSTNest(after: Bool)
    /// Materialize and apply an operator over the indicated target.
    /// The delegate is responsible for: resolving the affected text
    /// range from `target` (using the current cursor position),
    /// writing the affected text to the system pasteboard, applying
    /// the edit (if `op` is `.delete` or `.change`), and positioning
    /// the cursor at the start of the operated range. The controller
    /// flips into insert mode after this returns when `op == .change`,
    /// so the delegate doesn't need to itself.
    func applyOperator(
        _ op: VimOperator,
        target: OperatorTarget,
        count: Int
    )
    /// Walk back `count` snapshots in the document's CST-aware undo
    /// history and install the resulting state.
    func undo(count: Int)
    /// Walk forward `count` snapshots and install the resulting state.
    func redo(count: Int)
    /// Esc out of insert mode: commit the active insert session as a
    /// single transaction in the undo history. Called BEFORE the
    /// controller flips mode back to `.normal`.
    func commitInsertSession()
    func toggleTaskAtCursor()
    func setMark(_ name: Character)
    func jumpToMark(_ name: Character)
    /// Build a ``LiminalForest`` at the cursor's current byte offset
    /// and mirror it into the text view. Called after the controller
    /// has flipped to ``VimMode/visualCST``. If no navigable forest
    /// covers the cursor, the delegate should call
    /// ``VimController/forceNormalMode()`` to abort the entry.
    func enterCSTVisualMode()
    /// Slide the forest selection in `motion`'s direction `count`
    /// times. Each step collapses the selection to a singleton.
    func cstNavigate(_ motion: CSTMotion, count: Int)
    /// Extend the forest's head endpoint in `motion`'s direction
    /// `count` times. The anchor stays fixed. Only meaningful for
    /// `.nextSibling` / `.previousSibling`.
    func extendCSTSelection(_ motion: CSTMotion, count: Int)
    /// Swap the forest's anchor and head endpoints (vim's `o`).
    func swapCSTEnds()
    /// Search the current forest's subtree for a forest matching
    /// `kind`. Forward returns the first match in preorder; backward
    /// returns the last. Backs `f<letter>` / `F<letter>`.
    func cstFindKind(direction: FindDirection, kind: TypedDescentKind, count: Int)
}

extension VimControllerDelegate {
    /// Default no-op so existing test spies / partial conformers
    /// don't have to implement this immediately. Production
    /// conformers (the document) MUST override.
    public func applyOperator(
        _ op: VimOperator,
        target: OperatorTarget,
        count: Int
    ) {}
    public func undo(count: Int) {}
    public func redo(count: Int) {}
    public func commitInsertSession() {}
    public func changeSelection() { deleteSelection() }
    public func pasteCSTSplice(after: Bool) {}
    public func pasteCSTNest(after: Bool) {}
    // CST visual mode default no-ops — production Coordinator
    // overrides; spy delegates in tests inherit the no-op.
    public func enterCSTVisualMode() {}
    public func cstNavigate(_ motion: CSTMotion, count: Int) {}
    public func extendCSTSelection(_ motion: CSTMotion, count: Int) {}
    public func swapCSTEnds() {}
    public func cstFindKind(
        direction: FindDirection,
        kind: TypedDescentKind,
        count: Int
    ) {}
}
