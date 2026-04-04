import Foundation

enum VimSpecialKey: Hashable {
    case escape
    case leftArrow
    case rightArrow
    case downArrow
    case upArrow
}

enum VimKeyPress: Hashable {
    case character(Character)
    case special(VimSpecialKey)
}

enum VimMotion {
    case left
    case right
    case up
    case down
    case wordForward
    case wordBackward
    case paragraphForward
    case paragraphBackward
}

enum VimCommand {
    case enterInsertMode
    case move(VimMotion, count: Int)
}

struct VimSessionState {
    var mode: VimMode = .normal
    var pendingCount: Int?
    var pendingKeys: [VimKeyPress] = []
    var preferredColumn: Int?

    mutating func clearPendingInput() {
        pendingCount = nil
        pendingKeys.removeAll()
    }
}

struct VimBindingTree {
    struct Node {
        var commandFactory: ((Int) -> VimCommand)?
        var children: [VimKeyPress: Node] = [:]
    }

    enum Match {
        case exact((Int) -> VimCommand)
        case partial
        case none
    }

    struct Builder {
        private var root = Node()

        mutating func bind(
            _ sequence: [VimKeyPress], command: @escaping (Int) -> VimCommand
        ) {
            guard !sequence.isEmpty else { return }
            insert(sequence, command: command, at: &root)
        }

        private func insert(
            _ sequence: [VimKeyPress],
            command: @escaping (Int) -> VimCommand,
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

        return node.children.isEmpty ? .none : .partial
    }
}

extension VimBindingTree {
    static let normalMode: VimBindingTree = {
        var builder = Builder()

        builder.bind([.special(.leftArrow)]) { .move(.left, count: $0) }
        builder.bind([.special(.rightArrow)]) { .move(.right, count: $0) }
        builder.bind([.special(.downArrow)]) { .move(.down, count: $0) }
        builder.bind([.special(.upArrow)]) { .move(.up, count: $0) }

        builder.bind([.character("i")]) { _ in .enterInsertMode }
        builder.bind([.character("w")]) { .move(.wordForward, count: $0) }
        builder.bind([.character("b")]) { .move(.wordBackward, count: $0) }
        builder.bind([.character("}")]) { .move(.paragraphForward, count: $0) }
        builder.bind([.character("{")]) { .move(.paragraphBackward, count: $0) }

        return builder.build()
    }()
}
