import CambiumIncremental
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI document-group document. Owns a `LiminalEditorSession` and
/// re-publishes per-parse derived state (diagnostics count, reuse summary)
/// so SwiftUI views can observe it. The session itself stays a plain
/// orchestrator class; Combine is kept at the app boundary.
///
/// Not isolated to MainActor — SwiftUI's DocumentGroup constructs documents
/// from a non-isolated Sendable closure, and `ReferenceFileDocument`
/// conformance brings its own thread-safety expectations via @Published.
final class LiminalSourceDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.liminalMarkup, .plainText] }
    static var writableContentTypes: [UTType] { [.liminalMarkup] }

    let session: LiminalEditorSession

    @Published private(set) var diagnosticsCount: Int = 0
    @Published private(set) var reuseSummary: ReuseSummary = .empty

    init() {
        self.session = LiminalEditorSession()
        syncFromSession()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.session = LiminalEditorSession()
        try session.replaceSource(source)
        syncFromSession()
    }

    func snapshot(contentType: UTType) throws -> String {
        session.source
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// Forward a textual edit to the session. Called by `LiminalTextView`'s
    /// `NSTextStorageDelegate` coordinator on user-initiated edits.
    func applyTextEdits(_ edits: [TextEdit]) {
        do {
            try session.applyTextEdits(edits)
        } catch {
            NSLog("LiminalSourceDocument: applyTextEdits failed: \(error)")
        }
        syncFromSession()
    }

    private func syncFromSession() {
        diagnosticsCount = session.parseResult?.diagnostics.count ?? 0
        reuseSummary = session.lastReuseSummary
    }
}
