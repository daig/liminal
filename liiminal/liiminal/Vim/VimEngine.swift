import Foundation

enum VimHandleResult {
    case handled(VimCommand)
    case pending
    case ignored
}

final class VimEngine {
    private let keymapCatalog: VimKeymapCatalog
    private let commandBindings: VimBindingTree
    private let visualBindings: VimBindingTree
    private let operatorMotionBindings: [VimOperator: VimOperatorMotionBindingTree]

    private(set) var sessionState: VimSessionState

    init(
        keymapCatalog: VimKeymapCatalog = .normalMode,
        visualBindings: VimBindingTree = .visualMode,
        initialState: VimSessionState = VimSessionState()
    ) {
        self.keymapCatalog = keymapCatalog
        self.commandBindings = keymapCatalog.commandBindings
        self.visualBindings = visualBindings
        self.operatorMotionBindings = keymapCatalog.operatorMotionBindings
        self.sessionState = initialState
    }

    var hintCandidate: VimHintCandidate? {
        keymapCatalog.hintCandidate(for: sessionState)
    }

    func rootHintCandidate() -> VimHintCandidate {
        keymapCatalog.rootHintCandidate()
    }

    func setMode(_ mode: VimMode) {
        sessionState.mode = mode

        if mode != .normal {
            sessionState.clearPendingInput()
            sessionState.preferredColumn = nil
        }
    }

    func reset() {
        sessionState = VimSessionState()
    }

    func clearPendingInput() {
        sessionState.clearPendingInput()
    }

    func handleTargetPosition(_ position: Int) -> VimHandleResult {
        let motion = VimTextMotion.targetPosition(position)

        switch sessionState.mode {
        case .normal:
            if let pendingOperator = sessionState.pendingOperator {
                sessionState.clearPendingInput()
                return resolvePendingOperator(
                    pendingOperator,
                    motion: .characterwise(motion),
                    operatorCount: nil,
                    motionCount: nil
                )
            }

            sessionState.clearPendingInput()
            return resolve(.moveText(motion, count: nil))
        case .visual, .visualLine:
            sessionState.clearPendingInput()
            return resolve(.moveText(motion, count: nil))
        case .insert:
            return .ignored
        }
    }

    func setPreferredColumn(_ preferredColumn: Int?) {
        sessionState.preferredColumn = preferredColumn
    }

    func handle(_ keyPress: VimKeyPress) -> VimHandleResult {
        switch sessionState.mode {
        case .normal:
            handleNormalMode(keyPress)
        case .insert:
            .ignored
        case .visual, .visualLine:
            handleVisualMode(keyPress)
        }
    }

    private func handleNormalMode(_ keyPress: VimKeyPress) -> VimHandleResult {
        if keyPress == .special(.escape) {
            clearPendingInput()
            return .ignored
        }

        if let pendingOperator = sessionState.pendingOperator {
            return handlePendingOperator(keyPress, pendingOperator: pendingOperator)
        }

        if let characterCommandFactory = sessionState.pendingCharacterCommandFactory {
            guard case .character(let character) = keyPress else {
                clearPendingInput()
                return .ignored
            }

            let count = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolve(characterCommandFactory(character, count))
        }

        if consumeCountDigitIfNeeded(keyPress) {
            return .pending
        }

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch commandBindings.match(candidateKeys) {
        case .exact(let commandFactory):
            let count = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolve(commandFactory(count))
        case .characterPending(let characterCommandFactory):
            sessionState.pendingKeys = candidateKeys
            sessionState.pendingCharacterCommandFactory = characterCommandFactory
            return .pending
        case .partial:
            sessionState.pendingKeys = candidateKeys
            return .pending
        case .none:
            sessionState.clearPendingInput()
            return .ignored
        }
    }

