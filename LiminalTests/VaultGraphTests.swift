import CambiumCore
import Foundation
import Testing
@testable import Liminal

@Suite("VaultGraph")
@MainActor
struct VaultGraphTests {
    @Test("undirected edges dedupe across A→B and B→A")
    func edgeDedup() {
        let a = URL(fileURLWithPath: "/v/A.lim")
        let b = URL(fileURLWithPath: "/v/B.lim")
        #expect(VaultGraph.Edge(a, b) == VaultGraph.Edge(b, a))
        #expect(Set([VaultGraph.Edge(a, b), VaultGraph.Edge(b, a)]).count == 1)
    }

    @Test("full mode includes every note and resolved cross-doc edge")
    func fullModeBasics() throws {
        let entry = try makeEntry(notes: [
            ("Source.lim", "[[Target]] and [[Other]]"),
            ("Target.lim", ""),
            ("Other.lim", "[[Source]]"),
            ("Lonely.lim", "no links")
        ])

        let graph = VaultGraph.build(from: entry, mode: .full)

        #expect(graph.nodes.count == 4)
        #expect(graph.nodes.contains { $0.label == "Lonely" })

        let labelsForEdges = graph.edges.map { edge in
            Set([edge.nodeA.lastPathComponent, edge.nodeB.lastPathComponent])
        }
        #expect(labelsForEdges.contains(["Source.lim", "Target.lim"]))
        #expect(labelsForEdges.contains(["Source.lim", "Other.lim"]))
        // The reverse `Other → Source` collapses with `Source → Other`.
        #expect(graph.edges.count == 2)
    }

    @Test("full mode skips unresolved targets")
    func fullModeSkipsUnresolved() throws {
        let entry = try makeEntry(notes: [
            ("Source.lim", "[[DoesNotExist]]")
        ])
        let graph = VaultGraph.build(from: entry, mode: .full)
        #expect(graph.nodes.count == 1)
        #expect(graph.edges.isEmpty)
    }

    @Test("neighbors mode = center + outgoing targets + incoming sources")
    func neighborsMode() throws {
        let entry = try makeEntry(notes: [
            ("Center.lim", "[[Outbound]]"),
            ("Outbound.lim", ""),
            ("Inbound.lim", "[[Center]]"),
            ("Far.lim", "[[Inbound]]"),
            ("Lonely.lim", "")
        ])

        let centerURL = entry.rootURL.appendingPathComponent("Center.lim")
        let canonicalCenter = VaultRegistry.canonicalNoteURL(for: centerURL)
        let graph = VaultGraph.build(from: entry, mode: .neighbors(canonicalCenter))

        let nodeNames = Set(graph.nodes.map(\.label))
        #expect(nodeNames == ["Center", "Outbound", "Inbound"])
        // Far.lim links to Inbound (an incoming source of Center) but
        // is two hops away — should NOT appear in the neighbors view.
        #expect(!nodeNames.contains("Far"))
        #expect(!nodeNames.contains("Lonely"))

        // Both edges involve Center.
        for edge in graph.edges {
            #expect(edge.contains(canonicalCenter))
        }
        #expect(graph.edges.count == 2)
    }

    @Test("self-references don't produce a loop edge")
    func selfReferenceFiltered() throws {
        let entry = try makeEntry(notes: [
            ("Self.lim", "[[Self]]")
        ])
        let graph = VaultGraph.build(from: entry, mode: .full)
        #expect(graph.nodes.count == 1)
        #expect(graph.edges.isEmpty)
    }

    @Test("node degree counts edges on each side of an undirected edge")
    func degreeCount() throws {
        let entry = try makeEntry(notes: [
            ("Hub.lim", "[[A]] [[B]] [[C]]"),
            ("A.lim", ""),
            ("B.lim", ""),
            ("C.lim", "")
        ])
        let graph = VaultGraph.build(from: entry, mode: .full)
        let hub = graph.nodes.first { $0.label == "Hub" }
        #expect(hub?.degree == 3)
        for spoke in ["A", "B", "C"] {
            #expect(graph.nodes.first { $0.label == spoke }?.degree == 1)
        }
    }

    private func makeEntry(notes: [(String, String)]) throws -> VaultEntry {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("liminal-graph-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let entry = VaultEntry(rootURL: dir)
        let parser = LiminalParser()
        for (name, content) in notes {
            let url = dir.appendingPathComponent(name)
            try content.data(using: .utf8)!.write(to: url)
            let parsed = try parser.parse(content)
            entry.indexCurrentDocument(url, rootSyntax: parsed.rootSyntax, content: content)
        }
        return entry
    }
}
