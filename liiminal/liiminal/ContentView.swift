import SwiftUI

struct ContentView: View {
    @State private var vaultViewModel = VaultViewModel()
    @State private var editorViewModel: EditorViewModel?
    @State private var showPreview = false
    @State private var previewFontSize: CGFloat = 16

    var body: some View {
        Group {
            if vaultViewModel.vault != nil {
                NavigationSplitView {
                    SidebarView(vaultViewModel: vaultViewModel)
                } detail: {
                    if let editorVM = editorViewModel, editorVM.currentNote != nil {
                        HSplitView {
                            Group {
                                if showPreview {
                                    RenderedDocumentView(
                                        document: editorVM.document,
                                        documentIndex: editorVM.documentIndex,
                                        currentNoteID: editorVM.currentNote?.id,
                                        navigationRequest: vaultViewModel.navigationRequest,
                                        onOpenWikiTarget: { target in
                                            vaultViewModel.activateTarget(
                                                target,
                                                from: editorVM.currentNote?.id
                                            )
                                        },
                                        baseFontSize: $previewFontSize
                                    )
                                } else {
                                    ZStack(alignment: .bottom) {
                                        EditorView(
                                            editorViewModel: editorVM,
                                            currentNoteID: editorVM.currentNote?.id,
                                            documentIndex: editorVM.documentIndex,
                                            navigationRequest: vaultViewModel.navigationRequest,
                                            referenceResolver: { offset in
                                                guard
                                                    let noteID = editorVM.currentNote?.id,
                                                    let content = editorVM.currentNote?.content,
                                                    let reference = editorVM.documentIndex.reference(
                                                        containing: offset
                                                    )
                                                else {
                                                    return nil
                                                }
                                                return vaultViewModel.resolveReference(
                                                    reference,
                                                    from: noteID,
                                                    content: content
                                                )
                                            },
                                            onActivateReference: { reference in
                                                vaultViewModel.activateReference(reference)
                                            }
                                        )

                                        if let hintSnapshot = editorVM.vimHintSnapshot {
                                            VimHintOverlayView(snapshot: hintSnapshot)
                                                .transition(.opacity)
                                                .zIndex(1)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            LinkInspectorView(
                                vaultViewModel: vaultViewModel,
                                noteID: editorVM.currentNote?.id
                            )
                        }
                        .toolbar {
                            if !showPreview {
                                ToolbarItem(placement: .automatic) {
                                    HStack(spacing: 6) {
                                        Text(editorVM.vimMode.rawValue.uppercased())
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .foregroundStyle(
                                                modeForegroundStyle(for: editorVM.vimMode)
                                            )
                                            .background(
                                                modeBackgroundColor(for: editorVM.vimMode)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 4))

                                        if let detailText = editorVM.vimStatus.detailText {
                                            Text(detailText)
                                                .font(
                                                    .system(
                                                        size: 11,
                                                        weight: .medium,
                                                        design: .monospaced
                                                    )
                                                )
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .foregroundStyle(.secondary)
                                                .background(Color.secondary.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }

                                        if let cursorInfo = editorVM.vimCursorInfo {
                                            HStack(spacing: 6) {
                                                Text(cursorInfo.sectionTitle)
                                                    .font(
                                                        .system(
                                                            size: 10,
                                                            weight: .semibold,
                                                            design: .monospaced
                                                        )
                                                    )
                                                    .foregroundStyle(.secondary)

                                                ForEach(cursorInfo.items) { item in
                                                    Text(item.label)
                                                        .font(
                                                            .system(
                                                                size: 11,
                                                                weight: .semibold,
                                                                design: .monospaced
                                                            )
                                                        )
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .foregroundStyle(cursorInfoForeground(for: item))
                                                        .background(
                                                            cursorInfoForeground(for: item).opacity(0.12)
                                                        )
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            ToolbarItem(placement: .automatic) {
                                Button {
                                    showPreview.toggle()
                                } label: {
                                    Image(
                                        systemName: showPreview
                                            ? "pencil.line" : "eye"
                                    )
                                }
                                .keyboardShortcut("e", modifiers: .command)
                                .help(showPreview ? "Edit" : "Preview")
                            }
                        }
                    } else {
                        Text("Select a note")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                WelcomeView(onOpenVault: { vaultViewModel.openVault() })
            }
        }
        .onAppear {
            editorViewModel = EditorViewModel(fileService: vaultViewModel.fileService)
            if AppRuntime.isRunningUnitTests == false {
                vaultViewModel.restorePreviousVault()
            }
        }
        .onChange(of: vaultViewModel.selectedNoteID) { _, _ in
            if let note = vaultViewModel.selectedNote {
                editorViewModel?.openNote(note)
                if vaultViewModel.navigationRequest?.noteID != note.id {
                    vaultViewModel.clearNavigationRequest()
                }
            }
        }
        .onChange(of: editorViewModel?.currentNote?.content) { _, newContent in
            guard let noteID = editorViewModel?.currentNote?.id, let newContent else { return }
            vaultViewModel.updateNoteContent(noteID: noteID, content: newContent)
        }
        .onChange(of: showPreview) { _, _ in
            editorViewModel?.clearVimHints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVault)) { _ in
            vaultViewModel.openVault()
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func modeForegroundStyle(for mode: VimMode) -> Color {
        switch mode {
        case .normal:
            .orange
        case .visual, .visualLine:
            .blue
        case .insert:
            .secondary
        }
    }

    private func modeBackgroundColor(for mode: VimMode) -> Color {
        switch mode {
        case .normal:
            Color.orange.opacity(0.15)
        case .visual, .visualLine:
            Color.blue.opacity(0.14)
        case .insert:
            Color.secondary.opacity(0.1)
        }
    }

    private func cursorInfoForeground(for item: VimCursorInfoItem) -> Color {
        guard let tint = item.tint else { return .secondary }
        return Color(
            hue: tint.hue,
            saturation: tint.saturation,
            brightness: tint.brightness
        )
    }
}
