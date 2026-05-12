import CambiumIncremental
import Combine
import Foundation

@MainActor
final class LiminalEditorViewModel: ObservableObject {
    @Published private(set) var diagnosticsCount: Int = 0
    @Published private(set) var reuseSummary: ReuseSummary = .empty

    let session: LiminalEditorSession

    init(session: LiminalEditorSession) {
        self.session = session
        syncFromSession()
    }

    func applyTextEdits(_ edits: [TextEdit]) {
        do {
            try session.applyTextEdits(edits)
        } catch {
            NSLog("LiminalEditorViewModel: applyTextEdits failed: \(error)")
        }
        syncFromSession()
    }

    func replaceSource(_ source: String) {
        do {
            try session.replaceSource(source)
        } catch {
            NSLog("LiminalEditorViewModel: replaceSource failed: \(error)")
        }
        syncFromSession()
    }

    func syncFromSession() {
        diagnosticsCount = session.parseResult?.diagnostics.count ?? 0
        reuseSummary = session.lastReuseSummary
    }
}
