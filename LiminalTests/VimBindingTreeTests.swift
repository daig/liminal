import Testing
@testable import Liminal

@Suite("VimBindingTree")
struct VimBindingTreeTests {

    @Test("single-key binding resolves to command")
    func singleKey() {
        var t = VimBindingTree()
        t.bind(.normal, [.char("h")], description: "Left") { count in
            .moveCursor(.left, count: count ?? 1)
        }
        let res = t.resolve([.char("h")], mode: .normal, count: nil)
        #expect(res == .command(.moveCursor(.left, count: 1)))
    }

    @Test("multi-key sequence: partial then command")
    func multiKey() {
        var t = VimBindingTree()
        t.bind(.normal, [.special(.space), .char("t")],
               description: "Toggle task") { _ in .toggleTaskAtCursor }

        #expect(t.resolve([.special(.space)], mode: .normal, count: nil) == .partial)
        #expect(t.resolve([.special(.space), .char("t")], mode: .normal, count: nil)
                == .command(.toggleTaskAtCursor))
    }

    @Test("unmatched sequence returns .none")
    func noMatch() {
        var t = VimBindingTree()
        t.bind(.normal, [.char("h")], description: "Left") { _ in
            .moveCursor(.left, count: 1)
        }
        #expect(t.resolve([.char("z")], mode: .normal, count: nil) == .none)
        #expect(t.resolve([.special(.space), .char("z")], mode: .normal, count: nil) == .none)
    }

    @Test("count is propagated to the command factory")
    func countPropagation() {
        var t = VimBindingTree()
        t.bind(.normal, [.char("h")], description: "Left") { count in
            .moveCursor(.left, count: count ?? 1)
        }
        let res = t.resolve([.char("h")], mode: .normal, count: 5)
        #expect(res == .command(.moveCursor(.left, count: 5)))
    }

    @Test("mode segregation: same keys, different commands per mode")
    func perModeBindings() {
        var t = VimBindingTree()
        t.bind(.normal, [.char("i")], description: "Insert") { _ in .enterInsertMode }
        t.bind(.insert, [.special(.escape)], description: "Normal") { _ in .enterNormalMode }

        #expect(t.resolve([.char("i")], mode: .normal, count: nil) == .command(.enterInsertMode))
        #expect(t.resolve([.char("i")], mode: .insert, count: nil) == .none)
        #expect(t.resolve([.special(.escape)], mode: .insert, count: nil)
                == .command(.enterNormalMode))
    }

    @Test("hints after a prefix enumerate the direct children")
    func hintsLookup() {
        var t = VimBindingTree()
        t.bind(.normal, [.special(.space), .char("t")],
               description: "Toggle task") { _ in .toggleTaskAtCursor }
        t.bind(.normal, [.special(.space), .char("q")],
               description: "Quote") { _ in .enterNormalMode }

        let hints = t.hints(after: [.special(.space)], mode: .normal)
        #expect(hints.count == 2)
        let labels = Dictionary(uniqueKeysWithValues: hints.map { ($0.key.displayString, $0.description) })
        #expect(labels["t"] == "Toggle task")
        #expect(labels["q"] == "Quote")
    }

    @Test("hints from empty prefix list top-level bindings")
    func hintsFromRoot() {
        var t = VimBindingTree()
        t.bind(.normal, [.char("h")], description: "Left") { _ in
            .moveCursor(.left, count: 1)
        }
        t.bind(.normal, [.char("j")], description: "Down") { _ in
            .moveCursor(.down, count: 1)
        }
        let hints = t.hints(after: [], mode: .normal)
        #expect(hints.count == 2)
    }

    @Test("default bindings contain expected slice-3 keys")
    func defaultBindingsSmoke() {
        let t = VimController.defaultBindings()
        #expect(t.resolve([.char("i")], mode: .normal, count: nil)
                == .command(.enterInsertMode))
        #expect(t.resolve([.special(.escape)], mode: .insert, count: nil)
                == .command(.enterNormalMode))
        #expect(t.resolve([.char("{")], mode: .normal, count: nil)
                == .command(.structuralMotion(.previousSibling, count: 1)))
        #expect(t.resolve([.special(.space), .char("t")], mode: .normal, count: nil)
                == .command(.toggleTaskAtCursor))
    }
}