    private func handlePendingOperator(
        _ keyPress: VimKeyPress,
        pendingOperator: VimOperator
    ) -> VimHandleResult {
        if let characterMotionFactory = sessionState.pendingCharacterOperatorMotionFactory {
            guard case .character(let character) = keyPress else {
                clearPendingInput()
                return .ignored
            }

            let operatorCount = sessionState.pendingOperatorCount
            let motionCount = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolvePendingOperator(
                pendingOperator,
                motion: characterMotionFactory(character, motionCount),
                operatorCount: operatorCount,
                motionCount: motionCount
            )
        }

        if consumeCountDigitIfNeeded(keyPress) {
            return .pending
        }

        guard let operatorBindings = operatorMotionBindings[pendingOperator] else {
            sessionState.clearPendingInput()
            return .ignored
        }

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch operatorBindings.match(candidateKeys) {
        case .exact(let motionFactory):
            let operatorCount = sessionState.pendingOperatorCount
            let motionCount = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolvePendingOperator(
                pendingOperator,
                motion: motionFactory(motionCount),
                operatorCount: operatorCount,
                motionCount: motionCount
            )
        case .characterPending(let characterMotionFactory):
            sessionState.pendingKeys = candidateKeys
            sessionState.pendingCharacterOperatorMotionFactory = characterMotionFactory
            return .pending
        case .partial:
            sessionState.pendingKeys = candidateKeys
            return .pending
        case .none:
            sessionState.clearPendingInput()
            return .ignored
        }
    }

    private func handleVisualMode(_ keyPress: VimKeyPress) -> VimHandleResult {
        if keyPress == .special(.escape) {
            clearPendingInput()
            return .handled(.exitVisual)
        }

        switch keyPress {
        case .character("v"):
            clearPendingInput()
            return sessionState.mode == .visualLine
                ? .handled(.enterVisual(.characterwise))
                : .handled(.exitVisual)
        case .character("V"):
            clearPendingInput()
            return sessionState.mode == .visual
                ? .handled(.enterVisual(.linewise))
                : .handled(.exitVisual)
        case .character("d"), .character("x"):
            clearPendingInput()
            return .handled(.deleteSelection)
        case .character("c"), .character("s"):
            clearPendingInput()
            return .handled(.changeSelection)
        case .character("y"):
            clearPendingInput()
            return .handled(.yankSelection)
        case .character("p"), .character("P"):
            let count = sessionState.pendingCount
            clearPendingInput()
            return .handled(.replaceSelectionWithPaste(count: count))
        default:
            break
        }

        if let characterCommandFactory = sessionState.pendingCharacterCommandFactory {
            guard case .character(let character) = keyPress else {
                clearPendingInput()
                return .ignored
            }

            let count = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolve(characterCommandFactory(character, count))
        }

        if consumeCountDigitIfNeeded(keyPress) {
            return .pending
        }

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch visualBindings.match(candidateKeys) {
        case .exact(let commandFactory):
            let count = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolve(commandFactory(count))
        case .characterPending(let characterCommandFactory):
            sessionState.pendingKeys = candidateKeys
            sessionState.pendingCharacterCommandFactory = characterCommandFactory
            return .pending
        case .partial:
            sessionState.pendingKeys = candidateKeys
            return .pending
        case .none:
            sessionState.clearPendingInput()
            return .ignored
        }
    }

    private func resolve(_ command: VimCommand) -> VimHandleResult {
        switch command {
        case .beginOperator(let op, let count):
            sessionState.pendingOperator = op
            sessionState.pendingOperatorCount = count
            return .pending
        case .enterVisual(let kind):
            setMode(kind.mode)
            return .handled(command)
        case .exitVisual, .scrollCursorLine, .deleteSelection, .changeSelection, .yankSelection,
            .replaceSelectionWithPaste:
            return .handled(command)
        case .enterInsert:
            setMode(.insert)
            return .handled(command)
        case .moveText(.characterSearch(let search), _):
            sessionState.lastCharacterSearch = search
            return .handled(command)
        case .moveText(.repeatCharacterSearch(let oppositeDirection), let count):
            guard let lastCharacterSearch = sessionState.lastCharacterSearch else {
                return .ignored
            }

            let search = oppositeDirection
                ? lastCharacterSearch.reversed()
                : lastCharacterSearch

            return .handled(.moveText(.characterSearch(search), count: count))
        case .delete(let target):
            return resolveOperatorCharacterSearch(
                target,
                commandBuilder: VimCommand.delete
            )
        case .change(let target):
            return resolveOperatorCharacterSearch(
                target,
                commandBuilder: VimCommand.change
            )
        case .yank(let target):
            return resolveOperatorCharacterSearch(
                target,
                commandBuilder: VimCommand.yank
            )
        case .moveText, .moveLayout, .paste, .undo, .redo:
            return .handled(command)
        }
    }

