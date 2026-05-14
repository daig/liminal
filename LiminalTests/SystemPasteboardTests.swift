import AppKit
import Testing
@testable import Liminal

@Suite("SystemPasteboard")
@MainActor
struct SystemPasteboardTests {
    /// Each test gets a fresh in-memory pasteboard so the user's
    /// real clipboard is untouched and tests don't see each other's
    /// writes.
    private func withSandboxPasteboard<R>(_ body: () -> R) -> R {
        let original = SystemPasteboard.pasteboard
        SystemPasteboard.pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "dev.sub.liminal.tests.\(UUID().uuidString)"
        ))
        defer { SystemPasteboard.pasteboard = original }
        return body()
    }

    @Test(
        "round-trip preserves text + kind",
        arguments: [
            YankKind.characterwise,
            .linewise,
            .blockwise
        ]
    )
    func roundTrip(_ kind: YankKind) {
        withSandboxPasteboard {
            SystemPasteboard.write(text: "hello\nworld", kind: kind)
            let read = SystemPasteboard.read()
            #expect(read?.text == "hello\nworld")
            #expect(read?.kind == kind)
            #expect(read?.structuralFragmentData == nil)
        }
    }

    @Test("round-trip preserves structural fragment data")
    func roundTripStructuralFragmentData() {
        withSandboxPasteboard {
            let data = Data([0x01, 0x02, 0x03])
            SystemPasteboard.write(
                text: "structural",
                kind: .cstForest,
                structuralFragmentData: data
            )
            let read = SystemPasteboard.read()
            #expect(read?.text == "structural")
            #expect(read?.kind == .cstForest)
            #expect(read?.structuralFragmentData == data)
        }
    }

    @Test("read degrades to characterwise when kind UTI is absent")
    func degradeToCharwise() {
        withSandboxPasteboard {
            // Simulate a foreign-app write: only the standard
            // .string type is set, no kind UTI.
            let pb = SystemPasteboard.pasteboard
            pb.declareTypes([.string], owner: nil)
            pb.setString("from another app", forType: .string)

            let read = SystemPasteboard.read()
            #expect(read?.text == "from another app")
            #expect(read?.kind == .characterwise)
        }
    }

    @Test("read returns nil when pasteboard has no string")
    func emptyPasteboard() {
        withSandboxPasteboard {
            #expect(SystemPasteboard.read() == nil)
        }
    }
}
