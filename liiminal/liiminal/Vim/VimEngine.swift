import Foundation

enum VimHandleResult: Equatable {
    case handled(VimCommand)
    case pending
    case ignored
}

final class VimEngine {
    private let keymapCatalog: VimKeymapCatalog
    private let commandBindings: VimBindingTree
    private let visualBindings: VimBindingTree
    private let operatorArgumentBindings: [VimOperator: VimOperatorArgumentBindingTree]

    private(set) var sessionState: VimSessionState

    init(
        keymapCatalog: VimKeymapCatalog = .normalMode,
        visualBindings: VimBindingTree = .visualMode,
        initialState: VimSessionState = VimSessionState()
    ) {
        self.keymapCatalog = keymapCatalog
        self.commandBindings = keymapCatalog.commandBindings
        self.visualBindings = visualBindings
        self.operatorArgumentBindings = keymapCatalog.operatorArgumentBindings
        self.sessionState = initialState
    }

    func hintCandidate(in context: VimHintContext = .empty) -> VimHintCandidate? {
        keymapCatalog.hintCandidate(for: sessionState, in: context)
    }

    func rootHintCandidate(in context: VimHintContext = .empty) -> VimHintCandidate {
        keymapCatalog.rootHintCandidate(in: context)
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
                    argument: .characterwiseMotion(motion)
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
        if let characterArgumentFactory = sessionState.pendingCharacterOperatorArgumentFactory {
            guard case .character(let character) = keyPress else {
                clearPendingInput()
                return .ignored
            }

            let operatorCount = sessionState.pendingOperatorCount
            let argumentCount = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolvePendingOperator(
                pendingOperator,
                argument: characterArgumentFactory(character, argumentCount).applying(
                    operatorCount: operatorCount)
            )
        }

        if consumeCountDigitIfNeeded(keyPress) {
            return .pending
        }

        guard let operatorBindings = operatorArgumentBindings[pendingOperator] else {
            sessionState.clearPendingInput()
            return .ignored
        }

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch operatorBindings.match(candidateKeys) {
        case .exact(let argumentFactory):
            let operatorCount = sessionState.pendingOperatorCount
            let argumentCount = sessionState.pendingCount
            sessionState.clearPendingInput()
            return resolvePendingOperator(
                pendingOperator,
                argument: argumentFactory(argumentCount).applying(operatorCount: operatorCount)
            )
        case .characterPending(let characterArgumentFactory):
            sessionState.pendingKeys = candidateKeys
            sessionState.pendingCharacterOperatorArgumentFactory = characterArgumentFactory
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
        case .setMark:
            return .handled(command)
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
        _ target: VimOperatorArgument,
        commandBuilder: (VimOperatorArgument) -> VimCommand
    ) -> VimHandleResult {
        switch target {
        case .motion(let argument) where argument.granularity == .characterwise:
            switch argument.motion {
            case .characterSearch(let search):
                sessionState.lastCharacterSearch = search
                return .handled(
                    commandBuilder(
                        .motion(
                            VimMotionArgument(
                                motion: .characterSearch(search),
                                granularity: .characterwise,
                                count: argument.count
                            )
                        )
                    )
                )
            case .repeatCharacterSearch(let oppositeDirection):
                guard let lastCharacterSearch = sessionState.lastCharacterSearch else {
                    return .ignored
                }

                let search = oppositeDirection
                    ? lastCharacterSearch.reversed()
                    : lastCharacterSearch

                return .handled(
                    commandBuilder(
                        .motion(
                            VimMotionArgument(
                                motion: .characterSearch(search),
                                granularity: .characterwise,
                                count: argument.count
                            )
                        )
                    )
                )
            default:
                return .handled(commandBuilder(target))
            }
        default:
            return .handled(commandBuilder(target))
        }
    }

    private func resolvePendingOperator(
        _ op: VimOperator,
        argument: VimOperatorArgument
    ) -> VimHandleResult {
        switch op {
        case .delete:
            return resolve(.delete(argument))
        case .change:
            return resolve(.change(argument))
        case .yank:
            return resolve(.yank(argument))
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
