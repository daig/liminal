import Foundation

typealias VimCommandFactory = (Int?) -> VimCommand
typealias VimCharacterCommandFactory = (Character, Int?) -> VimCommand
typealias VimOperatorMotionFactory = (Int?) -> VimOperatorMotion
typealias VimCharacterOperatorMotionFactory = (Character, Int?) -> VimOperatorMotion

enum VimSpecialKey: Hashable {
    case escape
    case leftArrow
    case rightArrow
    case downArrow
    case upArrow
    case ctrlU
    case ctrlD
    case ctrlB
    case ctrlF
}

enum VimKeyPress: Hashable {
    case character(Character)
    case special(VimSpecialKey)
}

enum VimDefaultLineDestination: Equatable {
    case first
    case last
}

enum VimCharacterSearchDirection: Equatable {
    case forward
    case backward
}

enum VimCharacterSearchKind: Equatable {
    case to
    case till
}

struct VimCharacterSearch {
    let character: Character
    let direction: VimCharacterSearchDirection
    let kind: VimCharacterSearchKind

    func reversed() -> VimCharacterSearch {
        VimCharacterSearch(
            character: character,
            direction: direction == .forward ? .backward : .forward,
            kind: kind
        )
    }
}

enum VimTextMotion {
    case left
    case right
    case up
    case down
    case lineStart
    case lineFirstNonBlank
    case lineEnd
    case wordForward
    case wordBackward
    case wordEndForward
    case goToLine(defaultDestination: VimDefaultLineDestination)
    case characterSearch(VimCharacterSearch)
    case repeatCharacterSearch(oppositeDirection: Bool)
    case paragraphForward
    case paragraphBackward
}

enum VimViewportLinePosition: Equatable {
    case top
    case middle
    case bottom
}

enum VimLayoutMotion {
    case windowLine(VimViewportLinePosition)
    case screenLineDown
    case screenLineUp
    case screenLineStart
    case screenLineFirstNonBlank
    case screenLineEnd
    case halfPageDown
    case halfPageUp
    case fullPageDown
    case fullPageUp
}

enum VimInsertTransition {
    case atCursor
    case afterCursor
    case lineFirstNonBlank
    case lineEnd
    case openLineBelow
    case openLineAbove
}

enum VimPastePlacement {
    case afterCursor
    case beforeCursor
}

enum VimPasteStyle: String {
    case characterwise
    case linewise
}

struct VimPastePayload {
    let text: String
    let style: VimPasteStyle
}

enum VimOperator {
    case delete
}

enum VimOperatorMotion {
    case currentLines
    case characterwise(VimTextMotion)
    case linewise(VimTextMotion)
}

enum VimDeleteTarget {
    case currentLines(count: Int?)
    case characterwise(VimTextMotion, count: Int?)
    case linewise(VimTextMotion, count: Int?)
}

enum VimCommand {
    case beginOperator(VimOperator, count: Int?)
    case enterInsert(VimInsertTransition)
    case moveText(VimTextMotion, count: Int?)
    case moveLayout(VimLayoutMotion, count: Int?)
    case delete(VimDeleteTarget)
    case paste(VimPastePlacement, count: Int?)
}

struct VimSessionState {
    var mode: VimMode = .normal
    var pendingCount: Int?
    var pendingOperatorCount: Int?
    var pendingKeys: [VimKeyPress] = []
    var pendingCharacterCommandFactory: VimCharacterCommandFactory?
    var pendingOperator: VimOperator?
    var pendingCharacterOperatorMotionFactory: VimCharacterOperatorMotionFactory?
    var preferredColumn: Int?
    var lastCharacterSearch: VimCharacterSearch?

    mutating func clearPendingInput() {
        pendingCount = nil
        pendingOperatorCount = nil
        pendingKeys.removeAll()
        pendingCharacterCommandFactory = nil
        pendingOperator = nil
        pendingCharacterOperatorMotionFactory = nil
    }
}

