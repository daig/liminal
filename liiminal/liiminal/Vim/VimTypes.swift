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
    case forwardDelete
    case ctrlR
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
    case targetPosition(Int)
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

struct VimTextEdit: Equatable {
    let location: Int
    let removedText: String
    let insertedText: String
}

enum VimOperator: Hashable {
    case delete
    case change
    case yank
}

enum VimOperatorMotion {
    case currentLines
    case characterwise(VimTextMotion)
    case linewise(VimTextMotion)
}

enum VimOperatorTarget {
    case currentLines(count: Int?)
    case characterwise(VimTextMotion, count: Int?)
    case linewise(VimTextMotion, count: Int?)
}

enum VimCommand {
    case beginOperator(VimOperator, count: Int?)
    case enterInsert(VimInsertTransition)
    case enterVisual
    case exitVisual
    case moveText(VimTextMotion, count: Int?)
    case moveLayout(VimLayoutMotion, count: Int?)
    case delete(VimOperatorTarget)
    case change(VimOperatorTarget)
    case yank(VimOperatorTarget)
    case deleteSelection
    case changeSelection
    case yankSelection
    case paste(VimPastePlacement, count: Int?)
    case replaceSelectionWithPaste(count: Int?)
    case undo(count: Int?)
    case redo(count: Int?)
}

struct VimStatusPresentation: Equatable {
    let mode: VimMode
    let detailText: String?
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

    var hasPendingInput: Bool {
        pendingCount != nil
            || pendingOperatorCount != nil
            || !pendingKeys.isEmpty
            || pendingCharacterCommandFactory != nil
            || pendingOperator != nil
            || pendingCharacterOperatorMotionFactory != nil
    }

    var statusPresentation: VimStatusPresentation {
        VimStatusPresentation(
            mode: mode,
            detailText: mode == .insert ? nil : pendingDetailText
        )
    }

    private var pendingDetailText: String? {
        if let pendingOperator {
            return pendingOperatorDetailText(for: pendingOperator)
        }

        let sequence = nonOperatorPendingSequenceDisplay()
        return sequence?.isEmpty == false ? sequence : nil
    }

    private func pendingOperatorDetailText(for pendingOperator: VimOperator) -> String {
        let operatorLabel = pendingOperator.statusLabel
        let sequence = operatorPendingSequenceDisplay(for: pendingOperator)
        let isBareOperator =
            pendingKeys.isEmpty
            && pendingCount == nil
            && pendingCharacterOperatorMotionFactory == nil

        if isBareOperator {
            if let pendingOperatorCount {
                return "\(operatorLabel) ×\(pendingOperatorCount)"
            }
            return operatorLabel
        }

        return "\(operatorLabel) · \(sequence)"
    }

    private func operatorPendingSequenceDisplay(for pendingOperator: VimOperator) -> String {
        var sequence = ""

        if let pendingOperatorCount {
            sequence += String(pendingOperatorCount)
        }

        sequence += pendingOperator.keyNotation

        if let pendingCount {
            sequence += String(pendingCount)
        }

        sequence += pendingKeys.map(\.displayNotation).joined()

        return sequence + "…"
    }

    private func nonOperatorPendingSequenceDisplay() -> String? {
        let hasPendingInput =
            pendingCount != nil
            || !pendingKeys.isEmpty
            || pendingCharacterCommandFactory != nil

        guard hasPendingInput else { return nil }

        var sequence = ""

        if let pendingCount {
            sequence += String(pendingCount)
        }

        sequence += pendingKeys.map(\.displayNotation).joined()

        return sequence + "…"
    }
}

extension VimOperator {
    var statusLabel: String {
        switch self {
        case .delete:
            "DELETE"
        case .change:
            "CHANGE"
        case .yank:
            "YANK"
        }
    }

    var displayLabel: String {
        switch self {
        case .delete:
            "Delete"
        case .change:
            "Change"
        case .yank:
            "Yank"
        }
    }

