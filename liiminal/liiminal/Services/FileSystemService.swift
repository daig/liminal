import Foundation

@Observable
final class FileSystemService {
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var monitoredFD: Int32 = -1

    func scanDirectory(at url: URL) -> [Note] {
        let fm = FileManager.default
        let basePath = url.standardizedFileURL.path
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
            let standardizedPath = fileURL.standardizedFileURL.path
            let relativePath = String(standardizedPath.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            notes.append(
                Note(
                    url: fileURL,
                    relativePath: relativePath,
                    content: content,
                    lastModified: modified
                )
            )
        }

        return notes.sorted {
            let lhsTitleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            if lhsTitleOrder == .orderedSame {
                return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath)
                    == .orderedAscending
            }
            return lhsTitleOrder == .orderedAscending
        }
    }

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createNote(titled title: String, in vaultURL: URL) throws -> URL {
        try createNote(atRelativePath: title, in: vaultURL)
    }

    func createNote(atRelativePath relativePath: String, in vaultURL: URL) throws -> URL {
        var normalizedPath = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))

        if normalizedPath.isEmpty {
            normalizedPath = "Untitled"
        }

        if !normalizedPath.lowercased().hasSuffix(".md") {
            normalizedPath += ".md"
        }

        var fileURL = vaultURL.appendingPathComponent(normalizedPath)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            let extensionPart = fileURL.pathExtension
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let deduplicatedStem = "\(stem) \(counter)"
            fileURL = directoryURL.appendingPathComponent(deduplicatedStem)
            if !extensionPart.isEmpty {
                fileURL = fileURL.appendingPathExtension(extensionPart)
            }
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
