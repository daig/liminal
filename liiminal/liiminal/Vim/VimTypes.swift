import Foundation

typealias VimCommandFactory = (Int?) -> VimCommand
typealias VimCharacterCommandFactory = (Character, Int?) -> VimCommand
typealias VimOperatorArgumentFactory = (Int?) -> VimOperatorArgument
typealias VimCharacterOperatorArgumentFactory = (Character, Int?) -> VimOperatorArgument
typealias VimMarkResolver = (Character) -> Int?

enum VimSpecialKey: Hashable, Equatable {
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

enum VimKeyPress: Hashable, Equatable {
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

struct VimCharacterSearch: Equatable {
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

enum VimTextMotion: Equatable {
    case left
    case right
    case up
    case down
    case targetPosition(Int)
    case mark(Character)
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

enum VimLayoutMotion: Equatable {
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

enum VimInsertTransition: Equatable {
    case atCursor
    case afterCursor
    case lineFirstNonBlank
    case lineEnd
    case openLineBelow
    case openLineAbove
}

enum VimVisualKind: Equatable {
    case characterwise
    case linewise

    var mode: VimMode {
        switch self {
        case .characterwise:
            .visual
        case .linewise:
            .visualLine
        }
    }
}

enum VimPastePlacement: Equatable {
    case afterCursor
    case beforeCursor
}

enum VimPasteStyle: String, Equatable {
    case characterwise
    case linewise
}

struct VimPastePayload: Equatable {
    let text: String
    let style: VimPasteStyle
}

struct VimTextEdit: Equatable {
    let location: Int
    let removedText: String
    let insertedText: String
}

enum VimOperator: Hashable, Equatable {
    case delete
    case change
    case yank
}

enum VimOperatorArgumentGranularity: Equatable {
    case characterwise
    case linewise
}

struct VimMotionArgument: Equatable {
    let motion: VimTextMotion
    let granularity: VimOperatorArgumentGranularity
    let count: Int?
}

enum VimTextObjectScope: Equatable {
    case around
    case inner
}

enum VimTextObjectKind: Equatable {
    case word
    case wordBig
    case sentence
    case paragraph
    case parenBlock
    case braceBlock
    case bracketBlock
    case angleBlock
    case tagBlock
    case doubleQuote
    case singleQuote
    case backtickQuote
}

struct VimTextObjectArgument: Equatable {
    let scope: VimTextObjectScope
    let kind: VimTextObjectKind
    let count: Int?
}

enum VimObjectArgument: Equatable {
    case text(VimTextObjectArgument)
}

enum VimOperatorArgument: Equatable {
    case currentLines(count: Int?)
    case motion(VimMotionArgument)
    case object(VimObjectArgument)
}

enum VimCommand: Equatable {
    case beginOperator(VimOperator, count: Int?)
    case setMark(Character)
    case enterInsert(VimInsertTransition)
    case enterVisual(VimVisualKind)
    case exitVisual
    case scrollCursorLine(VimViewportLinePosition)
    case moveText(VimTextMotion, count: Int?)
    case moveLayout(VimLayoutMotion, count: Int?)
    case delete(VimOperatorArgument)
    case change(VimOperatorArgument)
    case yank(VimOperatorArgument)
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

struct VimCursorInfoItem: Equatable, Identifiable {
    let label: String
    let tint: VimDisplayTint?

