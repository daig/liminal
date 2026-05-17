import Foundation
import Testing
@testable import Liminal

@Suite("PathResolver")
struct PathResolverTests {

    private static let vault = URL(fileURLWithPath: "/Users/test/notes", isDirectory: true)

    @Test("empty input returns nil")
    func emptyInput() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        #expect(resolver.resolve("") == nil)
        #expect(resolver.resolve("   ") == nil)
    }

    @Test("vault-relative paths resolve against the vault root and get .lim")
    func vaultRelativeResolution() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("foo")
        #expect(resolved == URL(fileURLWithPath: "/Users/test/notes/foo.lim"))
    }

    @Test("vault-relative paths preserve subdirectories")
    func vaultRelativeWithSubdir() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("subdir/note")
        #expect(resolved == URL(fileURLWithPath: "/Users/test/notes/subdir/note.lim"))
    }

    @Test("paths with explicit extension are not extended again")
    func explicitExtensionPreserved() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        #expect(resolver.resolve("readme.md") ==
                URL(fileURLWithPath: "/Users/test/notes/readme.md"))
        #expect(resolver.resolve("notes.lim") ==
                URL(fileURLWithPath: "/Users/test/notes/notes.lim"))
    }

    @Test("absolute paths bypass the vault root")
    func absolutePath() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("/etc/hosts.txt")
        #expect(resolved == URL(fileURLWithPath: "/etc/hosts.txt"))
    }

    @Test("absolute paths still get the .lim default when missing extension")
    func absoluteNoExtensionGetsLim() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("/Users/other/Documents/scratch")
        #expect(resolved ==
                URL(fileURLWithPath: "/Users/other/Documents/scratch.lim"))
    }

    @Test("~ expands to the user's home directory")
    func tildeExpansion() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("~/Documents/note")
        let expected = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/note.lim")
        #expect(resolved == expected)
    }

    @Test("bare ~ resolves to the home directory itself")
    func bareTilde() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        let resolved = resolver.resolve("~")
        // NSHomeDirectory has no extension, so .lim is appended.
        let expected = URL(fileURLWithPath: NSHomeDirectory()).appendingPathExtension("lim")
        #expect(resolved == expected)
    }

    @Test("vault-relative resolution requires a vault root")
    func vaultRelativeWithoutVault() {
        let resolver = PathResolver(vaultRoot: nil)
        #expect(resolver.resolve("foo") == nil)
    }

    @Test("absolute paths work without a vault root")
    func absoluteWithoutVault() {
        let resolver = PathResolver(vaultRoot: nil)
        let resolved = resolver.resolve("/tmp/scratch.lim")
        #expect(resolved == URL(fileURLWithPath: "/tmp/scratch.lim"))
    }

    @Test("whitespace around the input is stripped")
    func whitespaceStripped() {
        let resolver = PathResolver(vaultRoot: Self.vault)
        #expect(resolver.resolve("  foo  ") ==
                URL(fileURLWithPath: "/Users/test/notes/foo.lim"))
    }
}
