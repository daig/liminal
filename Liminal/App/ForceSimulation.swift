import CoreGraphics
import Foundation

/// Tunable physics constants for the graph layout. Defaults are
/// hand-calibrated for nodes that should settle ~80pt apart along
/// edges, with viewport sized for a few hundred nodes.
public struct ForceSimulationSettings: Sendable, Equatable {
    /// Coulomb-like repulsion: `F = repulsion / d²`. Higher → more
    /// space between nodes.
    public var repulsion: Double = 4000

    /// Hooke spring along each edge: `F = attraction × (d − rest)`.
    /// Higher → faster settle to `restLength`.
    public var attraction: Double = 0.04

    /// Equilibrium edge distance.
    public var restLength: Double = 80

    /// Linear pull toward the viewport center: `F = gravity × (pos − center)`.
    /// Prevents disconnected clusters from drifting off-screen.
    public var centerGravity: Double = 0.005

    /// Multiplied into velocity each step. <1 prevents oscillation;
    /// 0.85 gives a fast-but-overshootable feel.
    public var damping: Double = 0.85

    /// Velocity magnitude clamp. Without this, two close nodes can
    /// blow apart at light-speed before damping catches them.
    public var maxVelocity: Double = 30

    /// Floor for distance in the repulsion divisor — guards against
    /// 1/0 when two nodes occupy the same point on first frame.
    public var minDistance: Double = 5

    /// Integration timestep. Bumping this above 1.0 makes the
    /// simulation feel "snappier" but risks overshoot.
    public var dt: Double = 1.0

    /// Max-velocity threshold below which we consider a frame "at rest."
    public var convergenceThreshold: Double = 0.1

    /// Consecutive frames at rest before the simulation declares
    /// itself converged (so the view can stop ticking physics).
    public var convergenceFrames: Int = 10

    public init() {}
}

public struct ForceSimulationStep: Equatable {
    public let positions: [URL: CGPoint]
    public let velocities: [URL: CGVector]
    /// Largest per-node speed produced by this step. The caller
    /// uses this for convergence detection.
    public let maxSpeed: Double
}

/// Pure one-step force simulator. Pulled out of the SwiftUI view so
/// the physics is unit-testable without spinning the runloop.
public enum ForceSimulation {
    public static func step(
        nodes: [VaultGraph.Node],
        edges: [VaultGraph.Edge],
        positions: [URL: CGPoint],
        velocities: [URL: CGVector],
        pinned: Set<URL>,
        center: CGPoint,
        settings: ForceSimulationSettings = ForceSimulationSettings()
    ) -> ForceSimulationStep {
        // Accumulator initialized to zero for every node we know about.
        var forces = [URL: CGVector](minimumCapacity: nodes.count)
        for node in nodes { forces[node.id] = .zero }

        // O(n²) pairwise repulsion. Acceptable up to ~500 nodes;
        // beyond that we'd want a Barnes-Hut quadtree.
        let nodeCount = nodes.count
        if nodeCount > 1 {
            for i in 0..<nodeCount {
                let aURL = nodes[i].id
                guard let pa = positions[aURL] else { continue }
                for j in (i + 1)..<nodeCount {
                    let bURL = nodes[j].id
                    guard let pb = positions[bURL] else { continue }
                    let dx = Double(pa.x - pb.x)
                    let dy = Double(pa.y - pb.y)
                    let dist2 = max(dx * dx + dy * dy,
                                    settings.minDistance * settings.minDistance)
                    let dist = dist2.squareRoot()
                    let mag = settings.repulsion / dist2
                    let fx = (dx / dist) * mag
                    let fy = (dy / dist) * mag
                    forces[aURL, default: .zero].dx += fx
                    forces[aURL, default: .zero].dy += fy
                    forces[bURL, default: .zero].dx -= fx
                    forces[bURL, default: .zero].dy -= fy
                }
            }
        }

        // Spring attraction along each edge.
        for edge in edges {
            guard let pa = positions[edge.nodeA],
                  let pb = positions[edge.nodeB]
            else { continue }
            let dx = Double(pa.x - pb.x)
            let dy = Double(pa.y - pb.y)
            let dist = max((dx * dx + dy * dy).squareRoot(), settings.minDistance)
            let stretch = dist - settings.restLength
            let mag = settings.attraction * stretch
            let fx = (dx / dist) * mag
            let fy = (dy / dist) * mag
            // Pull endpoints toward each other when stretched
            // (positive `stretch`), push apart when compressed.
            forces[edge.nodeA, default: .zero].dx -= fx
            forces[edge.nodeA, default: .zero].dy -= fy
            forces[edge.nodeB, default: .zero].dx += fx
            forces[edge.nodeB, default: .zero].dy += fy
        }

        // Linear pull toward `center`.
        for node in nodes {
            guard let p = positions[node.id] else { continue }
            forces[node.id, default: .zero].dx -= settings.centerGravity
                * Double(p.x - center.x)
            forces[node.id, default: .zero].dy -= settings.centerGravity
                * Double(p.y - center.y)
        }

        // Integrate: update velocity (with damping + clamp) and
        // position, except for pinned nodes which don't move and
        // have their velocity zeroed.
        var newVel = velocities
        var newPos = positions
        var maxSpeed: Double = 0

        for node in nodes {
            let id = node.id
            if pinned.contains(id) {
                newVel[id] = .zero
                continue
            }
            let force = forces[id] ?? .zero
            var vel = newVel[id] ?? .zero
            vel.dx = (vel.dx + force.dx * settings.dt) * settings.damping
            vel.dy = (vel.dy + force.dy * settings.dt) * settings.damping
            let speed = (vel.dx * vel.dx + vel.dy * vel.dy).squareRoot()
            if speed > settings.maxVelocity {
                let scale = settings.maxVelocity / speed
                vel.dx *= scale
                vel.dy *= scale
            }
            newVel[id] = vel

            if var p = newPos[id] {
                p.x += vel.dx * settings.dt
                p.y += vel.dy * settings.dt
                newPos[id] = p
            }
            let finalSpeed = (vel.dx * vel.dx + vel.dy * vel.dy).squareRoot()
            if finalSpeed > maxSpeed { maxSpeed = finalSpeed }
        }

        return ForceSimulationStep(
            positions: newPos,
            velocities: newVel,
            maxSpeed: maxSpeed
        )
    }
}