    var id: String {
        label
    }
}

struct VimCursorInfoPresentation: Equatable {
    let sectionTitle: String
    let items: [VimCursorInfoItem]
}

enum VimResolvedOperatorTarget: Equatable {
    case text(VimSelectionResult)
}

private func combineOperatorCounts(_ lhs: Int?, _ rhs: Int?) -> Int? {
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

extension VimMotionArgument {
    func applying(operatorCount: Int?) -> VimMotionArgument {
        let effectiveCount: Int?

        switch motion {
        case .goToLine:
            effectiveCount = count ?? operatorCount
        default:
            effectiveCount = combineOperatorCounts(operatorCount, count)
        }

        return VimMotionArgument(
            motion: motion,
            granularity: granularity,
            count: effectiveCount
        )
    }
}

extension VimTextObjectArgument {
    func applying(operatorCount: Int?) -> VimTextObjectArgument {
        VimTextObjectArgument(
            scope: scope,
            kind: kind,
            count: combineOperatorCounts(operatorCount, count)
        )
    }
}

extension VimOperatorArgument {
    static func characterwiseMotion(_ motion: VimTextMotion, count: Int? = nil) -> VimOperatorArgument {
        .motion(
            VimMotionArgument(
                motion: motion,
                granularity: .characterwise,
                count: count
            )
        )
    }

    static func linewiseMotion(_ motion: VimTextMotion, count: Int? = nil) -> VimOperatorArgument {
        .motion(
            VimMotionArgument(
                motion: motion,
                granularity: .linewise,
                count: count
            )
        )
    }

    static func textObject(
        scope: VimTextObjectScope,
        kind: VimTextObjectKind,
        count: Int? = nil
    ) -> VimOperatorArgument {
        .object(
            .text(
                VimTextObjectArgument(
                    scope: scope,
                    kind: kind,
                    count: count
                )
            )
        )
    }

    func applying(operatorCount: Int?) -> VimOperatorArgument {
        switch self {
        case .currentLines(let count):
            return .currentLines(count: combineOperatorCounts(operatorCount, count))
        case .motion(let argument):
            return .motion(argument.applying(operatorCount: operatorCount))
        case .object(.text(let argument)):
            return .object(.text(argument.applying(operatorCount: operatorCount)))
        }
    }
}

struct VimSessionState {
    var mode: VimMode = .normal
    var pendingCount: Int?
    var pendingOperatorCount: Int?
    var pendingKeys: [VimKeyPress] = []
    var pendingCharacterCommandFactory: VimCharacterCommandFactory?
    var pendingOperator: VimOperator?
    var pendingCharacterOperatorArgumentFactory: VimCharacterOperatorArgumentFactory?
    var preferredColumn: Int?
    var lastCharacterSearch: VimCharacterSearch?

    mutating func clearPendingInput() {
        pendingCount = nil
        pendingOperatorCount = nil
        pendingKeys.removeAll()
        pendingCharacterCommandFactory = nil
        pendingOperator = nil
        pendingCharacterOperatorArgumentFactory = nil
    }

    var hasPendingInput: Bool {
        pendingCount != nil
            || pendingOperatorCount != nil
            || !pendingKeys.isEmpty
            || pendingCharacterCommandFactory != nil
            || pendingOperator != nil
            || pendingCharacterOperatorArgumentFactory != nil
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
            && pendingCharacterOperatorArgumentFactory == nil

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
        var argumentPresentation: VimHintArgumentPresentation?
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
            argumentHint: VimHintArgumentPresentation,
            command: @escaping VimCharacterCommandFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(
                sequence,
                metadata: NodeMetadata(
                    label: description,
                    itemKind: .action,
                    argumentPresentation: argumentHint
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
            let argumentPresentation: VimHintArgumentPresentation?

            init(
                label: String? = nil,
                itemKind: VimHintItemKind? = nil,
                argumentPresentation: VimHintArgumentPresentation? = nil
            ) {
                self.label = label
                self.itemKind = itemKind
                self.argumentPresentation = argumentPresentation
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
            if let argumentPresentation = metadata.argumentPresentation {
                node.argumentPresentation = argumentPresentation
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

struct VimOperatorArgumentBindingTree {
    struct Node {
        var argumentFactory: VimOperatorArgumentFactory?
        var characterArgumentFactory: VimCharacterOperatorArgumentFactory?
        var hintLabel: String?
        var hintItemKind: VimHintItemKind?
        var argumentPresentation: VimHintArgumentPresentation?
        var children: [VimKeyPress: Node] = [:]
        var childOrder: [VimKeyPress] = []
    }

    enum Match {
        case exact(VimOperatorArgumentFactory)
        case characterPending(VimCharacterOperatorArgumentFactory)
        case partial
        case none
    }

    struct Builder {
        private var root = Node()

        mutating func bind(
            _ sequence: [VimKeyPress],
            description: String,
            kind: VimHintItemKind = .action,
            argument: @escaping VimOperatorArgumentFactory
        ) {
            guard !sequence.isEmpty else { return }
            insert(
                sequence,
                metadata: NodeMetadata(label: description, itemKind: kind),
                argument: argument,
                at: &root
            )
        }

        mutating func bindCharacterArgument(
            _ sequence: [VimKeyPress],
            description: String,
            argumentHint: VimHintArgumentPresentation,
            argument: @escaping VimCharacterOperatorArgumentFactory
        ) {
            guard !sequence.isEmpty else { return }
            insertCharacterArgument(
                sequence,
                metadata: NodeMetadata(
                    label: description,
                    itemKind: .action,
                    argumentPresentation: argumentHint
                ),
                argument: argument,
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
            let argumentPresentation: VimHintArgumentPresentation?

            init(
                label: String? = nil,
                itemKind: VimHintItemKind? = nil,
                argumentPresentation: VimHintArgumentPresentation? = nil
            ) {
                self.label = label
                self.itemKind = itemKind
                self.argumentPresentation = argumentPresentation
            }
        }

        private func insert(
            _ sequence: [VimKeyPress],
            metadata: NodeMetadata,
            argument: @escaping VimOperatorArgumentFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.argumentFactory = argument
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insert(
                Array(sequence.dropFirst()),
                metadata: metadata,
                argument: argument,
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
            argument: @escaping VimCharacterOperatorArgumentFactory,
            at node: inout Node
        ) {
            guard let head = sequence.first else {
                node.characterArgumentFactory = argument
                apply(metadata, to: &node)
                return
            }

            var child = node.children[head] ?? Node()
            insertCharacterArgument(
                Array(sequence.dropFirst()),
                metadata: metadata,
                argument: argument,
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
            if let argumentPresentation = metadata.argumentPresentation {
                node.argumentPresentation = argumentPresentation
            }
        }

        func build() -> VimOperatorArgumentBindingTree {
            VimOperatorArgumentBindingTree(root: root)
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

        if let argumentFactory = node.argumentFactory {
            return .exact(argumentFactory)
        }

        if let characterArgumentFactory = node.characterArgumentFactory {
            return .characterPending(characterArgumentFactory)
        }

        return node.children.isEmpty ? .none : .partial
    }
}

private enum VimBindingRegistration {
    static func registerSharedNavigationBindings(into builder: inout VimBindingTree.Builder) {
        let characterArgumentHint = VimHintArgumentPresentation.placeholder(
            VimHintItem(
                key: "<char>",
                description: "Target character",
                kind: .argument,
                tint: nil
            )
        )
        let markArgumentHint = VimHintArgumentPresentation.dynamic(
            .localMarks,
            fallback: VimHintItem(
                key: "<mark>",
                description: "Mark name",
                kind: .argument,
                tint: nil
            )
        )

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
                argumentHint: characterArgumentHint
            ) { character, count in
                .moveText(motion(character), count: count)
            }
        }

        func bindMarkMotion(
            _ sequence: [VimKeyPress],
            description: String
        ) {
            builder.bindCharacterArgument(
                sequence,
                description: description,
                argumentHint: markArgumentHint
            ) { character, _ in
                .moveText(.mark(character), count: nil)
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
        bindMarkMotion([.character("`")], description: "Jump to mark")

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

        builder.describeGroup([.character("z")], label: "Scroll")
        builder.bind([.character("z"), .character("t")], description: "Cursor line to top") {
            _ in .scrollCursorLine(.top)
        }
        builder.bind([.character("z"), .character("z")], description: "Cursor line to center") {
            _ in .scrollCursorLine(.middle)
        }
        builder.bind([.character("z"), .character("b")], description: "Cursor line to bottom") {
            _ in .scrollCursorLine(.bottom)
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
        builder.bindCharacterArgument(
            [.character("m")],
            description: "Set mark",
            argumentHint: VimHintArgumentPresentation.dynamic(
                .localMarks,
                fallback: VimHintItem(
                    key: "<mark>",
                    description: "Mark name",
                    kind: .argument,
                    tint: nil
                )
            )
        ) { character, _ in
            .setMark(character)
        }
        builder.bind(
            [.character("D")],
            description: "Delete to line end"
        ) { .delete(.characterwiseMotion(.lineEnd, count: $0)) }
        builder.bind(
            [.character("c")],
            description: "Change",
            kind: .group
        ) { .beginOperator(.change, count: $0) }
        builder.bind(
            [.character("C")],
            description: "Change to line end"
        ) { .change(.characterwiseMotion(.lineEnd, count: $0)) }
        builder.bind(
            [.character("y")],
            description: "Yank",
            kind: .group
        ) { .beginOperator(.yank, count: $0) }
        builder.bind([.character("Y")], description: "Yank line") {
            .yank(.currentLines(count: $0))
        }
        builder.bind([.character("s")], description: "Change character") {
            .change(.characterwiseMotion(.right, count: $0))
        }
        builder.bind([.character("S")], description: "Change line") {
            .change(.currentLines(count: $0))
        }
        builder.bind([.character("x")], description: "Delete character") {
            .delete(.characterwiseMotion(.right, count: $0))
        }
        builder.bind([.character("X")], description: "Delete left character") {
            .delete(.characterwiseMotion(.left, count: $0))
        }
        builder.bind([.special(.forwardDelete)], description: "Delete character") {
            .delete(.characterwiseMotion(.right, count: $0))
        }
        builder.bind([.character("u")], description: "Undo") { .undo(count: $0) }
        builder.bind([.special(.ctrlR)], description: "Redo") { .redo(count: $0) }
        builder.bind([.character("i")], description: "Insert") { _ in .enterInsert(.atCursor) }
        builder.bind([.character("v")], description: "Visual mode") {
            _ in .enterVisual(.characterwise)
        }
        builder.bind([.character("V")], description: "Visual line mode") {
            _ in .enterVisual(.linewise)
        }
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

extension VimOperatorArgumentBindingTree {
    private static func normalMode(repeatedKey: Character) -> VimOperatorArgumentBindingTree {
        var builder = Builder()
        let characterArgumentHint = VimHintArgumentPresentation.placeholder(
            VimHintItem(
                key: "<char>",
                description: "Target character",
                kind: .argument,
                tint: nil
            )
        )
        let markArgumentHint = VimHintArgumentPresentation.dynamic(
            .localMarks,
            fallback: VimHintItem(
                key: "<mark>",
                description: "Mark name",
                kind: .argument,
                tint: nil
            )
        )

        func bindTextMotion(
            _ sequence: [VimKeyPress],
            argument: VimOperatorArgument,
            hintFragment: String
        ) {
            builder.bind(sequence, description: hintFragment) { _ in argument }
        }

        func bindCharacterArgumentMotion(
            _ sequence: [VimKeyPress],
            hintFragment: String,
            argument: @escaping (Character) -> VimOperatorArgument
        ) {
            builder.bindCharacterArgument(
                sequence,
                description: hintFragment,
                argumentHint: characterArgumentHint
            ) { character, _ in
                argument(character)
            }
        }

        func bindMarkMotion(
            _ sequence: [VimKeyPress],
            hintFragment: String
        ) {
            builder.bindCharacterArgument(
                sequence,
                description: hintFragment,
                argumentHint: markArgumentHint
            ) { character, _ in
                .characterwiseMotion(.mark(character))
            }
        }

        func bindTextObject(
            _ sequence: [VimKeyPress],
            scope: VimTextObjectScope,
            kind: VimTextObjectKind,
            hintFragment: String
        ) {
            builder.bind(sequence, description: hintFragment) { count in
                .textObject(scope: scope, kind: kind, count: count)
            }
        }

        builder.bind(
            [.character(repeatedKey)],
            description: "current line"
        ) { _ in .currentLines(count: nil) }

        bindTextMotion(
            [.character("h")],
            argument: .characterwiseMotion(.left),
            hintFragment: "left"
        )
        bindTextMotion(
            [.character("j")],
            argument: .linewiseMotion(.down),
            hintFragment: "line below"
        )
        bindTextMotion(
            [.character("k")],
            argument: .linewiseMotion(.up),
            hintFragment: "line above"
        )
        bindTextMotion(
            [.character("l")],
            argument: .characterwiseMotion(.right),
            hintFragment: "character"
        )

        bindTextMotion(
            [.character("0")],
            argument: .characterwiseMotion(.lineStart),
            hintFragment: "to line start"
        )
        bindTextMotion(
            [.character("^")],
            argument: .characterwiseMotion(.lineFirstNonBlank),
            hintFragment: "to first non-blank"
        )
        bindTextMotion(
            [.character("$")],
            argument: .characterwiseMotion(.lineEnd),
            hintFragment: "to line end"
        )

        bindTextMotion(
            [.character("w")],
            argument: .characterwiseMotion(.wordForward),
            hintFragment: "word"
        )
        bindTextMotion(
            [.character("b")],
            argument: .characterwiseMotion(.wordBackward),
            hintFragment: "previous word"
        )
        bindTextMotion(
            [.character("e")],
            argument: .characterwiseMotion(.wordEndForward),
            hintFragment: "to word end"
        )
        bindMarkMotion([.character("`")], hintFragment: "to mark")

        builder.describeGroup([.character("g")], label: "Go")
        bindTextMotion(
            [.character("g"), .character("g")],
            argument: .linewiseMotion(.goToLine(defaultDestination: .first)),
            hintFragment: "to first line"
        )
        bindTextMotion(
            [.character("G")],
            argument: .linewiseMotion(.goToLine(defaultDestination: .last)),
            hintFragment: "to last line"
        )

        bindCharacterArgumentMotion(
            [.character("f")],
            hintFragment: "through character"
        ) { character in
            .characterwiseMotion(
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
            .characterwiseMotion(
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
            .characterwiseMotion(
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
            .characterwiseMotion(
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
            .characterwiseMotion(.repeatCharacterSearch(oppositeDirection: false))
        }
        builder.bind([.character(",")], description: "repeat backward character search") { _ in
            .characterwiseMotion(.repeatCharacterSearch(oppositeDirection: true))
        }

        bindTextMotion(
            [.character("}")],
            argument: .linewiseMotion(.paragraphForward),
            hintFragment: "next paragraph"
        )
        bindTextMotion(
            [.character("{")],
            argument: .linewiseMotion(.paragraphBackward),
            hintFragment: "previous paragraph"
        )

        builder.describeGroup([.character("a")], label: "Around")
        bindTextObject(
            [.character("a"), .character("w")],
            scope: .around,
            kind: .word,
            hintFragment: "word"
        )
        bindTextObject(
            [.character("a"), .character("W")],
            scope: .around,
            kind: .wordBig,
            hintFragment: "WORD"
        )
        bindTextObject(
            [.character("a"), .character("s")],
            scope: .around,
            kind: .sentence,
            hintFragment: "sentence"
        )
        bindTextObject(
            [.character("a"), .character("p")],
            scope: .around,
            kind: .paragraph,
            hintFragment: "paragraph"
        )
        bindTextObject(
            [.character("a"), .character("b")],
            scope: .around,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("a"), .character("(")],
            scope: .around,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("a"), .character(")")],
            scope: .around,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("a"), .character("B")],
            scope: .around,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("a"), .character("{")],
            scope: .around,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("a"), .character("}")],
            scope: .around,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("a"), .character("[")],
            scope: .around,
            kind: .bracketBlock,
            hintFragment: "[] block"
        )
        bindTextObject(
            [.character("a"), .character("]")],
            scope: .around,
            kind: .bracketBlock,
            hintFragment: "[] block"
        )
        bindTextObject(
            [.character("a"), .character("<")],
            scope: .around,
            kind: .angleBlock,
            hintFragment: "<> block"
        )
        bindTextObject(
            [.character("a"), .character(">")],
            scope: .around,
            kind: .angleBlock,
            hintFragment: "<> block"
        )
        bindTextObject(
            [.character("a"), .character("t")],
            scope: .around,
            kind: .tagBlock,
            hintFragment: "tag block"
        )
        bindTextObject(
            [.character("a"), .character("\"")],
            scope: .around,
            kind: .doubleQuote,
            hintFragment: "double-quoted string"
        )
        bindTextObject(
            [.character("a"), .character("'")],
            scope: .around,
            kind: .singleQuote,
            hintFragment: "single-quoted string"
        )
        bindTextObject(
            [.character("a"), .character("`")],
            scope: .around,
            kind: .backtickQuote,
            hintFragment: "backtick string"
        )

        builder.describeGroup([.character("i")], label: "Inner")
        bindTextObject(
            [.character("i"), .character("w")],
            scope: .inner,
            kind: .word,
            hintFragment: "word"
        )
        bindTextObject(
            [.character("i"), .character("W")],
            scope: .inner,
            kind: .wordBig,
            hintFragment: "WORD"
        )
        bindTextObject(
            [.character("i"), .character("s")],
            scope: .inner,
            kind: .sentence,
            hintFragment: "sentence"
        )
        bindTextObject(
            [.character("i"), .character("p")],
            scope: .inner,
            kind: .paragraph,
            hintFragment: "paragraph"
        )
        bindTextObject(
            [.character("i"), .character("b")],
            scope: .inner,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("i"), .character("(")],
            scope: .inner,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("i"), .character(")")],
            scope: .inner,
            kind: .parenBlock,
            hintFragment: "() block"
        )
        bindTextObject(
            [.character("i"), .character("B")],
            scope: .inner,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("i"), .character("{")],
            scope: .inner,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("i"), .character("}")],
            scope: .inner,
            kind: .braceBlock,
            hintFragment: "{} block"
        )
        bindTextObject(
            [.character("i"), .character("[")],
            scope: .inner,
            kind: .bracketBlock,
            hintFragment: "[] block"
        )
        bindTextObject(
            [.character("i"), .character("]")],
            scope: .inner,
            kind: .bracketBlock,
            hintFragment: "[] block"
        )
        bindTextObject(
            [.character("i"), .character("<")],
            scope: .inner,
            kind: .angleBlock,
            hintFragment: "<> block"
        )
        bindTextObject(
            [.character("i"), .character(">")],
            scope: .inner,
            kind: .angleBlock,
            hintFragment: "<> block"
        )
        bindTextObject(
            [.character("i"), .character("t")],
            scope: .inner,
            kind: .tagBlock,
            hintFragment: "tag block"
        )
        bindTextObject(
            [.character("i"), .character("\"")],
            scope: .inner,
            kind: .doubleQuote,
            hintFragment: "double-quoted string"
        )
        bindTextObject(
            [.character("i"), .character("'")],
            scope: .inner,
            kind: .singleQuote,
            hintFragment: "single-quoted string"
        )
        bindTextObject(
            [.character("i"), .character("`")],
            scope: .inner,
            kind: .backtickQuote,
            hintFragment: "backtick string"
        )

        return builder.build()
    }

    static let normalModeDeleteOperator = normalMode(repeatedKey: "d")
    static let normalModeChangeOperator = normalMode(repeatedKey: "c")
    static let normalModeYankOperator = normalMode(repeatedKey: "y")
}