    var keyNotation: String {
        switch self {
        case .delete:
            "d"
        case .change:
            "c"
        case .yank:
            "y"
        }
    }
}

extension VimKeyPress {
    var displayNotation: String {
        switch self {
        case .character(let character):
            character == " " ? "Space" : String(character)
        case .special(.escape):
            "Esc"
        case .special(.leftArrow):
            "Left"
        case .special(.rightArrow):
            "Right"
        case .special(.downArrow):
            "Down"
        case .special(.upArrow):
            "Up"
        case .special(.forwardDelete):
            "Del"
        case .special(.ctrlR):
            "^R"
        case .special(.ctrlU):
            "^U"
        case .special(.ctrlD):
            "^D"
        case .special(.ctrlB):
            "^B"
        case .special(.ctrlF):
            "^F"
        }
    }
}

struct VimBindingTree {
    struct Node {
        var commandFactory: VimCommandFactory?
        var characterCommandFactory: VimCharacterCommandFactory?
        var hintLabel: String?
        var hintItemKind: VimHintItemKind?
        var argumentPlaceholder: String?
        var argumentDescription: String?
        var children: [VimKeyPress: Node] = [:]
        var childOrder: [VimKeyPress] = []
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
            _ sequence: [VimKeyPress],
            description: String,
            kind: VimHintItemKind = .action,
            command: @escaping VimCommandFactory
        ) {
            guard !sequence.isEmpty else { return }
            insert(
                sequence,
                metadata: NodeMetadata(label: description, itemKind: kind),
                command: command,
                at: &root
            )
        }

        mutating func bindCharacterArgument(
            _ sequence: [VimKeyPress],
            description: String,
            argumentPlaceholder: String,
            argumentDescription: String,
            command: @escaping VimCharacterCommandFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(
                sequence,
                metadata: NodeMetadata(
                    label: description,
                    itemKind: .action,
                    argumentPlaceholder: argumentPlaceholder,
                    argumentDescription: argumentDescription
                ),
                command: command,
                at: &root
            )
        }

        mutating func describeGroup(_ sequence: [VimKeyPress], label: String) {
            guard !sequence.isEmpty else { return }
            insertGroup(
                sequence,
                metadata: NodeMetadata(label: label, itemKind: .group),
                at: &root
            )
        }

        private struct NodeMetadata {
            let label: String?
            let itemKind: VimHintItemKind?
            let argumentPlaceholder: String?
            let argumentDescription: String?

            init(
                label: String? = nil,
                itemKind: VimHintItemKind? = nil,
                argumentPlaceholder: String? = nil,
                argumentDescription: String? = nil
            ) {
                self.label = label
                self.itemKind = itemKind
                self.argumentPlaceholder = argumentPlaceholder
                self.argumentDescription = argumentDescription
            }
        }

