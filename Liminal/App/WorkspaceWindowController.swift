import Combine
import Foundation

@MainActor
final class WorkspaceTab: ObservableObject, Identifiable {
    let id: UUID

    @Published private(set) var document: LiminalSourceDocument
    @Published private(set) var fileURL: URL?
    @Published private(set) var contentIdentity: UUID
    @Published var navigationRequest: NavigationRequest?

    private(set) var isHostBacked: Bool

    init(
        id: UUID = UUID(),
        document: LiminalSourceDocument,
        fileURL: URL?,
        isHostBacked: Bool
    ) {
        self.id = id
        self.document = document
        self.fileURL = fileURL
        self.contentIdentity = UUID()
        self.isHostBacked = isHostBacked
        document.setFileURL(fileURL)
    }

    var title: String {
        guard let fileURL else { return "Untitled" }
        return fileURL.deletingPathExtension().lastPathComponent
    }

    var subtitle: String? {
        guard let fileURL else { return nil }
        return fileURL.deletingLastPathComponent().lastPathComponent
    }

    func updateHostFileURL(_ newURL: URL?) {
        guard isHostBacked else { return }
        fileURL = newURL.map(VaultRegistry.canonicalNoteURL)
        document.setFileURL(fileURL)
    }

    func replace(
        with document: LiminalSourceDocument,
        fileURL: URL,
        isHostBacked: Bool
    ) {
        self.document = document
        self.fileURL = VaultRegistry.canonicalNoteURL(for: fileURL)
        self.isHostBacked = isHostBacked
        self.contentIdentity = UUID()
    }

    func stageNavigation(_ request: NavigationRequest) {
        navigationRequest = request
    }
}

@MainActor
final class WorkspaceWindowController: ObservableObject, WorkspaceNavigationSubscriber {
    @Published private(set) var tabs: [WorkspaceTab]
    @Published var selectedTabID: WorkspaceTab.ID?

    private var retainedDocumentsByURL: [URL: RetainedDocument] = [:]

    private struct RetainedDocument {
        let document: LiminalSourceDocument
        let isHostBacked: Bool
    }

    init(initialDocument: LiminalSourceDocument, initialFileURL: URL?) {
        let canonicalURL = initialFileURL.map(VaultRegistry.canonicalNoteURL)
        let tab = WorkspaceTab(
            document: initialDocument,
            fileURL: canonicalURL,
            isHostBacked: true
        )
        self.tabs = [tab]
        self.selectedTabID = tab.id
        if let canonicalURL {
            retainedDocumentsByURL[canonicalURL] = RetainedDocument(
                document: initialDocument,
                isHostBacked: true
            )
        }
    }

    var activeTab: WorkspaceTab? {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID })
        else {
            return tabs.first
        }
        return tab
    }

    func updateHostDocument(_ document: LiminalSourceDocument, fileURL: URL?) {
        guard let hostTab = tabs.first(where: { $0.isHostBacked && $0.document === document }) else {
            return
        }
        hostTab.updateHostFileURL(fileURL)
    }

    func selectTab(_ tabID: WorkspaceTab.ID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        selectedTabID = tabID
    }

    func closeTab(_ tabID: WorkspaceTab.ID) {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else { return }

        tabs[index].document.writeToBackingFileIfPossible()
        tabs.remove(at: index)
        if selectedTabID == tabID {
            let replacementIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[replacementIndex].id
        }
    }

    /// `:Quit` entry point. Closes the active tab when there's more
    /// than one; returns `false` for the last-tab case so the caller
    /// can close the window instead.
    func closeActiveTab() -> Bool {
        guard tabs.count > 1, let active = activeTab else { return false }
        closeTab(active.id)
        return true
    }

    func handleNavigation(_ request: NavigationRequest, disposition: NavigationDisposition) {
        switch disposition {
        case .replaceInCurrentTab:
            replaceActiveTab(with: request)
        case .newTab:
            openNewTab(for: request)
        case .newWindow:
            NavigationRouter.shared.navigate(
                to: request.targetURL,
                anchor: request.anchor,
                disposition: .newWindow
            )
        }
    }

    private func replaceActiveTab(with request: NavigationRequest) {
        if let existing = tab(for: request.targetURL) {
            selectedTabID = existing.id
            existing.stageNavigation(request)
            return
        }

        guard let activeTab else {
            openNewTab(for: request)
            return
        }

        remember(activeTab)
        activeTab.document.writeToBackingFileIfPossible()
        guard let retained = makeDocument(for: request.targetURL) else {
            NavigationRouter.shared.navigate(
                to: request.targetURL,
                anchor: request.anchor,
                disposition: .newWindow
            )
            return
        }

        activeTab.replace(
            with: retained.document,
            fileURL: request.targetURL,
            isHostBacked: retained.isHostBacked
        )
        selectedTabID = activeTab.id
        activeTab.stageNavigation(request)
    }

    private func openNewTab(for request: NavigationRequest) {
        guard let retained = makeDocument(for: request.targetURL) else {
            NavigationRouter.shared.navigate(
                to: request.targetURL,
                anchor: request.anchor,
                disposition: .newWindow
            )
            return
        }

        let tab = WorkspaceTab(
            document: retained.document,
            fileURL: request.targetURL,
            isHostBacked: retained.isHostBacked
        )
        tab.stageNavigation(request)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func tab(for targetURL: URL) -> WorkspaceTab? {
        let canonical = VaultRegistry.canonicalNoteURL(for: targetURL)
        return tabs.first { tab in
            guard let fileURL = tab.fileURL else { return false }
            return VaultRegistry.canonicalNoteURL(for: fileURL) == canonical
        }
    }

    private func remember(_ tab: WorkspaceTab) {
        guard let fileURL = tab.fileURL else { return }
        retainedDocumentsByURL[VaultRegistry.canonicalNoteURL(for: fileURL)] = RetainedDocument(
            document: tab.document,
            isHostBacked: tab.isHostBacked
        )
    }

    private func makeDocument(for url: URL) -> RetainedDocument? {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        if let retained = retainedDocumentsByURL[canonical] {
            return retained
        }
        do {
            let document = try LiminalSourceDocument(standaloneFileURL: url)
            let retained = RetainedDocument(document: document, isHostBacked: false)
            retainedDocumentsByURL[canonical] = retained
            return retained
        } catch {
            NSLog("WorkspaceWindowController: failed to load \(url.path): \(error)")
            return nil
        }
    }
}
