import Foundation

enum BookmarkService {
    private static let bookmarkKey = "vaultBookmark"

    static func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            // Re-save if stale
            try? saveBookmark(for: url)
        }
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        return url
    }

    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
