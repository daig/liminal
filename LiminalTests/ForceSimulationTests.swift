import CoreGraphics
import Foundation
import Testing
@testable import Liminal

@Suite("ForceSimulation")
struct ForceSimulationTests {
    @Test("pinned node has zero velocity after a step and never moves")
    func pinnedNodeStaysPut() {
        let a = url("A")
        let b = url("B")
        let nodes = [node(a), node(b)]
        let edges = [VaultGraph.Edge(a, b)]
        let positions: [URL: CGPoint] = [
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 400, y: 100)
        ]
        let velocities: [URL: CGVector] = [a: .zero, b: .zero]

        var pos = positions
        var vel = velocities
        for _ in 0..<50 {
            let step = ForceSimulation.step(
                nodes: nodes, edges: edges,
                positions: pos, velocities: vel,
                pinned: [a],
                center: CGPoint(x: 250, y: 250)
            )
            pos = step.positions
            vel = step.velocities
        }

        #expect(pos[a] == CGPoint(x: 100, y: 100))
        #expect(vel[a] == .zero)
    }

    @Test("two connected nodes converge close to restLength")
    func twoNodesConvergeToRestLength() {
        let a = url("A")
        let b = url("B")
        let nodes = [node(a), node(b)]
        let edges = [VaultGraph.Edge(a, b)]
        var pos: [URL: CGPoint] = [
            a: CGPoint(x: 200, y: 250),
            b: CGPoint(x: 500, y: 250)
        ]
        var vel: [URL: CGVector] = [a: .zero, b: .zero]
        let center = CGPoint(x: 350, y: 250)
        var settings = ForceSimulationSettings()
        settings.restLength = 100

        for _ in 0..<400 {
            let step = ForceSimulation.step(
                nodes: nodes, edges: edges,
                positions: pos, velocities: vel,
                pinned: [],
                center: center,
                settings: settings
            )
            pos = step.positions
            vel = step.velocities
        }

        let pa = pos[a]!
        let pb = pos[b]!
        let dist = hypot(Double(pa.x - pb.x), Double(pa.y - pb.y))
        // Equilibrium isn't exactly restLength because center
        // gravity also pulls; expect within ±20% of restLength.
        #expect(dist > 70)
        #expect(dist < 130)
    }

    @Test("disconnected far nodes stay near the center after many steps")
    func centerGravityBoundsDisconnectedNodes() {
        let a = url("Far")
        let nodes = [node(a)]
        let center = CGPoint(x: 0, y: 0)
        var pos: [URL: CGPoint] = [a: CGPoint(x: 1000, y: 1000)]
        var vel: [URL: CGVector] = [a: .zero]

        for _ in 0..<300 {
            let step = ForceSimulation.step(
                nodes: nodes, edges: [],
                positions: pos, velocities: vel,
                pinned: [], center: center
            )
            pos = step.positions
            vel = step.velocities
        }

        let p = pos[a]!
        let dist = hypot(Double(p.x), Double(p.y))
        // Far drift is curtailed by center gravity — should be
        // dragged inside ~200pt of origin within 300 steps.
        #expect(dist < 200)
    }

    @Test("max speed strictly bounded by maxVelocity")
    func maxVelocityClamp() {
        let a = url("A")
        let b = url("B")
        // Place two nodes very close → huge repulsion next step.
        let pos: [URL: CGPoint] = [
            a: CGPoint(x: 0, y: 0),
            b: CGPoint(x: 0.5, y: 0)
        ]
        let vel: [URL: CGVector] = [a: .zero, b: .zero]
        var settings = ForceSimulationSettings()
        settings.maxVelocity = 5

        let step = ForceSimulation.step(
            nodes: [node(a), node(b)],
            edges: [],
            positions: pos, velocities: vel,
            pinned: [], center: .zero,
            settings: settings
        )
        #expect(step.maxSpeed <= settings.maxVelocity + 1e-6)
    }

    @Test("step is pure: same input → same output")
    func deterministic() {
        let a = url("A")
        let b = url("B")
        let nodes = [node(a), node(b)]
        let edges = [VaultGraph.Edge(a, b)]
        let pos: [URL: CGPoint] = [
            a: CGPoint(x: 10, y: 10),
            b: CGPoint(x: 200, y: 200)
        ]
        let vel: [URL: CGVector] = [a: .zero, b: .zero]
        let center = CGPoint(x: 100, y: 100)

        let s1 = ForceSimulation.step(
            nodes: nodes, edges: edges,
            positions: pos, velocities: vel,
            pinned: [], center: center
        )
        let s2 = ForceSimulation.step(
            nodes: nodes, edges: edges,
            positions: pos, velocities: vel,
            pinned: [], center: center
        )
        #expect(s1 == s2)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/v/\(name).lim")
    }

    private func node(_ url: URL) -> VaultGraph.Node {
        VaultGraph.Node(
            id: url,
            label: (url.lastPathComponent as NSString).deletingPathExtension,
            degree: 1
        )
    }
}
