import Foundation
import Testing
@testable import Liminal

@Suite("CoordinatedFileIO")
struct CoordinatedFileIOTests {

    /// Build a unique temp directory for each test; clean up via
    /// `defer { try? FileManager.default.removeItem(at: dir) }`.
    private static func makeTempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CoordinatedFileIOTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("read+write round-trip for a local file")
    func readRoundTripsForLocalFile() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("hello.lim")
        try CoordinatedFileIO.write(Data("hello".utf8), to: url, presenter: nil)
        let read = try CoordinatedFileIO.read(at: url, presenter: nil) { try Data(contentsOf: $0) }
        #expect(read == Data("hello".utf8))
    }

    @Test("atomic write replaces a prior file's contents")
    func writeAtomicReplacesFile() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("scratch.lim")
        try CoordinatedFileIO.write(Data("first".utf8), to: url, presenter: nil)
        try CoordinatedFileIO.write(Data("second".utf8), to: url, presenter: nil)
        let read = try CoordinatedFileIO.read(at: url, presenter: nil) { try Data(contentsOf: $0) }
        #expect(read == Data("second".utf8))
    }

    @Test("writeNew creates intermediate directories along the path")
    func writeNewCreatesIntermediateDirectories() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nested = dir
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c.lim")
        try CoordinatedFileIO.writeNew(Data("nested".utf8), to: nested, presenter: nil)
        #expect(FileManager.default.fileExists(atPath: nested.path))
        let read = try Data(contentsOf: nested)
        #expect(read == Data("nested".utf8))
    }

    @Test("reading a missing file propagates the underlying error")
    func readMissingFileThrows() {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nope.lim")
        #expect(throws: (any Error).self) {
            _ = try CoordinatedFileIO.read(at: url, presenter: nil) {
                try Data(contentsOf: $0)
            }
        }
    }

    @Test("body's error bubbles out of the coordinator wrapper")
    func bodyErrorPropagates() {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("hello.lim")
        try? Data("x".utf8).write(to: url)
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            _ = try CoordinatedFileIO.read(at: url, presenter: nil) { _ in
                throw Boom()
            }
        }
    }

    @Test("write to a file the coordinator can't reach surfaces an error")
    func writeToUnreachablePathThrows() {
        // Use a path that requires nonexistent intermediate dirs that
        // we DON'T pre-create — atomic write should fail.
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let badURL = dir.appendingPathComponent("missing-dir/nope.lim")
        #expect(throws: (any Error).self) {
            try CoordinatedFileIO.write(Data("x".utf8), to: badURL, presenter: nil)
        }
    }
}
