import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Force-directed graph view of a vault. Two display modes: the full
/// vault (every note + every resolved cross-doc reference) and the
/// neighbors-only view of a chosen center note.
///
/// Click a node → navigate to that note (via `NavigationRouter`) and
/// adopt it as the new center. Drag a node → pin it under the cursor
/// while the rest of the graph adjusts.
///
/// Compact layout: designed for the sidebar's narrow column. Mode
/// picker stacks above the canvas; center picker (Neighbors only)
/// shows on a second row; node/edge counts live in a footer strip.
struct VaultGraphView: View {
    @ObservedObject var entry: VaultEntry

    /// The active note for this tab, sourced from `WorkspaceTab.fileURL`
    /// via the prop chain `WorkspaceSidebar → VaultSidebarView →
    /// VaultGraphView`. The graph's blue "selected" highlight and
    /// Neighbors-mode pivot read from this directly — they do NOT
    /// shadow it with local @State, because that's the bug we just
    /// fixed. Writes go through `NavigationRouter`, which loops back
    /// here by updating the tab's `fileURL`.
    let currentDocURL: URL?

    @StateObject private var simulator = GraphSimulator()
    @State private var modeKind: ModeKind = .full

    // Drag state. `draggedNode` is set while the cursor is on a node;
    // its position is pinned in the simulation and updated to follow
    // the cursor (offset by `dragOffset` so the grab point stays
    // under the pointer).
    @State private var draggedNode: URL?
    @State private var dragOffset: CGSize = .zero
    @State private var dragLocation: CGPoint?

    private enum ModeKind: String, CaseIterable, Identifiable {
        case full = "Full"
        case neighbors = "Neighbors"
        var id: String { rawValue }
    }

    /// Active center: whatever note the editor is focused on for this
    /// tab. Falls back to the alphabetically-first note only on cold
    /// start, when no document is loaded yet — keeps Neighbors mode
    /// always-meaningful. No local override; see the doc on
    /// `currentDocURL` for why.
    private var resolvedCenterURL: URL? {
        if let currentDocURL {
            return VaultRegistry.canonicalNoteURL(for: currentDocURL)
        }
        return entry.notes.keys.min { $0.absoluteString < $1.absoluteString }
    }

    private var mode: VaultGraph.Mode {
        switch modeKind {
        case .full:
            return .full
        case .neighbors:
            if let url = resolvedCenterURL {
                return .neighbors(url)
            }
            return .full
        }
    }

    private var graph: VaultGraph {
        VaultGraph.build(from: entry, mode: mode)
    }

