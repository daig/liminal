import Testing
@testable import Liminal

@Suite("VimStatusPresentation")
struct VimStatusPresentationTests {

    @Test("idle Normal mode: detail text is nil")
    func idleNormal() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [],
            pendingCount: nil
        )
        #expect(s.mode == .normal)
        #expect(s.detailText == nil)
    }

    @Test("count-only: detail text is the count digits")
    func countOnly() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [],
            pendingCount: 3
        )
        #expect(s.detailText == "3")
    }

    @Test("multi-digit count formats as decimal")
    func multiDigitCount() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [],
            pendingCount: 42
        )
        #expect(s.detailText == "42")
    }

    @Test("pending key only: shows displayString")
    func pendingKeyOnly() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [.special(.space)],
            pendingCount: nil
        )
        #expect(s.detailText == "<Space>")
    }

    @Test("count + pending key: count first, then keys, separated by space")
    func countAndKey() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [.char("g")],
            pendingCount: 3
        )
        #expect(s.detailText == "3 g")
    }

    @Test("multiple pending keys join with spaces")
    func multipleKeys() {
        let s = VimStatusPresentation.make(
            mode: .normal,
            pendingKeys: [.special(.space), .char("g")],
            pendingCount: nil
        )
        #expect(s.detailText == "<Space> g")
    }

    @Test("Insert mode reflects the mode even when idle")
    func insertMode() {
        let s = VimStatusPresentation.make(
            mode: .insert,
            pendingKeys: [],
            pendingCount: nil
        )
        #expect(s.mode == .insert)
        #expect(s.detailText == nil)
    }
}
