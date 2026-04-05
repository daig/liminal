import Foundation

enum VimHintItemKind: Equatable {
    case action
    case group
    case argument
}

struct VimHintItem: Equatable, Identifiable {
    let key: String
    let description: String
    let kind: VimHintItemKind
    let tint: VimDisplayTint?

    var id: String {
        "\(key)|\(description)|\(String(describing: kind))|\(String(describing: tint))"
    }
}

enum VimDynamicHintOptionsSource: Hashable {
    case localMarks
}

struct VimHintContext {
    static let empty = VimHintContext()

    var dynamicOptions: [VimDynamicHintOptionsSource: [VimHintItem]] = [:]

    func items(for source: VimDynamicHintOptionsSource) -> [VimHintItem] {
        dynamicOptions[source] ?? []
    }
}

enum VimHintArgumentPresentation {
    case placeholder(VimHintItem)
    case fixed([VimHintItem], fallback: VimHintItem? = nil)
    case dynamic(VimDynamicHintOptionsSource, fallback: VimHintItem? = nil)

    func items(in context: VimHintContext) -> [VimHintItem] {
        switch self {
        case .placeholder(let item):
            return [item]
        case .fixed(let items, let fallback):
            return items.isEmpty ? fallback.map { [$0] } ?? [] : items
        case .dynamic(let source, let fallback):
            let items = context.items(for: source)
            return items.isEmpty ? fallback.map { [$0] } ?? [] : items
        }
    }
}

struct VimHintSnapshot: Equatable {
    let title: String
    let items: [VimHintItem]
}

enum VimHintSource: Equatable {
    case pendingPrefix
    case rootHelp
}

struct VimHintCandidate: Equatable {
    let snapshot: VimHintSnapshot
    let source: VimHintSource
}

struct VimKeymapCatalog {
    let commandBindings: VimBindingTree
    let operatorMotionBindings: [VimOperator: VimOperatorMotionBindingTree]

    static let normalMode: VimKeymapCatalog = {
        VimKeymapCatalog(
            commandBindings: .normalMode,
            operatorMotionBindings: [
                .delete: .normalModeDeleteOperator,
                .change: .normalModeChangeOperator,
                .yank: .normalModeYankOperator,
            ]
        )
    }()

    func rootHintCandidate(in context: VimHintContext = .empty) -> VimHintCandidate {
        VimHintCandidate(
            snapshot: commandBindings.hintSnapshot(
                at: [],
                titlePrefix: "Commands",
                argumentPending: false,
                context: context
            ) ?? VimHintSnapshot(title: "Commands", items: []),
            source: .rootHelp
        )
    }

    func hintCandidate(
        for sessionState: VimSessionState,
        in context: VimHintContext = .empty
    ) -> VimHintCandidate? {
        guard sessionState.mode == .normal else { return nil }

        if let pendingOperator = sessionState.pendingOperator {
            guard let bindingTree = operatorMotionBindings[pendingOperator] else {
                return nil
            }

            guard
                let snapshot = bindingTree.hintSnapshot(
                    at: sessionState.pendingKeys,
                    titlePrefix: pendingOperator.displayLabel,
                    argumentPending: sessionState.pendingCharacterOperatorMotionFactory != nil,
                    context: context
                )
            else {
                return nil
            }

            return VimHintCandidate(snapshot: snapshot, source: .pendingPrefix)
        }

        let hasCommandPrefix =
            !sessionState.pendingKeys.isEmpty
            || sessionState.pendingCharacterCommandFactory != nil
        guard hasCommandPrefix else { return nil }

        guard
            let snapshot = commandBindings.hintSnapshot(
                at: sessionState.pendingKeys,
                titlePrefix: nil,
                argumentPending: sessionState.pendingCharacterCommandFactory != nil,
                context: context
            )
        else {
            return nil
        }

        return VimHintCandidate(snapshot: snapshot, source: .pendingPrefix)
    }
}

private protocol VimHintQueryableTree {
    associatedtype Node

    var rootNode: Node { get }
    func node(at keys: [VimKeyPress]) -> Node?
}

extension VimBindingTree: VimHintQueryableTree {
    fileprivate var rootNode: Node { root }
}

extension VimOperatorMotionBindingTree: VimHintQueryableTree {
    fileprivate var rootNode: Node { root }
}

private protocol VimHintQueryableNode {
    var hintLabel: String? { get }
    var hintItemKind: VimHintItemKind? { get }
    var argumentPresentation: VimHintArgumentPresentation? { get }
    var childrenKeyOrder: [VimKeyPress] { get }
    func child(for key: VimKeyPress) -> Self?
}

extension VimBindingTree.Node: VimHintQueryableNode {
    fileprivate var childrenKeyOrder: [VimKeyPress] { childOrder }

    fileprivate func child(for key: VimKeyPress) -> VimBindingTree.Node? {
        children[key]
    }
}

extension VimOperatorMotionBindingTree.Node: VimHintQueryableNode {
    fileprivate var childrenKeyOrder: [VimKeyPress] { childOrder }

    fileprivate func child(for key: VimKeyPress) -> VimOperatorMotionBindingTree.Node? {
        children[key]
    }
}

private extension VimHintQueryableTree where Node: VimHintQueryableNode {
    func hintSnapshot(
        at keys: [VimKeyPress],
        titlePrefix: String?,
        argumentPending: Bool,
        context: VimHintContext
    ) -> VimHintSnapshot? {
        guard let node = node(at: keys) else { return nil }

        let items =
            argumentPending
            ? argumentHintItems(for: node, context: context)
            : childHintItems(for: node)

        guard !items.isEmpty else { return nil }

        return VimHintSnapshot(
            title: title(for: keys, titlePrefix: titlePrefix),
            items: items
        )
    }

    private func title(for keys: [VimKeyPress], titlePrefix: String?) -> String {
        var labels: [String] = []

        if let titlePrefix {
            labels.append(titlePrefix)
        }

        var currentNode = rootNode
        for key in keys {
            guard let child = currentNode.child(for: key) else { break }
            currentNode = child

            if let label = currentNode.hintLabel {
                if labels.last != label {
                    labels.append(label)
                }
            }
        }

        if labels.isEmpty {
            return titlePrefix ?? "Commands"
        }

        return labels.joined(separator: " › ")
    }

    private func childHintItems(for node: Node) -> [VimHintItem] {
        node.childrenKeyOrder.compactMap { keyPress in
            guard let child = node.child(for: keyPress) else { return nil }

            return VimHintItem(
                key: keyPress.displayNotation,
                description: child.hintLabel ?? fallbackDescription(for: child),
                kind: child.hintItemKind ?? inferredKind(for: child),
                tint: nil
            )
        }
    }

    private func argumentHintItems(for node: Node, context: VimHintContext) -> [VimHintItem] {
        node.argumentPresentation?.items(in: context) ?? []
    }

    private func fallbackDescription(for node: Node) -> String {
        if !node.childrenKeyOrder.isEmpty {
            return "\(node.childrenKeyOrder.count) commands"
        }

        return "Command"
    }

    private func inferredKind(for node: Node) -> VimHintItemKind {
        node.childrenKeyOrder.isEmpty ? .action : .group
    }
}