    var body: some View {
        let currentGraph = graph
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas(graph: currentGraph)
            Divider()
            footer(graph: currentGraph)
        }
    }

    // MARK: - Toolbar (compact, multi-row for sidebar width)

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Mode", selection: $modeKind) {
                ForEach(ModeKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if modeKind == .neighbors {
                centerPicker
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var centerPicker: some View {
        let sorted = entry.notes.values.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath)
                == .orderedAscending
        }
        return HStack(spacing: 6) {
            Text("Center")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Center", selection: Binding(
                get: { resolvedCenterURL },
                // Picking a center is conceptually identical to clicking
                // a node — both should set the active note for the tab.
                // Route through NavigationRouter so the editor follows
                // and the graph re-reads its center from the prop.
                set: { newURL in
                    guard let newURL else { return }
                    NavigationRouter.shared.navigate(
                        to: newURL,
                        anchor: nil,
                        disposition: .replaceInCurrentTab
                    )
                }
            )) {
                ForEach(sorted) { note in
                    Text(note.relativePathWithoutExtension)
                        .tag(URL?.some(note.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func footer(graph: VaultGraph) -> some View {
        HStack {
            Text("\(graph.nodes.count) nodes · \(graph.edges.count) edges")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Canvas

    private func canvas(graph: VaultGraph) -> some View {
        GeometryReader { geom in
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))

                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    Canvas(opaque: true, rendersAsynchronously: false) { ctx, size in
                        draw(ctx: ctx, size: size, graph: graph)
                    }
                    .onChange(of: context.date) { _, _ in
                        let pinned: Set<URL>
                        if let id = draggedNode {
                            pinned = [id]
                            if let target = dragLocation {
                                simulator.setPosition(target, for: id)
                            }
                        } else {
                            pinned = []
                        }
                        simulator.tick(
                            graph: graph,
                            viewportSize: geom.size,
                            pinned: pinned
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewportSize: geom.size))
            .onAppear {
                simulator.adopt(graph: graph, viewportSize: geom.size)
            }
            .onChange(of: graph) { _, newGraph in
                simulator.adopt(graph: newGraph, viewportSize: geom.size)
            }
        }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if draggedNode == nil {
                    if let id = simulator.nodeAt(
                        value.startLocation,
                        tolerance: hitTolerance
                    ),
                    let pos = simulator.position(for: id) {
                        draggedNode = id
                        dragOffset = CGSize(
                            width: pos.x - value.startLocation.x,
                            height: pos.y - value.startLocation.y
                        )
                    }
                }
                if draggedNode != nil {
                    dragLocation = CGPoint(
                        x: value.location.x + dragOffset.width,
                        y: value.location.y + dragOffset.height
                    )
                    simulator.wakeUp()
                }
            }
            .onEnded { value in
                let traveled = hypot(value.translation.width, value.translation.height)
                let target = draggedNode
                draggedNode = nil
                dragLocation = nil
                dragOffset = .zero

                // Treat near-zero motion as a tap. Either the user
                // tapped on a node (`target` was set in onChanged)
                // or tapped empty space (no-op).
                if traveled < 4, let id = target {
                    handleTap(on: id)
                }
            }
    }

    /// Tap: navigate. The blue highlight + neighbor pivot follow
    /// automatically because `resolvedCenterURL` reads from
    /// `currentDocURL`, which the navigation will update via the
    /// tab's `fileURL`. No local-state bookkeeping needed.
    private func handleTap(on url: URL) {
        NavigationRouter.shared.navigate(
            to: url,
            anchor: nil,
            disposition: NavigationDisposition.click()
        )
    }

    // MARK: - Drawing

    private var hitTolerance: CGFloat { 14 }

    private func draw(ctx: GraphicsContext, size: CGSize, graph: VaultGraph) {
        let edgeColor = Color(nsColor: .tertiaryLabelColor)
        let nodeColor = Color(nsColor: .secondaryLabelColor)
        let centerColor = Color.accentColor
        let labelColor = Color(nsColor: .labelColor)

        // Edges: one consolidated path stroked once.
        var edgePath = Path()
        for edge in graph.edges {
            guard let a = simulator.position(for: edge.nodeA),
                  let b = simulator.position(for: edge.nodeB)
            else { continue }
            edgePath.move(to: a)
            edgePath.addLine(to: b)
        }
        ctx.stroke(edgePath, with: .color(edgeColor), lineWidth: 1)

        // Nodes — selected/center node highlighted in *both* modes
        // so a click is always a visible action.
        let center = resolvedCenterURL
        for node in graph.nodes {
            guard let pos = simulator.position(for: node.id) else { continue }
            let radius = nodeRadius(for: node)
            let isCenter = (node.id == center)
            let fill = isCenter ? centerColor : nodeColor
            let rect = CGRect(
                x: pos.x - radius,
                y: pos.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        }

        // Labels: only when the graph is small enough to keep the
        // canvas legible. Hover-only labels are a future iteration.
        if graph.nodes.count <= 40 {
            for node in graph.nodes {
                guard let pos = simulator.position(for: node.id) else { continue }
                let radius = nodeRadius(for: node)
                let text = Text(node.label)
                    .font(.system(size: 10))
                    .foregroundColor(labelColor)
                ctx.draw(
                    text,
                    at: CGPoint(x: pos.x, y: pos.y + radius + 8),
                    anchor: .top
                )
            }
        }
    }

    /// Circle radius scales with degree but is clamped so a single
    /// hub node doesn't dwarf everyone else.
    private func nodeRadius(for node: VaultGraph.Node) -> CGFloat {
        4 + CGFloat(min(node.degree, 6))
    }
}

/// Holds the live force-simulation state for one graph view. Not
/// `@Published` for positions — TimelineView re-renders the canvas
/// every frame, and the simulator is read directly during drawing.
/// `objectWillChange` fires only when topology changes (via
/// `graphVersion`) so the parent view triggers re-layout.
@MainActor
final class GraphSimulator: ObservableObject {
    @Published private(set) var graphVersion: Int = 0

    private var positions: [URL: CGPoint] = [:]
    private var velocities: [URL: CGVector] = [:]
    private var settledFrames: Int = 0
    private var lastEdges: Set<VaultGraph.Edge> = []

    private let settings: ForceSimulationSettings

    init(settings: ForceSimulationSettings = ForceSimulationSettings()) {
        self.settings = settings
    }

    /// Reconcile the simulator with a new graph topology.
    /// Existing nodes retain their positions — including nodes that
    /// briefly disappeared (e.g., during a Neighbors→Full→Neighbors
    /// pivot), so toggling modes never reshuffles layout.
    ///
    /// New nodes are placed in a small disc around the *center* node
    /// (Neighbors mode) or the viewport middle (Full mode). The
    /// neighbor-pivot case feels cohesive: when the user clicks
    /// note B, B's previously-unseen neighbors emanate from B
    /// rather than appearing at random spots in the canvas.
    func adopt(graph: VaultGraph, viewportSize: CGSize) {
        let knownIDs = Set(positions.keys)
        let graphIDs = Set(graph.nodes.map(\.id))

        let viewportCenter = CGPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        )
        let placementOrigin: CGPoint = {
            if case .neighbors(let centerURL) = graph.mode,
               let centerPos = positions[centerURL] {
                return centerPos
            }
            return viewportCenter
        }()

        var added = false
        for id in graphIDs.subtracting(knownIDs) {
            let angle = Double.random(in: 0..<(2 * .pi))
            let radius = Double.random(in: 50...100)
            positions[id] = CGPoint(
                x: placementOrigin.x + CGFloat(cos(angle) * radius),
                y: placementOrigin.y + CGFloat(sin(angle) * radius)
            )
            velocities[id] = .zero
            added = true
        }

        let newEdges = Set(graph.edges)
        if added || newEdges != lastEdges {
            settledFrames = 0
        }
        lastEdges = newEdges
        graphVersion &+= 1
    }

    var isConverged: Bool {
        settledFrames >= settings.convergenceFrames
    }

    /// Advance one physics tick. No-op once converged so we don't
    /// burn CPU on a settled graph.
    func tick(graph: VaultGraph, viewportSize: CGSize, pinned: Set<URL>) {
        if isConverged && pinned.isEmpty { return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let result = ForceSimulation.step(
            nodes: graph.nodes,
            edges: graph.edges,
            positions: positions,
            velocities: velocities,
            pinned: pinned,
            center: center,
            settings: settings
        )
        positions = result.positions
        velocities = result.velocities
        if result.maxSpeed < settings.convergenceThreshold {
            settledFrames += 1
        } else {
            settledFrames = 0
        }
    }

    /// Reset convergence so the simulation will keep stepping. Use
    /// when the user grabs a node — the rest of the graph needs to
    /// react.
    func wakeUp() {
        settledFrames = 0
    }

    func position(for id: URL) -> CGPoint? {
        positions[id]
    }

    func setPosition(_ pos: CGPoint, for id: URL) {
        positions[id] = pos
        velocities[id] = .zero
    }

    /// Hit test: nearest node within `tolerance` pt of `point`, or
    /// nil if none. Uses straight-line distance over the canvas;
    /// good enough since node circles are small.
    func nodeAt(_ point: CGPoint, tolerance: CGFloat) -> URL? {
        var best: (id: URL, dist: CGFloat)?
        for (id, pos) in positions {
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist <= tolerance,
               dist < (best?.dist ?? .greatestFiniteMagnitude) {
                best = (id, dist)
            }
        }
        return best?.id
    }
}
