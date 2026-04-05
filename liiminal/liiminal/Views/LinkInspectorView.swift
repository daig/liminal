import SwiftUI

struct LinkInspectorView: View {
    @Bindable var vaultViewModel: VaultViewModel
    let noteID: URL?

    private var outgoing: [ResolvedReference] {
        vaultViewModel.outgoingReferences(for: noteID)
    }

    private var backlinks: [ResolvedReference] {
        vaultViewModel.backlinks(for: noteID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(
                    title: "Outgoing",
                    references: outgoing,
                    emptyText: "No outgoing wiki links."
                ) { reference in
                    OutgoingReferenceRow(
                        reference: reference,
                        vaultViewModel: vaultViewModel
                    )
                }

                section(
                    title: "Backlinks",
                    references: backlinks,
                    emptyText: "No backlinks yet."
                ) { reference in
                    BacklinkReferenceRow(
                        reference: reference,
                        vaultViewModel: vaultViewModel
                    )
                }
            }
            .padding(16)
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func section<Row: View>(
        title: String,
        references: [ResolvedReference],
        emptyText: String,
        @ViewBuilder row: @escaping (ResolvedReference) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(references.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if references.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(references) { reference in
                        row(reference)
                    }
                }
            }
        }
    }
}

private struct OutgoingReferenceRow: View {
    let reference: ResolvedReference
    @Bindable var vaultViewModel: VaultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(primaryText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)

                Spacer()

                if isCreatable {
                    Button("Create") {
                        vaultViewModel.activateReference(reference)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Open") {
                        vaultViewModel.activateReference(reference)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAmbiguous)
                }
            }

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)

            if !reference.sourceSnippet.isEmpty {
                Text(reference.sourceSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryText: String {
        switch reference.resolution {
        case .resolved(let destination):
            return destinationLabel(destination)
        case .noteResolved(let noteID, let anchor):
            let noteLabel = vaultViewModel.note(for: noteID)?.relativePathWithoutExtension
                ?? noteID.deletingPathExtension().lastPathComponent
            return noteLabel + " · " + anchorLabel(anchor)
        case .unresolved, .ambiguous:
            return reference.target.rawTargetString
        }
    }

    private var statusText: String {
        let kindLabel = reference.kind == .embed ? "embed" : "link"
        switch reference.resolution {
        case .resolved:
            return kindLabel + " · resolved"
        case .noteResolved:
            return kindLabel + " · note resolved, anchor missing"
        case .unresolved:
            return kindLabel + " · unresolved"
        case .ambiguous:
            return kindLabel + " · ambiguous"
        }
    }

    private var statusColor: Color {
        switch reference.resolution {
        case .resolved:
            return .secondary
        case .noteResolved:
            return .orange
        case .unresolved:
            return .red
        case .ambiguous:
            return .orange
        }
    }

    private var isCreatable: Bool {
        if case .unresolved = reference.resolution {
            return reference.target.notePath != nil
        }
        return false
    }

    private var isAmbiguous: Bool {
        if case .ambiguous = reference.resolution {
            return true
        }
        return false
    }

    private func destinationLabel(_ destination: LinkDestination) -> String {
        let noteLabel = vaultViewModel.note(for: destination.noteID)?.relativePathWithoutExtension
            ?? destination.noteID.deletingPathExtension().lastPathComponent
        switch destination {
        case .note:
            return noteLabel
        case .heading(_, let heading):
            return noteLabel + " · " + heading
        case .block(_, let blockID):
            return noteLabel + " · ^" + blockID
        }
    }

    private func anchorLabel(_ anchor: LinkNavigationAnchor) -> String {
        switch anchor {
        case .heading(let heading):
            return heading
        case .block(let blockID):
            return "^" + blockID
        case .sourceOffset:
            return "source"
        }
    }
}

private struct BacklinkReferenceRow: View {
    let reference: ResolvedReference
    @Bindable var vaultViewModel: VaultViewModel

    var body: some View {
        Button {
            vaultViewModel.activateBacklink(reference)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)

                Text(targetLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !reference.sourceSnippet.isEmpty {
                    Text(reference.sourceSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var sourceLabel: String {
        vaultViewModel.note(for: reference.sourceNoteID)?.relativePathWithoutExtension
            ?? reference.sourceNoteID.deletingPathExtension().lastPathComponent
    }

    private var targetLabel: String {
        let kindLabel = reference.kind == .embed ? "embed" : "link"
        return kindLabel + " · " + reference.target.rawTargetString
    }
}
