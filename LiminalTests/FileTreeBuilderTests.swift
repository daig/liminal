import Foundation
import Testing
@testable import Liminal

@Suite("FileTreeBuilder")
struct FileTreeBuilderTests {
    private let root = URL(fileURLWithPath: "/tmp/v")

    @Test("empty input produces an empty tree")
    func emptyTree() {
        #expect(FileTreeBuilder.build(noteURLs: [], vaultRoot: root).isEmpty)
    }

    @Test("flat files at the root are leaf nodes, sorted alphabetically")
    func flatFilesSorted() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/Beta.lim"),
            URL(fileURLWithPath: "/tmp/v/Alpha.lim"),
            URL(fileURLWithPath: "/tmp/v/Charlie.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree.map(\.name) == ["Alpha.lim", "Beta.lim", "Charlie.lim"])
        #expect(tree.allSatisfy { $0.url != nil })
        #expect(tree.allSatisfy { $0.children == nil })
    }

    @Test("subfolders nest correctly")
    func subfolderNesting() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/notes/A.lim"),
            URL(fileURLWithPath: "/tmp/v/notes/B.lim"),
            URL(fileURLWithPath: "/tmp/v/Top.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree.count == 2)

        // Folders sort before files.
        #expect(tree[0].name == "notes")
        #expect(tree[0].isFolder)
        #expect(tree[0].children?.map(\.name) == ["A.lim", "B.lim"])

        #expect(tree[1].name == "Top.lim")
        #expect(!tree[1].isFolder)
    }

    @Test("deeply nested paths build a chain of folders")
    func deepNesting() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/a/b/c/Deep.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree.map(\.name) == ["a"])
        let b = tree[0].children
        #expect(b?.map(\.name) == ["b"])
        let c = b?[0].children
        #expect(c?.map(\.name) == ["c"])
        let leaves = c?[0].children
        #expect(leaves?.map(\.name) == ["Deep.lim"])
        #expect(leaves?[0].url?.lastPathComponent == "Deep.lim")
    }

    @Test("folders and files at the same level coexist; folders sort first")
    func mixedFolderFile() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/zzz.lim"),
            URL(fileURLWithPath: "/tmp/v/aaa-folder/Inside.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree.map(\.name) == ["aaa-folder", "zzz.lim"])
    }

    @Test("URLs outside the vault root are dropped")
    func outsideRootDropped() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/Inside.lim"),
            URL(fileURLWithPath: "/tmp/other/Outside.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree.map(\.name) == ["Inside.lim"])
    }

    @Test("node ids are stable canonical paths")
    func stableIDs() {
        let urls = [
            URL(fileURLWithPath: "/tmp/v/sub/A.lim"),
            URL(fileURLWithPath: "/tmp/v/sub/B.lim")
        ]
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: root)
        #expect(tree[0].id == "sub")
        #expect(tree[0].children?.map(\.id) == ["sub/A.lim", "sub/B.lim"])
    }

    @Test("trailing slash on vault root path doesn't double-prefix children")
    func trailingSlashRoot() {
        let urls = [URL(fileURLWithPath: "/tmp/v/Note.lim")]
        let withSlash = URL(fileURLWithPath: "/tmp/v/")
        let tree = FileTreeBuilder.build(noteURLs: urls, vaultRoot: withSlash)
        #expect(tree.map(\.name) == ["Note.lim"])
    }
}
