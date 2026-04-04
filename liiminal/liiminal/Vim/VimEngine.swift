import Foundation

enum VimHandleResult {
    case handled(VimCommand)
    case pending
    case ignored
}

final class VimEngine {
    private let bindings: VimBindingTree

    private(set) var sessionState: VimSessionState

    init(
        bindings: VimBindingTree = .normalMode,
        initialState: VimSessionState = VimSessionState()
    ) {
        self.bindings = bindings
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

        if consumeCountDigitIfNeeded(keyPress) {
            return .pending
        }

        let candidateKeys = sessionState.pendingKeys + [keyPress]

        switch bindings.match(candidateKeys) {
        case .exact(let commandFactory):
            let count = sessionState.pendingCount ?? 1
            sessionState.clearPendingInput()
            let command = commandFactory(count)

            if case .enterInsertMode = command {
                setMode(.insert)
            }

            return .handled(command)
        case .partial:
            sessionState.pendingKeys = candidateKeys
            return .pending
        case .none:
            sessionState.clearPendingInput()
            return .ignored
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
