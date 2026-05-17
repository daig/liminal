import Foundation

/// `UserDefaults`-backed registry of security-scoped bookmark data
/// for vault root folders. Bookmarks persist across launches so the
/// app can restore folder access without re-prompting the user.
///
/// Keyed by the canonical vault root URL's `absoluteString` — that
/// way moving the vault folder (and re-resolving an `isStale`
/// bookmark) lets the new path slot in at the same key. The whole
/// `[URL string: Data]` dict lives under a single `.v1`-suffixed
/// `UserDefaults` key so we can introduce a `.v2` migration later
/// without colliding.
public final class VaultBookmarkStore: @unchecked Sendable {
    public static let shared = VaultBookmarkStore()

    private static let defaultsKey = "liminal.vaultBookmarks.v1"

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "liminal.vaultBookmarkStore", attributes: .concurrent)

    /// Injection point for tests. Pass an isolated suite so unit
    /// tests don't touch the user's real preferences.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stored bookmark data for `canonicalRoot`, or `nil` if no
    /// bookmark exists for this vault.
    public func bookmarkData(forVaultRoot canonicalRoot: URL) -> Data? {
        let key = Self.key(for: canonicalRoot)
        return queue.sync {
            currentDict()[key]
        }
    }

    /// Persist `bookmarkData` under `canonicalRoot`, replacing any
    /// prior value. Writes through to `UserDefaults` synchronously.
    public func setBookmarkData(_ data: Data, forVaultRoot canonicalRoot: URL) {
        let key = Self.key(for: canonicalRoot)
        queue.sync(flags: .barrier) {
            var dict = currentDict()
            dict[key] = data
            persist(dict)
        }
    }

    /// Drop the slot. No-op if no bookmark was stored.
    public func removeBookmark(forVaultRoot canonicalRoot: URL) {
        let key = Self.key(for: canonicalRoot)
        queue.sync(flags: .barrier) {
            var dict = currentDict()
            guard dict.removeValue(forKey: key) != nil else { return }
            persist(dict)
        }
    }

    /// Every canonical root URL that has a stored bookmark. Used at
    /// app launch to bulk-resolve bookmarks and start sessions.
    public func allVaultRoots() -> [URL] {
        queue.sync {
            currentDict().keys.compactMap { URL(string: $0) }
        }
    }

    // MARK: - Internal

    private func currentDict() -> [String: Data] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }

    private func persist(_ dict: [String: Data]) {
        if dict.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(dict, forKey: Self.defaultsKey)
        }
    }

    private static func key(for url: URL) -> String {
        url.absoluteString
    }
}
