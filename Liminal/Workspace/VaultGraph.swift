import Foundation

/// Snapshot of the vault as a graph of notes (nodes) and resolved
/// references (undirected edges, deduped). Built from a `VaultEntry`
/// — same `linkIndex` data the navigator and backlinks panel
/// observe, so the graph is automatically live as the user edits.
public struct VaultGraph: Sendable, Equatable {
    public let nodes: [Node]
    public let edges: [Edge]
    public let mode: Mode

    public struct Node: Sendable, Equatable, Hashable, Identifiable {
        public let id: URL
        public let label: String
        /// Number of edges this node participates in. Used by the
        /// renderer to scale circle radius.
        public let degree: Int
    }

    /// Undirected edge: endpoints are sorted by absoluteString so
    /// `Edge(a, b) == Edge(b, a)` and `Hashable` collapses
    /// duplicate references between the same pair.
    public struct Edge: Sendable, Equatable, Hashable {
        public let nodeA: URL
        public let nodeB: URL

        public init(_ first: URL, _ second: URL) {
            if first.absoluteString <= second.absoluteString {
                self.nodeA = first
                self.nodeB = second
            } else {
                self.nodeA = second
                self.nodeB = first
            }
        }

        public func contains(_ url: URL) -> Bool {
            url == nodeA || url == nodeB
        }

        public func other(than url: URL) -> URL? {
            if url == nodeA { return nodeB }
            if url == nodeB { return nodeA }
            return nil
        }
    }

    public enum Mode: Sendable, Equatable, Hashable {
        case full
        case neighbors(URL)
    }

    public static let empty = VaultGraph(nodes: [], edges: [], mode: .full)

    public init(nodes: [Node], edges: [Edge], mode: Mode) {
        self.nodes = nodes
        self.edges = edges
        self.mode = mode
    }

    @MainActor
    public static func build(from entry: VaultEntry, mode: Mode) -> VaultGraph {
        switch mode {
        case .full:
            return buildFull(entry: entry)
        case .neighbors(let centerURL):
            return buildNeighbors(entry: entry, centerURL: centerURL)
        }
    }

    @MainActor
    private static func buildFull(entry: VaultEntry) -> VaultGraph {
        var edgeSet: Set<Edge> = []
        for sourceURL in entry.notes.keys {
            for ref in entry.linkIndex.outgoing(for: sourceURL) {
                guard let targetURL = recipient(of: ref) else { continue }
                guard sourceURL != targetURL else { continue }
                edgeSet.insert(Edge(sourceURL, targetURL))
            }
        }

        let nodes = makeNodes(
            urls: Set(entry.notes.keys),
            edges: edgeSet,
            entry: entry
        )
        let edges = edgeSet.sorted { lhs, rhs in
            (lhs.nodeA.absoluteString, lhs.nodeB.absoluteString)
                < (rhs.nodeA.absoluteString, rhs.nodeB.absoluteString)
        }
        return VaultGraph(nodes: nodes, edges: edges, mode: .full)
    }

    @MainActor
    private static func buildNeighbors(entry: VaultEntry, centerURL: URL) -> VaultGraph {
        var nodeURLs: Set<URL> = [centerURL]
        var edgeSet: Set<Edge> = []

        for ref in entry.linkIndex.outgoing(for: centerURL) {
            guard let targetURL = recipient(of: ref) else { continue }
            guard centerURL != targetURL else { continue }
            nodeURLs.insert(targetURL)
            edgeSet.insert(Edge(centerURL, targetURL))
        }

        for ref in entry.linkIndex.backlinks(for: centerURL) {
            let sourceURL = ref.sourceNoteID
            guard centerURL != sourceURL else { continue }
            nodeURLs.insert(sourceURL)
            edgeSet.insert(Edge(sourceURL, centerURL))
        }

        let nodes = makeNodes(urls: nodeURLs, edges: edgeSet, entry: entry)
        let edges = edgeSet.sorted { lhs, rhs in
            (lhs.nodeA.absoluteString, lhs.nodeB.absoluteString)
                < (rhs.nodeA.absoluteString, rhs.nodeB.absoluteString)
        }
        return VaultGraph(nodes: nodes, edges: edges, mode: .neighbors(centerURL))
    }

    @MainActor
    private static func makeNodes(
        urls: Set<URL>,
        edges: Set<Edge>,
        entry: VaultEntry
    ) -> [Node] {
        var degreeByURL: [URL: Int] = [:]
        for edge in edges {
            degreeByURL[edge.nodeA, default: 0] += 1
            degreeByURL[edge.nodeB, default: 0] += 1
        }

        return urls
            .map { url in
                let label = entry.notes[url]?.title
                    ?? (url.lastPathComponent as NSString).deletingPathExtension
                return Node(id: url, label: label, degree: degreeByURL[url] ?? 0)
            }
            .sorted { $0.id.absoluteString < $1.id.absoluteString }
    }

    /// Extract the recipient URL from a `ResolvedReference`'s
    /// resolution. `.unresolved` and `.ambiguous` produce no edge —
    /// the graph reflects what actually links, not what's pending
    /// disambiguation.
    private static func recipient(of reference: ResolvedReference) -> URL? {
        switch reference.resolution {
        case .resolved(let destination):
            return destination.noteID
        case .noteResolved(let noteID, _):
            return noteID
        case .unresolved, .ambiguous:
            return nil
        }
    }
}
