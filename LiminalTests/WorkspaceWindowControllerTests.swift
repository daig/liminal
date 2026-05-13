import Foundation
import Testing
@testable import Liminal

@Suite("WorkspaceWindowController")
@MainActor
struct WorkspaceWindowControllerTests {
    @Test("replace navigation retargets the active tab without writing the host document externally")
    func replaceNavigationRetargetsActiveTab() throws {
        VaultRegistry.shared.resetForTesting()
        defer { VaultRegistry.shared.resetForTesting() }
        let urls = try makeVaultFiles([
            "Source.lim": "Source\n",
            "Target.lim": "Target\n"
        ])
        let sourceURL = try #require(urls["Source.lim"])
        let targetURL = try #require(urls["Target.lim"])
        let sourceDocument = LiminalSourceDocument()
        try sourceDocument.session.replaceSource("Unsaved Source\n")
        let workspace = WorkspaceWindowController(
            initialDocument: sourceDocument,
            initialFileURL: sourceURL
        )

        let request = NavigationRequest(targetURL: targetURL, anchor: .heading("H"))
        workspace.handleNavigation(request, disposition: .replaceInCurrentTab)
        let persistedSource = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(workspace.tabs.count == 1)
        #expect(persistedSource == "Source\n")
        #expect(workspace.activeTab?.fileURL == VaultRegistry.canonicalNoteURL(for: targetURL))
        #expect(workspace.activeTab?.document.session.source == "Target\n")
        #expect(workspace.activeTab?.navigationRequest == request)

        let backRequest = NavigationRequest(targetURL: sourceURL, anchor: nil)
        workspace.handleNavigation(backRequest, disposition: .replaceInCurrentTab)
        let returnedTab = try #require(workspace.activeTab)

        #expect(workspace.tabs.count == 1)
        #expect(returnedTab.document === sourceDocument)
        #expect(returnedTab.isHostBacked == true)
        #expect(returnedTab.document.session.source == "Unsaved Source\n")
    }

    @Test("shift navigation opens the target in a new active tab")
    func shiftNavigationOpensNewActiveTab() throws {
        VaultRegistry.shared.resetForTesting()
        defer { VaultRegistry.shared.resetForTesting() }
        let urls = try makeVaultFiles([
            "Source.lim": "Source\n",
            "Target.lim": "Target\n"
        ])
        let sourceURL = try #require(urls["Source.lim"])
        let targetURL = try #require(urls["Target.lim"])
        let sourceDocument = try LiminalSourceDocument(standaloneFileURL: sourceURL)
        let workspace = WorkspaceWindowController(
            initialDocument: sourceDocument,
            initialFileURL: sourceURL
        )

        let request = NavigationRequest(targetURL: targetURL, anchor: nil)
        workspace.handleNavigation(request, disposition: .newTab)

        #expect(workspace.tabs.count == 2)
        #expect(workspace.activeTab?.fileURL == VaultRegistry.canonicalNoteURL(for: targetURL))
        #expect(workspace.activeTab?.document.session.source == "Target\n")
        #expect(workspace.activeTab?.navigationRequest == request)
    }

    @Test("standalone tabs write through before being replaced")
    func standaloneTabsWriteThroughBeforeReplace() throws {
        VaultRegistry.shared.resetForTesting()
        defer { VaultRegistry.shared.resetForTesting() }
        let urls = try makeVaultFiles([
            "Source.lim": "Source\n",
            "Target.lim": "Target\n",
            "Third.lim": "Third\n"
        ])
        let sourceURL = try #require(urls["Source.lim"])
        let targetURL = try #require(urls["Target.lim"])
        let thirdURL = try #require(urls["Third.lim"])
        let sourceDocument = LiminalSourceDocument()
        try sourceDocument.session.replaceSource("Source\n")
        let workspace = WorkspaceWindowController(
            initialDocument: sourceDocument,
            initialFileURL: sourceURL
        )

        workspace.handleNavigation(
            NavigationRequest(targetURL: targetURL, anchor: nil),
            disposition: .newTab
        )
        let targetTab = try #require(workspace.activeTab)
        try targetTab.document.session.replaceSource("Unsaved Target\n")

        workspace.handleNavigation(
            NavigationRequest(targetURL: thirdURL, anchor: nil),
            disposition: .replaceInCurrentTab
        )
        let persistedTarget = try String(contentsOf: targetURL, encoding: .utf8)

        #expect(persistedTarget == "Unsaved Target\n")
        #expect(workspace.activeTab?.fileURL == VaultRegistry.canonicalNoteURL(for: thirdURL))
    }

    private func makeVaultFiles(_ files: [String: String]) throws -> [String: URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("liminal-workspace-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        var result: [String: URL] = [:]
        for (name, contents) in files {
            let url = root.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            result[name] = url
        }
        return result
    }
}
