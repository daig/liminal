import Testing
import CambiumCore
@testable import Liminal

@Suite("CSTSlotMarkRegistry")
struct CSTSlotMarkRegistryTests {
    private static func sampleAnchor(
        _ source: String = "First.\n"
    ) throws -> CSTSlotAnchor {
        let parsed = try LiminalParser().parse(CambiumSource(source))
        return try parsed.tree.withRoot { root in
            try #require(root.withChildNode(atRawIndex: 0) { child in
                CSTSlotAnchor(
                    node: CSTNodeAnchor(
                        path: child.liminalCSTPath,
                        fingerprint: NodeFingerprint(
                            kind: child.kind,
                            contentHash: child.greenHash
                        )
                    ),
                    selector: .before
                )
            })
        }
    }

    @Test("initial registry is empty")
    func initialRegistryIsEmpty() {
        let registry = CSTSlotMarkRegistry()
        #expect(registry.marks.isEmpty)
        #expect(registry.allLetters.isEmpty)
    }

    @Test("set stores and overwrites anchors")
    func setStoresAndOverwrites() throws {
        var registry = CSTSlotMarkRegistry()
        let first = try Self.sampleAnchor("First.\n")
        let second = try Self.sampleAnchor("Second.\n")

        registry.set("a", anchor: first)
        #expect(registry.anchor(named: "a") == first)

        registry.set("a", anchor: second)
        #expect(registry.anchor(named: "a") == second)
    }

    @Test("unset removes an anchor")
    func unsetRemovesAnchor() throws {
        var registry = CSTSlotMarkRegistry()
        registry.set("a", anchor: try Self.sampleAnchor())

        registry.unset("a")

        #expect(registry.anchor(named: "a") == nil)
    }

    @Test("allLetters returns sorted mark names")
    func allLettersSorted() throws {
        var registry = CSTSlotMarkRegistry()
        let anchor = try Self.sampleAnchor()
        registry.set("z", anchor: anchor)
        registry.set("A", anchor: anchor)
        registry.set("m", anchor: anchor)

        #expect(registry.allLetters == ["A", "m", "z"])
    }

    @Test("valid mark names match CST forest mark namespace")
    func validMarkNames() {
        for ch in ["a", "z", "A", "Z"] as [Character] {
            #expect(CSTSlotMarkRegistry.isValidMarkName(ch))
        }
        for ch in ["1", "_", "é"] as [Character] {
            #expect(!CSTSlotMarkRegistry.isValidMarkName(ch))
        }
    }

}
