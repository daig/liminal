import Foundation

/// One row in the project navigator's file tree. Either a folder
/// (carries `children`, `url == nil`) or a file (`url` set,
/// `children == nil`). The `id` is the canonical path string so
/// SwiftUI's `OutlineGroup` keeps stable identity across re-renders.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL?
    public let children: [FileTreeNode]?

    public init(id: String, name: String, url: URL?, children: [FileTreeNode]?) {
        self.id = id
        self.name = name
        self.url = url
        self.children = children
    }

    public var isFolder: Bool { url == nil }
}

/// Pure function: turn a flat list of note URLs (all under
/// `vaultRoot`) into a hierarchical tree sorted folders-first,
/// alphabetical within groups. URLs not under `vaultRoot` are
/// dropped — the caller is expected to canonicalize before calling.
public enum FileTreeBuilder {
    public static func build(noteURLs: [URL], vaultRoot: URL) -> [FileTreeNode] {
        let root = MutableNode(name: "", path: "")
        let rootPath = vaultRoot.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        for url in noteURLs {
            let path = url.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            let components = relative.split(separator: "/").map(String.init)
            insert(url: url, components: components, parentPath: "", into: root)
        }

        return root.children
            .map { $0.toNode() }
            .sorted(by: nodeOrdering)
    }

    private static func insert(
        url: URL,
        components: [String],
        parentPath: String,
        into node: MutableNode
    ) {
        guard let first = components.first else { return }
        let myPath = parentPath.isEmpty ? first : parentPath + "/" + first

        if components.count == 1 {
            node.children.append(MutableNode(name: first, path: myPath, url: url))
            return
        }

        let folder: MutableNode
        if let existing = node.children.first(where: { $0.url == nil && $0.name == first }) {
            folder = existing
        } else {
            folder = MutableNode(name: first, path: myPath)
            node.children.append(folder)
        }
        insert(
            url: url,
            components: Array(components.dropFirst()),
            parentPath: myPath,
            into: folder
        )
    }

    /// Folders before files; alphabetical within each group, case-
    /// insensitive so capitalization quirks don't reorder rows.
    private static func nodeOrdering(_ a: FileTreeNode, _ b: FileTreeNode) -> Bool {
        switch (a.isFolder, b.isFolder) {
        case (true, false): return true
        case (false, true): return false
        default:
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Mutable scratch type used during construction; final output
    /// is the immutable `FileTreeNode` value type.
    private final class MutableNode {
        let name: String
        let path: String
        let url: URL?
        var children: [MutableNode] = []

        init(name: String, path: String, url: URL? = nil) {
            self.name = name
            self.path = path
            self.url = url
        }

        func toNode() -> FileTreeNode {
            FileTreeNode(
                id: path,
                name: name,
                url: url,
                children: url == nil
                    ? children.map { $0.toNode() }.sorted(by: FileTreeBuilder.nodeOrdering)
                    : nil
            )
        }
    }
}
