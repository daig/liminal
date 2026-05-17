import Foundation
import Testing
@testable import Liminal

@Suite("VaultBookmarkStore")
struct VaultBookmarkStoreTests {

    /// Build an isolated `VaultBookmarkStore` backed by a unique
    /// `UserDefaults` suite so tests don't collide with each other
    /// or pollute the user's real preferences. The suite is removed
    /// at the end of each test.
    private static func makeStore() -> (store: VaultBookmarkStore, suiteName: String) {
        let suiteName = "liminal.bookmarkstore.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (VaultBookmarkStore(defaults: defaults), suiteName)
    }

    private static func cleanup(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private static let sampleVaultA = URL(fileURLWithPath: "/Users/test/notes-a", isDirectory: true)
    private static let sampleVaultB = URL(fileURLWithPath: "/Users/test/notes-b", isDirectory: true)
    private static let sampleData1 = Data([0xDE, 0xAD, 0xBE, 0xEF])
    private static let sampleData2 = Data([0xCA, 0xFE, 0xBA, 0xBE])

    @Test("a fresh store is empty")
    func freshStoreIsEmpty() {
        let (store, suite) = Self.makeStore()
        defer { Self.cleanup(suite) }

        #expect(store.bookmarkData(forVaultRoot: Self.sampleVaultA) == nil)
        #expect(store.allVaultRoots().isEmpty)
    }

    @Test("set + get round-trips bookmark data")
    func setAndGetRoundTrips() {
        let (store, suite) = Self.makeStore()
        defer { Self.cleanup(suite) }

        store.setBookmarkData(Self.sampleData1, forVaultRoot: Self.sampleVaultA)
        #expect(store.bookmarkData(forVaultRoot: Self.sampleVaultA) == Self.sampleData1)
    }

    @Test("set overwrites a prior bookmark for the same vault root")
    func setOverwritesPriorBookmark() {
        let (store, suite) = Self.makeStore()
        defer { Self.cleanup(suite) }

        store.setBookmarkData(Self.sampleData1, forVaultRoot: Self.sampleVaultA)
        store.setBookmarkData(Self.sampleData2, forVaultRoot: Self.sampleVaultA)
        #expect(store.bookmarkData(forVaultRoot: Self.sampleVaultA) == Self.sampleData2)
    }

    @Test("removeBookmark drops the slot")
    func removeDropsSlot() {
        let (store, suite) = Self.makeStore()
        defer { Self.cleanup(suite) }

        store.setBookmarkData(Self.sampleData1, forVaultRoot: Self.sampleVaultA)
        store.removeBookmark(forVaultRoot: Self.sampleVaultA)
        #expect(store.bookmarkData(forVaultRoot: Self.sampleVaultA) == nil)
        #expect(store.allVaultRoots().isEmpty)
    }

    @Test("allVaultRoots returns every URL with a stored bookmark")
    func allVaultRootsReturnsAllStoredKeys() {
        let (store, suite) = Self.makeStore()
        defer { Self.cleanup(suite) }

        store.setBookmarkData(Self.sampleData1, forVaultRoot: Self.sampleVaultA)
        store.setBookmarkData(Self.sampleData2, forVaultRoot: Self.sampleVaultB)
        let roots = Set(store.allVaultRoots())
        #expect(roots == Set([Self.sampleVaultA, Self.sampleVaultB]))
    }

    @Test("bookmarks persist across store instances on the same UserDefaults suite")
    func persistsAcrossInstances() {
        let suiteName = "liminal.bookmarkstore.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let storeA = VaultBookmarkStore(defaults: defaults)
        storeA.setBookmarkData(Self.sampleData1, forVaultRoot: Self.sampleVaultA)

        // Fresh instance pointed at the same suite must see the value.
        let storeB = VaultBookmarkStore(defaults: defaults)
        #expect(storeB.bookmarkData(forVaultRoot: Self.sampleVaultA) == Self.sampleData1)
    }
}
