import Foundation

enum VimHandleResult {
    case handled(VimCommand)
    case pending
    case ignored
}

final class VimEngine {
    private let commandBindings: VimBindingTree
    private let operatorMotionBindings: VimOperatorMotionBindingTree

    private(set) var sessionState: VimSessionState

    init(
        commandBindings: VimBindingTree = .normalMode,
        operatorMotionBindings: VimOperatorMotionBindingTree = .normalModeDeleteOperator,
        initialState: VimSessionState = VimSessionState()
    ) {
        self.commandBindings = commandBindings
        self.operatorMotionBindings = operatorMotionBindings
        self.sessionState = initialState
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

    func setPreferredColumn(_ preferredColumn: Int?) {
        sessionState.preferredColumn = preferredColumn
    }

    func handle(_ keyPress: VimKeyPress) -> VimHandleResult {
        switch sessionState.mode {
        case .normal:
            handleNormalMode(keyPress)
        case .insert:
            .ignored
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

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch operatorMotionBindings.match(candidateKeys) {
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

    private func resolve(_ command: VimCommand) -> VimHandleResult {
        switch command {
        case .beginOperator(let op, let count):
            sessionState.pendingOperator = op
            sessionState.pendingOperatorCount = count
            return .pending
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
        case .delete(.characterwise(.characterSearch(let search), let count)):
            sessionState.lastCharacterSearch = search
            return .handled(.delete(.characterwise(.characterSearch(search), count: count)))
        case .delete(.characterwise(.repeatCharacterSearch(let oppositeDirection), let count)):
            guard let lastCharacterSearch = sessionState.lastCharacterSearch else {
                return .ignored
            }

            let search = oppositeDirection
                ? lastCharacterSearch.reversed()
                : lastCharacterSearch

            return .handled(.delete(.characterwise(.characterSearch(search), count: count)))
        case .moveText, .moveLayout, .paste:
            return .handled(command)
        case .delete:
            return .handled(command)
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