    private func resolveOperatorCharacterSearch(
        _ target: VimOperatorTarget,
        commandBuilder: (VimOperatorTarget) -> VimCommand
    ) -> VimHandleResult {
        switch target {
        case .characterwise(.characterSearch(let search), let count):
            sessionState.lastCharacterSearch = search
            return .handled(commandBuilder(.characterwise(.characterSearch(search), count: count)))
        case .characterwise(.repeatCharacterSearch(let oppositeDirection), let count):
            guard let lastCharacterSearch = sessionState.lastCharacterSearch else {
                return .ignored
            }

            let search = oppositeDirection
                ? lastCharacterSearch.reversed()
                : lastCharacterSearch

            return .handled(commandBuilder(.characterwise(.characterSearch(search), count: count)))
        default:
            return .handled(commandBuilder(target))
        }
    }

    private func resolvePendingOperator(
        _ op: VimOperator,
        motion: VimOperatorMotion,
        operatorCount: Int?,
        motionCount: Int?
    ) -> VimHandleResult {
        let effectiveCount = effectiveCount(
            for: motion,
            operatorCount: operatorCount,
            motionCount: motionCount
        )

        switch op {
        case .delete:
            switch motion {
            case .currentLines:
                return resolve(.delete(.currentLines(count: effectiveCount)))
            case .characterwise(let textMotion):
                return resolve(.delete(.characterwise(textMotion, count: effectiveCount)))
            case .linewise(let textMotion):
                return resolve(.delete(.linewise(textMotion, count: effectiveCount)))
            }
        case .change:
            switch motion {
            case .currentLines:
                return resolve(.change(.currentLines(count: effectiveCount)))
            case .characterwise(let textMotion):
                return resolve(.change(.characterwise(textMotion, count: effectiveCount)))
            case .linewise(let textMotion):
                return resolve(.change(.linewise(textMotion, count: effectiveCount)))
            }
        case .yank:
            switch motion {
            case .currentLines:
                return resolve(.yank(.currentLines(count: effectiveCount)))
            case .characterwise(let textMotion):
                return resolve(.yank(.characterwise(textMotion, count: effectiveCount)))
            case .linewise(let textMotion):
                return resolve(.yank(.linewise(textMotion, count: effectiveCount)))
            }
        }
    }

    private func effectiveCount(
        for motion: VimOperatorMotion,
        operatorCount: Int?,
        motionCount: Int?
    ) -> Int? {
        switch motion {
        case .currentLines:
            return combinedRelativeCount(operatorCount, motionCount)
        case .characterwise(let textMotion), .linewise(let textMotion):
            switch textMotion {
            case .goToLine:
                return motionCount ?? operatorCount
            default:
                return combinedRelativeCount(operatorCount, motionCount)
            }
        }
    }

    private func combinedRelativeCount(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (let lhs?, nil):
            return lhs
        case (nil, let rhs?):
            return rhs
        case (let lhs?, let rhs?):
            return lhs * rhs
        }
    }

    private func consumeCountDigitIfNeeded(_ keyPress: VimKeyPress) -> Bool {
        guard sessionState.pendingKeys.isEmpty else { return false }
        guard case .character(let character) = keyPress else { return false }
        guard character.isASCII, character.isNumber else { return false }

        if character == "0" && sessionState.pendingCount == nil {
            return false
        }

        guard let digit = character.wholeNumberValue else { return false }
        sessionState.pendingCount = ((sessionState.pendingCount ?? 0) * 10) + digit
        return true
    }
}