        private func insert(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            command: @escaping VimCommandFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.commandFactory = command
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insert(
                Array(sequence.dropFirst()),
                metadata: metadata,
                command: command,
                at: &child
            )
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func insertCharacterArgument(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            command: @escaping VimCharacterCommandFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.characterCommandFactory = command
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insertCharacterArgument(
                Array(sequence.dropFirst()),
                metadata: metadata,
                command: command,
                at: &child
            )
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func insertGroup(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insertGroup(Array(sequence.dropFirst()), metadata: metadata, at: &child)
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func apply(_ metadata: NodeMetadata, to node: inout Node) {
            if let label = metadata.label {
                node.hintLabel = label
            }
            if let itemKind = metadata.itemKind {
                node.hintItemKind = itemKind
            }
            if let argumentPlaceholder = metadata.argumentPlaceholder {
                node.argumentPlaceholder = argumentPlaceholder
            }
            if let argumentDescription = metadata.argumentDescription {
                node.argumentDescription = argumentDescription
            }
        }

        func build() -> VimBindingTree {
            VimBindingTree(root: root)
        }
    }

    let root: Node

    func node(at keys: [VimKeyPress]) -> Node? {
        var node = root

        for key in keys {
            guard let child = node.children[key] else { return nil }
            node = child
        }

        return node
    }

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
        var hintLabel: String?
        var hintItemKind: VimHintItemKind?
        var argumentPlaceholder: String?
        var argumentDescription: String?
        var children: [VimKeyPress: Node] = [:]
        var childOrder: [VimKeyPress] = []
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
            _ sequence: [VimKeyPress],
            description: String,
            kind: VimHintItemKind = .action,
            motion: @escaping VimOperatorMotionFactory
        ) {
            guard !sequence.isEmpty else { return }
            insert(
                sequence,
                metadata: NodeMetadata(label: description, itemKind: kind),
                motion: motion,
                at: &root
            )
        }

        mutating func bindCharacterArgument(
            _ sequence: [VimKeyPress],
            description: String,
            argumentPlaceholder: String,
            argumentDescription: String,
            motion: @escaping VimCharacterOperatorMotionFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(
                sequence,
                metadata: NodeMetadata(
                    label: description,
                    itemKind: .action,
                    argumentPlaceholder: argumentPlaceholder,
                    argumentDescription: argumentDescription
                ),
                motion: motion,
                at: &root
            )
        }

        mutating func describeGroup(_ sequence: [VimKeyPress], label: String) {
            guard !sequence.isEmpty else { return }
            insertGroup(
                sequence,
                metadata: NodeMetadata(label: label, itemKind: .group),
                at: &root
            )
        }

        private struct NodeMetadata {
            let label: String?
            let itemKind: VimHintItemKind?
            let argumentPlaceholder: String?
            let argumentDescription: String?

            init(
                label: String? = nil,
                itemKind: VimHintItemKind? = nil,
                argumentPlaceholder: String? = nil,
                argumentDescription: String? = nil
            ) {
                self.label = label
                self.itemKind = itemKind
                self.argumentPlaceholder = argumentPlaceholder
                self.argumentDescription = argumentDescription
            }
        }

        private func insert(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            motion: @escaping VimOperatorMotionFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.motionFactory = motion
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insert(
                Array(sequence.dropFirst()),
                metadata: metadata,
                motion: motion,
                at: &child
            )
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func insertCharacterArgument(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            motion: @escaping VimCharacterOperatorMotionFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.characterMotionFactory = motion
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insertCharacterArgument(
                Array(sequence.dropFirst()),
                metadata: metadata,
                motion: motion,
                at: &child
            )
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func insertGroup(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insertGroup(Array(sequence.dropFirst()), metadata: metadata, at: &child)
            node.children[head] = child
            if !node.childOrder.contains(head) {
                node.childOrder.append(head)
            }
        }

        private func apply(_ metadata: NodeMetadata, to node: inout Node) {
            if let label = metadata.label {
                node.hintLabel = label
            }
            if let itemKind = metadata.itemKind {
                node.hintItemKind = itemKind
            }
            if let argumentPlaceholder = metadata.argumentPlaceholder {
                node.argumentPlaceholder = argumentPlaceholder
            }
            if let argumentDescription = metadata.argumentDescription {
                node.argumentDescription = argumentDescription
            }
        }

        func build() -> VimOperatorMotionBindingTree {
            VimOperatorMotionBindingTree(root: root)
        }
    }

    let root: Node

    func node(at keys: [VimKeyPress]) -> Node? {
        var node = root

        for key in keys {
            guard let child = node.children[key] else { return nil }
            node = child
        }

        return node
    }

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

private enum VimBindingRegistration {
    static func registerSharedNavigationBindings(into builder: inout VimBindingTree.Builder) {
        func bindTextMotion(
            _ sequence: [VimKeyPress],
            motion: VimTextMotion,
            description: String
        ) {
            builder.bind(sequence, description: description) {
                .moveText(motion, count: $0)
            }
        }

        func bindCharacterArgumentMotion(
            _ sequence: [VimKeyPress],
            description: String,
            motion: @escaping (Character) -> VimTextMotion
        ) {
            builder.bindCharacterArgument(
                sequence,
                description: description,
                argumentPlaceholder: "<char>",
                argumentDescription: "Target character"
            ) { character, count in
                .moveText(motion(character), count: count)
            }
        }

        builder.bind(
            [.special(.leftArrow)],
            description: "Move left"
        ) { .moveText(.left, count: $0) }
        builder.bind(
            [.special(.rightArrow)],
            description: "Move right"
        ) { .moveText(.right, count: $0) }
        builder.bind(
            [.special(.downArrow)],
            description: "Move down"
        ) { .moveText(.down, count: $0) }
        builder.bind(
            [.special(.upArrow)],
            description: "Move up"
        ) { .moveText(.up, count: $0) }

        bindTextMotion([.character("h")], motion: .left, description: "Move left")
        bindTextMotion([.character("j")], motion: .down, description: "Move down")
        bindTextMotion([.character("k")], motion: .up, description: "Move up")
        bindTextMotion([.character("l")], motion: .right, description: "Move right")

        bindTextMotion([.character("0")], motion: .lineStart, description: "Line start")
        bindTextMotion(
            [.character("^")],
            motion: .lineFirstNonBlank,
            description: "First non-blank"
        )
        bindTextMotion([.character("$")], motion: .lineEnd, description: "Line end")

        bindTextMotion([.character("w")], motion: .wordForward, description: "Next word")
        bindTextMotion([.character("b")], motion: .wordBackward, description: "Previous word")
        bindTextMotion([.character("e")], motion: .wordEndForward, description: "Word end")

        builder.describeGroup([.character("g")], label: "Go")
        bindTextMotion(
            [.character("g"), .character("g")],
            motion: .goToLine(defaultDestination: .first),
            description: "First line"
        )
        bindTextMotion(
            [.character("G")],
            motion: .goToLine(defaultDestination: .last),
            description: "Last line"
        )

        bindCharacterArgumentMotion(
            [.character("f")],
            description: "Find to character"
        ) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .forward,
                    kind: .to
                )
            )
        }
        bindCharacterArgumentMotion(
            [.character("F")],
            description: "Find backward to character"
        ) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .backward,
                    kind: .to
                )
            )
        }
        bindCharacterArgumentMotion(
            [.character("t")],
            description: "Find until character"
        ) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .forward,
                    kind: .till
                )
            )
        }
        bindCharacterArgumentMotion(
            [.character("T")],
            description: "Find backward until character"
        ) { character in
            .characterSearch(
                VimCharacterSearch(
                    character: character,
                    direction: .backward,
                    kind: .till
                )
            )
        }
        builder.bind([.character(";")], description: "Repeat character search") {
            .moveText(.repeatCharacterSearch(oppositeDirection: false), count: $0)
        }
        builder.bind([.character(",")], description: "Repeat character search backward") {
            .moveText(.repeatCharacterSearch(oppositeDirection: true), count: $0)
        }

        builder.bind([.character("H")], description: "Top screen line") {
            .moveLayout(.windowLine(.top), count: $0)
        }
        builder.bind([.character("M")], description: "Middle screen line") {
            .moveLayout(.windowLine(.middle), count: $0)
        }
        builder.bind([.character("L")], description: "Bottom screen line") {
            .moveLayout(.windowLine(.bottom), count: $0)
        }

        builder.bind([.special(.ctrlU)], description: "Half page up") {
            .moveLayout(.halfPageUp, count: $0)
        }
        builder.bind([.special(.ctrlD)], description: "Half page down") {
            .moveLayout(.halfPageDown, count: $0)
        }
        builder.bind([.special(.ctrlB)], description: "Full page up") {
            .moveLayout(.fullPageUp, count: $0)
        }
        builder.bind([.special(.ctrlF)], description: "Full page down") {
            .moveLayout(.fullPageDown, count: $0)
        }

        builder.bind([.character("g"), .character("j")], description: "Down screen line") {
            .moveLayout(.screenLineDown, count: $0)
        }
        builder.bind([.character("g"), .character("k")], description: "Up screen line") {
            .moveLayout(.screenLineUp, count: $0)
        }
        builder.bind([.character("g"), .character("0")], description: "Screen line start") {
            .moveLayout(.screenLineStart, count: $0)
        }
        builder.bind(
            [.character("g"), .character("^")],
            description: "Screen first non-blank"
        ) {
            .moveLayout(.screenLineFirstNonBlank, count: $0)
        }
        builder.bind([.character("g"), .character("$")], description: "Screen line end") {
            .moveLayout(.screenLineEnd, count: $0)
        }

        bindTextMotion(
            [.character("}")],
            motion: .paragraphForward,
            description: "Next paragraph"
        )
        bindTextMotion(
            [.character("{")],
            motion: .paragraphBackward,
            description: "Previous paragraph"
        )
    }
}

