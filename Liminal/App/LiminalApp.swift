import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let liminalMarkup = UTType(exportedAs: "sub.dev.liminal.markup")
}

@main
struct LiminalApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LiminalSourceDocument.init) { configuration in
            LiminalEditorView(document: configuration.document)
        }
    }
}