struct VimBindingTree {
    struct Node {
        var commandFactory: VimCommandFactory?
        var characterCommandFactory: VimCharacterCommandFactory?
        var children: [VimKeyPress: Node] = [:]
    }

    enum Match {
        case exact(VimCommandFactory)
        case characterPending(VimCharacterCommandFactory)
        case partial
        case none
    }

    struct Builder {
        private var root = Node()

        mutating func bind(
            _ sequence: [VimKeyPress], command: @escaping VimCommandFactory
        ) {
            guard !sequence.isEmpty else { return }
            insert(sequence, command: command, at: &root)
        }

        mutating func bindCharacterArgument(
            _ sequence: [VimKeyPress], command: @escaping VimCharacterCommandFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(sequence, command: command, at: &root)
        }

        private func insert(
            _ sequence: [VimKeyPress],
            command: @escaping VimCommandFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.commandFactory = command
                return
            }

            var child = node.children[head] ?? Node()
            insert(Array(sequence.dropFirst()), command: command, at: &child)
            node.children[head] = child
        }

        private func insertCharacterArgument(
            _ sequence: [VimKeyPress],
            command: @escaping VimCharacterCommandFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.characterCommandFactory = command
                return
            }

            var child = node.children[head] ?? Node()
            insertCharacterArgument(
                Array(sequence.dropFirst()),
                command: command,
                at: &child
            )
            node.children[head] = child
        }

        func build() -> VimBindingTree {
            VimBindingTree(root: root)
        }
    }

    let root: Node

    func match(_ keys: [VimKeyPress]) -> Match {
        guard !keys.isEmpty else { return .partial }

        var node = root
        for key in keys {
            guard let child = node.children[key] else { return .none }
            node = child
        }

        if let commandFactory = node.commandFactory {
            return .exact(commandFactory)
        }

        if let characterCommandFactory = node.characterCommandFactory {
            return .characterPending(characterCommandFactory)
        }

        return node.children.isEmpty ? .none : .partial
    }
}

struct VimOperatorMotionBindingTree {
    struct Node {
        var motionFactory: VimOperatorMotionFactory?
        var characterMotionFactory: VimCharacterOperatorMotionFactory?
        var children: [VimKeyPress: Node] = [:]
    }

    enum Match {
        case exact(VimOperatorMotionFactory)
        case characterPending(VimCharacterOperatorMotionFactory)
        case partial
        case none
    }

    struct Builder {
        private var root = Node()

        mutating func bind(
            _ sequence: [VimKeyPress], motion: @escaping VimOperatorMotionFactory
        ) {
            guard !sequence.isEmpty else { return }
            insert(sequence, motion: motion, at: &root)
        }

        mutating func bindCharacterArgument(
            _ sequence: [VimKeyPress], motion: @escaping VimCharacterOperatorMotionFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(sequence, motion: motion, at: &root)
        }

        private func insert(
            _ sequence: [VimKeyPress],
            motion: @escaping VimOperatorMotionFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.motionFactory = motion
                return
            }

            var child = node.children[head] ?? Node()
            insert(Array(sequence.dropFirst()), motion: motion, at: &child)
            node.children[head] = child
        }

        private func insertCharacterArgument(
            _ sequence: [VimKeyPress],
            motion: @escaping VimCharacterOperatorMotionFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.characterMotionFactory = motion
                return
            }

            var child = node.children[head] ?? Node()
            insertCharacterArgument(
                Array(sequence.dropFirst()),
                motion: motion,
                at: &child
            )
            node.children[head] = child
        }

        func build() -> VimOperatorMotionBindingTree {
            VimOperatorMotionBindingTree(root: root)
        }
    }

    let root: Node

    func match(_ keys: [VimKeyPress]) -> Match {
        guard !keys.isEmpty else { return .partial }

        var node = root
        for key in keys {
            guard let child = node.children[key] else { return .none }
            node = child
        }

        if let motionFactory = node.motionFactory {
            return .exact(motionFactory)
        }

        if let characterMotionFactory = node.characterMotionFactory {
            return .characterPending(characterMotionFactory)
        }

        return node.children.isEmpty ? .none : .partial
    }
}