extension VimBindingTree {
    static let normalMode: VimBindingTree = {
        var builder = Builder()
        VimBindingRegistration.registerSharedNavigationBindings(into: &builder)

        builder.bind(
            [.character("d")],
            description: "Delete",
            kind: .group
        ) { .beginOperator(.delete, count: $0) }
        builder.bind(
            [.character("D")],
            description: "Delete to line end"
        ) { .delete(.characterwise(.lineEnd, count: $0)) }
        builder.bind(
            [.character("c")],
            description: "Change",
            kind: .group
        ) { .beginOperator(.change, count: $0) }
        builder.bind(
            [.character("C")],
            description: "Change to line end"
        ) { .change(.characterwise(.lineEnd, count: $0)) }
        builder.bind(
            [.character("y")],
            description: "Yank",
            kind: .group
        ) { .beginOperator(.yank, count: $0) }
        builder.bind([.character("Y")], description: "Yank line") {
            .yank(.currentLines(count: $0))
        }
        builder.bind([.character("s")], description: "Change character") {
            .change(.characterwise(.right, count: $0))
        }
        builder.bind([.character("S")], description: "Change line") {
            .change(.currentLines(count: $0))
        }
        builder.bind([.character("x")], description: "Delete character") {
            .delete(.characterwise(.right, count: $0))
        }
        builder.bind([.character("X")], description: "Delete left character") {
            .delete(.characterwise(.left, count: $0))
        }
        builder.bind([.special(.forwardDelete)], description: "Delete character") {
            .delete(.characterwise(.right, count: $0))
        }
        builder.bind([.character("u")], description: "Undo") { .undo(count: $0) }
        builder.bind([.special(.ctrlR)], description: "Redo") { .redo(count: $0) }
        builder.bind([.character("i")], description: "Insert") { _ in .enterInsert(.atCursor) }
        builder.bind([.character("v")], description: "Visual mode") { _ in .enterVisual }
        builder.bind([.character("a")], description: "Append") { _ in .enterInsert(.afterCursor) }
        builder.bind(
            [.character("I")],
            description: "Insert at first non-blank"
        ) { _ in .enterInsert(.lineFirstNonBlank) }
        builder.bind([.character("A")], description: "Append at line end") {
            _ in .enterInsert(.lineEnd)
        }
        builder.bind([.character("o")], description: "Open line below") {
            _ in .enterInsert(.openLineBelow)
        }
        builder.bind([.character("O")], description: "Open line above") {
            _ in .enterInsert(.openLineAbove)
        }
        builder.bind([.character("p")], description: "Paste after cursor") {
            .paste(.afterCursor, count: $0)
        }
        builder.bind([.character("P")], description: "Paste before cursor") {
            .paste(.beforeCursor, count: $0)
        }

        return builder.build()
    }()

