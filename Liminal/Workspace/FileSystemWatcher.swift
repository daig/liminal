import Darwin
import Foundation

/// Watches a vault directory for structural changes (file
/// added/removed/renamed). Uses `DispatchSource` on a directory fd —
/// the kernel signals when the directory inode changes, which fires
/// for additions, removals, and renames but not for content edits to
/// existing files. That's the right granularity here: open documents
/// already own their content; the watcher exists to surface
/// out-of-band file system changes.
///
/// Per-file content edits from outside the app aren't picked up; v1
/// accepts that gap. The next user edit on the open document will
/// re-index it; closing and reopening will re-read disk.
final class FileSystemWatcher {
    let rootURL: URL

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let onChange: @Sendable () -> Void

    init(rootURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.rootURL = rootURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Open the directory and begin dispatching change events to the
    /// `onChange` callback. Logs and silently no-ops on failure (the
    /// app remains usable — Cmd-click navigation just won't pick up
    /// out-of-band changes until the next vault scan).
    func start() {
        stop()
        let fd = open(rootURL.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("FileSystemWatcher: open failed for \(rootURL.path) errno=\(errno)")
            return
        }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .global(qos: .utility)
        )
        let onChange = self.onChange
        source.setEventHandler { onChange() }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.activate()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}
