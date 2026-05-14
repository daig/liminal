import AppKit
import SwiftUI

struct ClipboardInspectorView: View {
    @State private var snapshot = ClipboardInspectorSnapshot.read()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                summary
                Divider()
                structuralDetails
                Divider()
                textPreview
            }
            .padding(12)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: SystemPasteboard.didWriteNotification)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClipboardInspectorRow(label: "Kind", value: snapshot.kindLabel)
            ClipboardInspectorRow(label: "Text", value: snapshot.textByteLabel)
            ClipboardInspectorRow(label: "Change", value: "\(snapshot.changeCount)")
        }
    }

    @ViewBuilder
    private var structuralDetails: some View {
        switch snapshot.structuralPayload {
        case .absent:
            ClipboardInspectorRow(label: "CST", value: "No structural payload")
        case .invalid(let byteCount, let message):
            VStack(alignment: .leading, spacing: 6) {
                ClipboardInspectorRow(label: "CST", value: "\(byteCount) bytes")
                ClipboardInspectorRow(label: "Decode", value: message)
            }
        case .decoded(let info):
            VStack(alignment: .leading, spacing: 6) {
                ClipboardInspectorRow(label: "CST", value: "\(info.payloadByteCount) bytes")
                ClipboardInspectorRow(label: "Wrapper", value: info.wrapperLabel)
                ClipboardInspectorRow(label: "Children", value: info.childKindLabel)
                ClipboardInspectorRow(label: "Adapter", value: info.adapterLabel)
                ClipboardInspectorRow(label: "Project", value: info.projectionLabel)
                ClipboardInspectorRow(label: "Source", value: "\(info.sourceByteCount) bytes")
                ClipboardInspectorRow(label: "Logical", value: "\(info.projectedByteCount) bytes")
            }
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if snapshot.textPreview.isEmpty {
            Text("Clipboard is empty")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(snapshot.textPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refresh() {
        let next = ClipboardInspectorSnapshot.read()
        if next != snapshot {
            snapshot = next
        }
    }
}

private struct ClipboardInspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct ClipboardInspectorSnapshot: Equatable {
    let changeCount: Int
    let entry: VimPasteboardEntry?
    let structuralPayload: StructuralPayload

    static func read() -> ClipboardInspectorSnapshot {
        let entry = SystemPasteboard.read()
        return ClipboardInspectorSnapshot(
            changeCount: SystemPasteboard.pasteboard.changeCount,
            entry: entry,
            structuralPayload: StructuralPayload(entry: entry)
        )
    }

    var kindLabel: String {
        entry?.kind.rawValue ?? "none"
    }

    var textByteLabel: String {
        guard let entry else { return "0 bytes" }
        return "\(entry.text.utf8.count) bytes"
    }

    var textPreview: String {
        guard let text = entry?.text else { return "" }
        return CSTPreview.format(text, max: 320)
    }
}

enum StructuralPayload: Equatable {
    case absent
    case invalid(byteCount: Int, message: String)
    case decoded(StructuralPayloadInfo)

    @MainActor
    init(entry: VimPasteboardEntry?) {
        guard let data = entry?.structuralPayloadData else {
            self = .absent
            return
        }
        do {
            let payload = try StructuralCSTClipboardPayload.decode(data: data)
            self = .decoded(
                StructuralPayloadInfo(
                    payload: payload,
                    payloadByteCount: data.count
                )
            )
        } catch {
            self = .invalid(
                byteCount: data.count,
                message: String(describing: error)
            )
        }
    }
}

struct StructuralPayloadInfo: Equatable {
    let wrapperKind: LiminalKind
    let childKinds: [LiminalKind]
    let sourceByteCount: Int
    let projectedByteCount: Int
    let payloadByteCount: Int
    let projectionKind: StructuralCSTSourceProjection.Kind
    let adapter: StructuralAdapterSupport

    init(payload: StructuralCSTClipboardPayload, payloadByteCount: Int) {
        let fragment = payload.fragment
        self.wrapperKind = fragment.wrapperKind
        self.childKinds = fragment.childKinds
        self.sourceByteCount = fragment.sourceText.utf8.count
        self.projectedByteCount = payload.logicalText.utf8.count
        self.payloadByteCount = payloadByteCount
        self.projectionKind = payload.projection.kind
        self.adapter = StructuralAdapterSupport(payload: payload)
    }

    var wrapperLabel: String {
        wrapperKind.displayName
    }

    var childKindLabel: String {
        childKinds.isEmpty
            ? "none"
            : childKinds.map(\.displayName).joined(separator: ", ")
    }

    var adapterLabel: String {
        adapter.label
    }

    var projectionLabel: String {
        projectionKind.rawValue
    }
}

enum StructuralAdapterSupport: Equatable {
    case rootDocumentItems
    case listItems
    case listItemContent
    case blockQuoteContent
    case unsupported

    init(payload: StructuralCSTClipboardPayload) {
        let fragment = payload.fragment
        let wrapperKind = fragment.wrapperKind
        let childKinds = fragment.childKinds
        if wrapperKind == .listItem,
           payload.projection.kind == .listItemContent {
            self = .listItemContent
            return
        }
        if wrapperKind == .blockQuote,
           payload.projection.kind == .blockQuoteContent {
            self = .blockQuoteContent
            return
        }

        guard !fragment.hasTokenChildren, !childKinds.isEmpty else {
            self = .unsupported
            return
        }
        if wrapperKind == .root,
           childKinds.allSatisfy(Self.isDocumentItemKind)
        {
            self = .rootDocumentItems
        } else if wrapperKind == .list,
                  childKinds.allSatisfy({ $0 == .listItem })
        {
            self = .listItems
        } else {
            self = .unsupported
        }
    }

    var label: String {
        switch self {
        case .rootDocumentItems:
            return "Document item"
        case .listItems:
            return "List item"
        case .listItemContent:
            return "List item content"
        case .blockQuoteContent:
            return "Block quote content"
        case .unsupported:
            return "Unsupported"
        }
    }

    private static func isDocumentItemKind(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .blankLine, .frontmatter, .directive, .schemaBlock,
             .templateBlock, .paragraph, .atxHeading, .thematicBreak,
             .valueDeclaration, .typedBlock, .fencedCodeBlock, .mathBlock,
             .htmlBlock, .commentBlock, .list, .blockQuote, .pipeTable,
             .structuredEmbedBlock, .wikiEmbedBlock:
            return true
        default:
            return false
        }
    }
}