    static let visualMode: VimBindingTree = {
        var builder = Builder()
        VimBindingRegistration.registerSharedNavigationBindings(into: &builder)
        return builder.build()
    }()
}

extension VimOperatorMotionBindingTree {
    private static func normalMode(repeatedKey: Character) -> VimOperatorMotionBindingTree {
        var builder = Builder()

        func bindTextMotion(
            _ sequence: [VimKeyPress],
            kind: VimOperatorMotion,
            hintFragment: String
        ) {
            builder.bind(sequence, description: hintFragment) { _ in kind }
        }

        func bindCharacterArgumentMotion(
            _ sequence: [VimKeyPress],
            hintFragment: String,
            motion: @escaping (Character) -> VimOperatorMotion
        ) {
            builder.bindCharacterArgument(
                sequence,
                description: hintFragment,
                argumentPlaceholder: "<char>",
                argumentDescription: "Target character"
            ) { character, _ in
                motion(character)
            }
        }

        builder.bind(
            [.character(repeatedKey)],
            description: "current line"
        ) { _ in .currentLines }

        bindTextMotion([.character("h")], kind: .characterwise(.left), hintFragment: "left")
        bindTextMotion([.character("j")], kind: .linewise(.down), hintFragment: "line below")
        bindTextMotion([.character("k")], kind: .linewise(.up), hintFragment: "line above")
        bindTextMotion([.character("l")], kind: .characterwise(.right), hintFragment: "character")

        bindTextMotion(
            [.character("0")],
            kind: .characterwise(.lineStart),
            hintFragment: "to line start"
        )
        bindTextMotion(
            [.character("^")],
            kind: .characterwise(.lineFirstNonBlank),
            hintFragment: "to first non-blank"
        )
        bindTextMotion(
            [.character("$")],
            kind: .characterwise(.lineEnd),
            hintFragment: "to line end"
        )

        bindTextMotion(
            [.character("w")],
            kind: .characterwise(.wordForward),
            hintFragment: "word"
        )
        bindTextMotion(
            [.character("b")],
            kind: .characterwise(.wordBackward),
            hintFragment: "previous word"
        )
        bindTextMotion(
            [.character("e")],
            kind: .characterwise(.wordEndForward),
            hintFragment: "to word end"
        )

        builder.describeGroup([.character("g")], label: "Go")
        bindTextMotion(
            [.character("g"), .character("g")],
            kind: .linewise(.goToLine(defaultDestination: .first)),
            hintFragment: "to first line"
        )
        bindTextMotion(
            [.character("G")],
            kind: .linewise(.goToLine(defaultDestination: .last)),
            hintFragment: "to last line"
        )

        bindCharacterArgumentMotion(
            [.character("f")],
            hintFragment: "through character"
        ) { character in
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
        bindCharacterArgumentMotion(
            [.character("F")],
            hintFragment: "backward through character"
        ) { character in
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
        bindCharacterArgumentMotion(
            [.character("t")],
            hintFragment: "until character"
        ) { character in
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
        bindCharacterArgumentMotion(
            [.character("T")],
            hintFragment: "backward until character"
        ) { character in
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
        builder.bind([.character(";")], description: "repeat character search") { _ in
            .characterwise(.repeatCharacterSearch(oppositeDirection: false))
        }
        builder.bind([.character(",")], description: "repeat backward character search") { _ in
            .characterwise(.repeatCharacterSearch(oppositeDirection: true))
        }

        bindTextMotion(
            [.character("}")],
            kind: .linewise(.paragraphForward),
            hintFragment: "next paragraph"
        )
        bindTextMotion(
            [.character("{")],
            kind: .linewise(.paragraphBackward),
            hintFragment: "previous paragraph"
        )

        return builder.build()
    }

    static let normalModeDeleteOperator = normalMode(repeatedKey: "d")
    static let normalModeChangeOperator = normalMode(repeatedKey: "c")
    static let normalModeYankOperator = normalMode(repeatedKey: "y")
}
