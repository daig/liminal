import Foundation

/// Resolves a user-typed path string from `:Edit <path>` (and future
/// ex commands) against a vault root, producing a concrete `URL`.
///
/// Resolution order:
/// 1. `~` is expanded to the user's home directory.
/// 2. Absolute paths (after expansion) are returned as-is.
/// 3. All other inputs are treated as **vault-relative** and resolved
///    against `vaultRoot`.
/// 4. If the resolved path has no extension, `.lim` is appended
///    automatically — matches the existing `[[NewLinkName]]` flow
///    which also defaults to `.lim`.
///
/// **Does not check existence.** The caller decides what to do with
/// the returned URL (open if existing, create if missing).
///
/// Pure value type — exists as a struct so the eventual sandbox
/// migration can swap in a sandbox-aware resolver (e.g., one that
/// routes absolute paths through `NSOpenPanel` to acquire a
/// security-scoped bookmark) without changing call sites.
public struct PathResolver: Sendable {
    public let vaultRoot: URL?

    public init(vaultRoot: URL?) {
        self.vaultRoot = vaultRoot
    }

    /// Resolve `input` to a URL. Returns nil only when the input is
    /// empty OR when the input is vault-relative but no `vaultRoot`
    /// was supplied (caller has no vault and didn't provide an
    /// absolute path).
    public func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = Self.expandingTilde(trimmed)

        let resolved: URL
        if expanded.hasPrefix("/") {
            resolved = URL(fileURLWithPath: expanded)
        } else if let vaultRoot {
            resolved = vaultRoot.appendingPathComponent(expanded)
        } else {
            return nil
        }

        return Self.ensuringLimExtension(resolved)
    }

    // MARK: - Internal helpers

    /// Expand `~` and `~/` to the user's home directory. Leaves
    /// `~user` (the `user` part isn't us) alone; that's a rare case
    /// in note paths and warrants its own handling later if needed.
    private static func expandingTilde(_ input: String) -> String {
        guard input.hasPrefix("~") else { return input }
        if input == "~" {
            return NSHomeDirectory()
        }
        if input.hasPrefix("~/") {
            let tail = String(input.dropFirst(2))
            return NSHomeDirectory() + "/" + tail
        }
        return input
    }

    /// Append `.lim` when the URL's last path component has no
    /// extension. Matches the convention used by the existing
    /// wikilink-creates-note flow.
    private static func ensuringLimExtension(_ url: URL) -> URL {
        if !url.pathExtension.isEmpty { return url }
        return url.appendingPathExtension("lim")
    }
}
