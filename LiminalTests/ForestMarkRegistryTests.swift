import Testing
import CambiumCore
import CambiumSelection
@testable import Liminal

@Suite("ForestMarkRegistry")
struct ForestMarkRegistryTests {

    // Build a real LiminalForestAnchor by parsing a tiny doc and
    // capturing whatever cstVisualEntry returns at byte 0.
    private static func sampleAnchor(_ source: String = "Hello world.\n") throws -> LiminalForestAnchor {
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let forest = try #require(
            LiminalForest.cstVisualEntry(at: .zero, in: parsed.tree)
        )
        return LiminalForestAnchor.from(forest)
    }

    @Test("a fresh registry is empty")
    func freshEmpty() {
        let registry = ForestMarkRegistry()
        #expect(registry.marks.isEmpty)
        #expect(registry.allLetters.isEmpty)
        #expect(registry.anchor(named: "a") == nil)
    }

    @Test("set + anchor(named:) round-trips")
    func setAndAnchorRoundTrip() throws {
        var registry = ForestMarkRegistry()
        let anchor = try Self.sampleAnchor()
        registry.set("a", anchor: anchor)
        #expect(registry.anchor(named: "a") == anchor)
    }

    @Test("set overwrites existing slot")
    func setOverwrites() throws {
        var registry = ForestMarkRegistry()
        let first = try Self.sampleAnchor("First.\n")
        let second = try Self.sampleAnchor("Second.\n")
        registry.set("a", anchor: first)
        registry.set("a", anchor: second)
        #expect(registry.anchor(named: "a") == second)
    }

    @Test("unset removes the slot")
    func unsetRemoves() throws {
        var registry = ForestMarkRegistry()
        registry.set("a", anchor: try Self.sampleAnchor())
        #expect(registry.anchor(named: "a") != nil)
        registry.unset("a")
        #expect(registry.anchor(named: "a") == nil)
    }

    @Test("allLetters returns slot letters in sorted order")
    func allLettersSorted() throws {
        var registry = ForestMarkRegistry()
        let anchor = try Self.sampleAnchor()
        for letter: Character in ["c", "a", "z", "B", "M"] {
            registry.set(letter, anchor: anchor)
        }
        #expect(registry.allLetters == ["B", "M", "a", "c", "z"])
    }

    @Test("isValidMarkName accepts a-z and A-Z, rejects digits / symbols / multi-scalar")
    func isValidMarkNameRange() {
        for ch: Character in ["a", "z", "m", "A", "Z", "Q"] {
            #expect(ForestMarkRegistry.isValidMarkName(ch), "expected \(ch) to be valid")
        }
        for ch: Character in ["0", "9", "!", "_", " ", "ñ", "🙂"] {
            #expect(!ForestMarkRegistry.isValidMarkName(ch), "expected \(ch) to be invalid")
        }
    }
}