extension VimBindingTree {
    static let normalMode: VimBindingTree = {
        var builder = Builder()

        func bindTextMotion(_ sequence: [VimKeyPress], motion: VimTextMotion) {
            builder.bind(sequence) { .moveText(motion, count: $0) }
        }

        func bindCharacterArgumentMotion(
            _ sequence: [VimKeyPress],
            motion: @escaping (Character) -> VimTextMotion
        ) {
            builder.bindCharacterArgument(sequence) { character, count in
                .moveText(motion(character), count: count)
            }
        }

        builder.bind([.special(.leftArrow)]) { .moveText(.left, count: $0) }
        builder.bind([.special(.rightArrow)]) { .moveText(.right, count: $0) }
        builder.bind([.special(.downArrow)]) { .moveText(.down, count: $0) }
        builder.bind([.special(.upArrow)]) { .moveText(.up, count: $0) }

        bindTextMotion([.character("h")], motion: .left)
        bindTextMotion([.character("j")], motion: .down)
        bindTextMotion([.character("k")], motion: .up)
        bindTextMotion([.character("l")], motion: .right)

        bindTextMotion([.character("0")], motion: .lineStart)
        bindTextMotion([.character("^")], motion: .lineFirstNonBlank)
        bindTextMotion([.character("$")], motion: .lineEnd)

        builder.bind([.character("d")]) { .beginOperator(.delete, count: $0) }
        builder.bind([.character("D")]) { .delete(.characterwise(.lineEnd, count: $0)) }
        builder.bind([.character("i")]) { _ in .enterInsert(.atCursor) }
        builder.bind([.character("a")]) { _ in .enterInsert(.afterCursor) }
        builder.bind([.character("I")]) { _ in .enterInsert(.lineFirstNonBlank) }
        builder.bind([.character("A")]) { _ in .enterInsert(.lineEnd) }
        builder.bind([.character("o")]) { _ in .enterInsert(.openLineBelow) }
        builder.bind([.character("O")]) { _ in .enterInsert(.openLineAbove) }
        builder.bind([.character("p")]) { .paste(.afterCursor, count: $0) }
        builder.bind([.character("P")]) { .paste(.beforeCursor, count: $0) }

        bindTextMotion([.character("w")], motion: .wordForward)
        bindTextMotion([.character("b")], motion: .wordBackward)
        bindTextMotion([.character("e")], motion: .wordEndForward)

        bindTextMotion([.character("g"), .character("g")], motion: .goToLine(defaultDestination: .first))
        bindTextMotion([.character("G")], motion: .goToLine(defaultDestination: .last))

        bindCharacterArgumentMotion([.character("f")]) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .forward,
                    kind: .to
                )
            )
        }
        bindCharacterArgumentMotion([.character("F")]) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .backward,
                    kind: .to
                )
            )
        }
        bindCharacterArgumentMotion([.character("t")]) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .forward,
                    kind: .till
                )
            )
        }
        bindCharacterArgumentMotion([.character("T")]) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .backward,
                    kind: .till
                )
            )
        }
        builder.bind([.character(";")]) {
            .moveText(.repeatCharacterSearch(oppositeDirection: false), count: $0)
        }
        builder.bind([.character(",")]) {
            .moveText(.repeatCharacterSearch(oppositeDirection: true), count: $0)
        }

        builder.bind([.character("H")]) { .moveLayout(.windowLine(.top), count: $0) }
        builder.bind([.character("M")]) { .moveLayout(.windowLine(.middle), count: $0) }
        builder.bind([.character("L")]) { .moveLayout(.windowLine(.bottom), count: $0) }

        builder.bind([.special(.ctrlU)]) { .moveLayout(.halfPageUp, count: $0) }
        builder.bind([.special(.ctrlD)]) { .moveLayout(.halfPageDown, count: $0) }
        builder.bind([.special(.ctrlB)]) { .moveLayout(.fullPageUp, count: $0) }
        builder.bind([.special(.ctrlF)]) { .moveLayout(.fullPageDown, count: $0) }

        builder.bind([.character("g"), .character("j")]) {
            .moveLayout(.screenLineDown, count: $0)
        }
        builder.bind([.character("g"), .character("k")]) {
            .moveLayout(.screenLineUp, count: $0)
        }
        builder.bind([.character("g"), .character("0")]) {
            .moveLayout(.screenLineStart, count: $0)
        }
        builder.bind([.character("g"), .character("^")]) {
            .moveLayout(.screenLineFirstNonBlank, count: $0)
        }
        builder.bind([.character("g"), .character("$")]) {
            .moveLayout(.screenLineEnd, count: $0)
        }

        bindTextMotion([.character("}")], motion: .paragraphForward)
        bindTextMotion([.character("{")], motion: .paragraphBackward)

        return builder.build()
    }()
}

