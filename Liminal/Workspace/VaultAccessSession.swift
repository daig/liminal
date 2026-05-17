import Foundation

/// RAII wrapper around a security-scoped bookmark's
/// `startAccessingSecurityScopedResource()` / `stopAccessing...`
/// lifecycle. Owning the session in a class makes it impossible for
/// callers to accidentally leak the access token — `deinit` always
/// releases it, and `release()` is idempotent so explicit teardown
/// works too.
///
/// `isStale` mirrors the value Apple's bookmark API returns: when
/// `true`, the bookmark resolved but the underlying URL changed
/// (e.g., user moved the folder). The caller should re-capture
/// fresh bookmark data from the resolved URL and write it back to
/// the store.
public final class VaultAccessSession {
    public let resolvedURL: URL
    public let isStale: Bool

    private var isReleased: Bool = false

    private init(resolvedURL: URL, isStale: Bool) {
        self.resolvedURL = resolvedURL
        self.isStale = isStale
    }

    /// Resolve `bookmarkData` against the current filesystem and
    /// call `startAccessingSecurityScopedResource()`. Returns nil
    /// when the bookmark can't resolve at all (file gone, drive
    /// unmounted) — the caller should drop the bookmark and prompt
    /// the user to reconnect the vault.
    public static func resolve(_ bookmarkData: Data) -> VaultAccessSession? {
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        return VaultAccessSession(resolvedURL: url, isStale: stale)
    }

    /// Stop accessing the security-scoped resource. Idempotent —
    /// calling it twice (e.g., explicit release followed by `deinit`)
    /// is safe.
    public func release() {
        guard !isReleased else { return }
        isReleased = true
        resolvedURL.stopAccessingSecurityScopedResource()
    }

    deinit { release() }
}
