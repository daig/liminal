import Testing
@testable import Liminal

@Suite("VimHintSnapshot")
struct VimHintSnapshotTests {

    @Test("VimHintItem default kind is .action")
    func defaultKind() {
        let item = VimHintItem(key: .char("t"), description: "Toggle task")
        #expect(item.kind == .action)
    }

    @Test("VimHintItem id mixes key and description")
    func idDistinguishesKeyAndDescription() {
        let a = VimHintItem(key: .char("t"), description: "Toggle task")
        let b = VimHintItem(key: .char("t"), description: "Other")
        let c = VimHintItem(key: .char("q"), description: "Toggle task")
        #expect(a.id != b.id)
        #expect(a.id != c.id)
    }

    @Test("VimHintItem equality treats kind as significant")
    func equalityIncludesKind() {
        let action = VimHintItem(key: .char("t"), description: "Toggle", kind: .action)
        let group  = VimHintItem(key: .char("t"), description: "Toggle", kind: .group)
        #expect(action != group)
    }

    @Test("VimHintSnapshot isEmpty true for empty items")
    func emptySnapshot() {
        let snapshot = VimHintSnapshot(title: nil, items: [])
        #expect(snapshot.isEmpty)
    }

    @Test("VimHintSnapshot isEmpty false when items are present")
    func nonEmptySnapshot() {
        let snapshot = VimHintSnapshot(
            title: "<Space>",
            items: [VimHintItem(key: .char("t"), description: "Toggle task")]
        )
        #expect(!snapshot.isEmpty)
    }

    @Test("snapshots with identical title+items compare equal")
    func equalitySymmetry() {
        let a = VimHintSnapshot(
            title: "<Space>",
            items: [VimHintItem(key: .char("t"), description: "Toggle task")]
        )
        let b = VimHintSnapshot(
            title: "<Space>",
            items: [VimHintItem(key: .char("t"), description: "Toggle task")]
        )
        #expect(a == b)
    }
}
