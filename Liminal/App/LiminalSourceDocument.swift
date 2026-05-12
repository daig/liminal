import AppKit
import SwiftUI

final class LiminalSourceDocument: NSDocument {
    let editorSession = LiminalEditorSession()
    private(set) lazy var viewModel = LiminalEditorViewModel(session: editorSession)

    override init() {
        super.init()
        hasUndoManager = true
    }

    override class var autosavesInPlace: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Call the session directly: it's a plain (non-isolated) class, and
        // the view-model is lazy — it will be created in makeWindowControllers
        // and pick up this source via its init's syncFromSession.
        try editorSession.replaceSource(source)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = editorSession.source.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    @MainActor
    override func makeWindowControllers() {
        let view = LiminalEditorView(viewModel: viewModel)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 900, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = displayName ?? "Untitled"
        window.center()
        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        addWindowController(controller)
    }
}