extension VimOperatorMotionBindingTree {
    static let normalModeDeleteOperator: VimOperatorMotionBindingTree = {
        var builder = Builder()

        func bindTextMotion(_ sequence: [VimKeyPress], kind: VimOperatorMotion) {
            builder.bind(sequence) { _ in kind }
        }

        func bindCharacterArgumentMotion(
            _ sequence: [VimKeyPress],
            motion: @escaping (Character) -> VimOperatorMotion
        ) {
            builder.bindCharacterArgument(sequence) { character, _ in
                motion(character)
            }
        }

        builder.bind([.character("d")]) { _ in .currentLines }

        bindTextMotion([.character("h")], kind: .characterwise(.left))
        bindTextMotion([.character("j")], kind: .linewise(.down))
        bindTextMotion([.character("k")], kind: .linewise(.up))
        bindTextMotion([.character("l")], kind: .characterwise(.right))

        bindTextMotion([.character("0")], kind: .characterwise(.lineStart))
        bindTextMotion([.character("^")], kind: .characterwise(.lineFirstNonBlank))
        bindTextMotion([.character("$")], kind: .characterwise(.lineEnd))

        bindTextMotion([.character("w")], kind: .characterwise(.wordForward))
        bindTextMotion([.character("b")], kind: .characterwise(.wordBackward))
        bindTextMotion([.character("e")], kind: .characterwise(.wordEndForward))

        bindTextMotion(
            [.character("g"), .character("g")],
            kind: .linewise(.goToLine(defaultDestination: .first))
        )
        bindTextMotion(
            [.character("G")],
            kind: .linewise(.goToLine(defaultDestination: .last))
        )

        bindCharacterArgumentMotion([.character("f")]) { character in
            .characterwise(
                .characterSearch(
                    VimCharacterSearch(
                        character: character,
                        direction: .forward,
                        kind: .to
                    )
                )
            )
        }
        bindCharacterArgumentMotion([.character("F")]) { character in
            .characterwise(
                .characterSearch(
                    VimCharacterSearch(
                        character: character,
                        direction: .backward,
                        kind: .to
                    )
                )
            )
        }
        bindCharacterArgumentMotion([.character("t")]) { character in
            .characterwise(
                .characterSearch(
                    VimCharacterSearch(
                        character: character,
                        direction: .forward,
                        kind: .till
                    )
                )
            )
        }
        bindCharacterArgumentMotion([.character("T")]) { character in
            .characterwise(
                .characterSearch(
                    VimCharacterSearch(
                        character: character,
                        direction: .backward,
                        kind: .till
                    )
                )
            )
        }
        builder.bind([.character(";")]) { _ in
            .characterwise(.repeatCharacterSearch(oppositeDirection: false))
        }
        builder.bind([.character(",")]) { _ in
            .characterwise(.repeatCharacterSearch(oppositeDirection: true))
        }

        bindTextMotion([.character("}")], kind: .linewise(.paragraphForward))
        bindTextMotion([.character("{")], kind: .linewise(.paragraphBackward))

        return builder.build()
    }()
}
