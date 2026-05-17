import Foundation

/// Centralized wrapper around `NSFileCoordinator` for every file
/// read/write in the app. Wrapping is mandatory for correctness when
/// any of our files lives in iCloud Drive — the iCloud daemon
/// (`bird`/`cloudd`) can read/write to user files at any moment, and
/// without coordination we get torn reads, lost writes, or spurious
/// "Conflict X copy" files in Finder.
///
/// For purely local files (outside any iCloud-synced folder), the
/// coordinator is a fast no-op — there's no other presenter to
/// coordinate with — so wrapping has effectively zero cost on the
/// happy path.
///
/// **Presenter argument**: when the calling document has registered
/// itself as an `NSFilePresenter`, pass it so the coordinator can
/// exclude it from "wait for other presenters" deadlocks (Apple's
/// docs: a presenter doesn't coordinate against itself). Background
/// scanners that don't own a presenter pass `nil`.
enum CoordinatedFileIO {

    /// Coordinated read. `body` runs synchronously with the
    /// (possibly redirected) URL Apple hands back; the returned value
    /// bubbles out. Re-throws both the body's errors and any
    /// coordinator errors.
    static func read<T>(
        at url: URL,
        presenter: NSFilePresenter?,
        _ body: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { resolvedURL in
            do {
                result = .success(try body(resolvedURL))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none:
            // Coordinator completed without invoking the block AND
            // without reporting an error — shouldn't happen per
            // Apple's contract. Surface as a synthetic error.
            throw CocoaError(.fileReadUnknown)
        }
    }

    /// Coordinated atomic write. Uses `.forReplacing` semantics so
    /// peer presenters know we're producing a new file at the URL.
    static func write(
        _ data: Data,
        to url: URL,
        presenter: NSFilePresenter?,
        options: Data.WritingOptions = [.atomic]
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinatorError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forReplacing],
            error: &coordinatorError
        ) { resolvedURL in
            do {
                try data.write(to: resolvedURL, options: options)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    /// Coordinated write that also creates any missing intermediate
    /// directories. Backs `:Edit <new-path>` which is allowed to
    /// invent a subfolder like `notes/inbox/today.lim`.
    static func writeNew(
        _ data: Data,
        to url: URL,
        presenter: NSFilePresenter?
    ) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        try write(data, to: url, presenter: presenter)
    }
}
