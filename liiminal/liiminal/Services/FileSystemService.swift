import Foundation

@Observable
final class FileSystemService {
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var monitoredFD: Int32 = -1

    func scanDirectory(at url: URL) -> [Note] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var notes: [Note] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ),
                values.isRegularFile == true
            else { continue }

            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let modified = values.contentModificationDate ?? .now
            notes.append(Note(url: fileURL, content: content, lastModified: modified))
        }

        return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createNote(titled title: String, in vaultURL: URL) throws -> URL {
        var filename = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty { filename = "Untitled" }
        if !filename.hasSuffix(".md") { filename += ".md" }

        var fileURL = vaultURL.appendingPathComponent(filename)

        // Deduplicate if file exists
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            let base = filename.replacingOccurrences(of: ".md", with: "")
            fileURL = vaultURL.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }

        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func startWatching(directory url: URL, onChange: @escaping () -> Void) {
        stopWatching()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        monitoredFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryMonitor = source
    }

    func stopWatching() {
        directoryMonitor?.cancel()
        directoryMonitor = nil
        monitoredFD = -1
    }

    deinit {
        stopWatching()
    }
}
