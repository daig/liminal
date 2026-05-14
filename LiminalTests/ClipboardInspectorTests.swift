import AppKit
import CambiumCore
import Testing
@testable import Liminal

@Suite("Clipboard inspector")
@MainActor
struct ClipboardInspectorTests {
    private func withSandboxPasteboard<R>(_ body: () throws -> R) rethrows -> R {
        let original = SystemPasteboard.pasteboard
        SystemPasteboard.pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "dev.sub.liminal.clipboard-inspector.tests.\(UUID().uuidString)"
        ))
        defer { SystemPasteboard.pasteboard = original }
        return try body()
    }

    @Test("snapshot reports an empty pasteboard")
    func emptySnapshot() throws {
        withSandboxPasteboard {
            let snapshot = ClipboardInspectorSnapshot.read()
            #expect(snapshot.entry == nil)
            #expect(snapshot.kindLabel == "none")
            #expect(snapshot.textByteLabel == "0 bytes")
            #expect(snapshot.structuralPayload == .absent)
        }
    }

    @Test("snapshot decodes structural fragment metadata")
    func structuralSnapshot() throws {
        try withSandboxPasteboard {
            let parsed = try LiminalParser().parse("One.\n")
            let forest = try #require(
                LiminalForest.cstVisualEntry(at: .zero, in: parsed.tree)
            )
            let capture = try StructuralCSTSelectionCapture.capture(
                forest: forest,
                source: "One.\n"
            )
            let data = try capture.clipboardPayload.serializedData()
            SystemPasteboard.write(
                text: capture.logicalText,
                kind: .cstForest,
                structuralPayloadData: data
            )

            let snapshot = ClipboardInspectorSnapshot.read()
            guard case .decoded(let info) = snapshot.structuralPayload else {
                Issue.record("expected decoded structural payload")
                return
            }
            #expect(snapshot.kindLabel == "cstForest")
            #expect(info.wrapperKind == .root)
            #expect(info.childKinds == [.paragraph])
            #expect(info.projectionKind == .identity)
            #expect(info.adapter == .rootDocumentItems)
        }
    }

    @Test("snapshot labels block quote content fragments")
    func blockQuoteContentSnapshot() throws {
        try withSandboxPasteboard {
            let source = """
            > foo
            > bar
            """
            let parsed = try LiminalParser().parse(source)
            let forest = try #require(
                firstBlockQuoteParagraphForest(in: parsed.tree)
            )
            let capture = try StructuralCSTSelectionCapture.capture(
                forest: forest,
                source: source
            )
            SystemPasteboard.write(
                text: capture.logicalText,
                kind: .cstForest,
                structuralPayloadData: try capture.clipboardPayload.serializedData()
            )

            let snapshot = ClipboardInspectorSnapshot.read()
            guard case .decoded(let info) = snapshot.structuralPayload else {
                Issue.record("expected decoded structural payload")
                return
            }
            #expect(info.wrapperKind == .blockQuote)
            #expect(info.childKinds == [.paragraph])
            #expect(info.projectionKind == .blockQuoteContent)
            #expect(info.adapter == .blockQuoteContent)
        }
    }

    @Test("snapshot labels unsupported table row fragments")
    func unsupportedTableRowSnapshot() throws {
        try withSandboxPasteboard {
            let source = """
            | A | B |
            | --- | --- |
            | C | D |
            """
            let parsed = try LiminalParser().parse(source)
            let offset = try byteOffset(of: "C", in: source)
            let row = try #require(tableRowForest(containing: offset, in: parsed.tree))
            let capture = try StructuralCSTSelectionCapture.capture(
                forest: row,
                source: source
            )
            SystemPasteboard.write(
                text: capture.logicalText,
                kind: .cstForest,
                structuralPayloadData: try capture.clipboardPayload.serializedData()
            )

            let snapshot = ClipboardInspectorSnapshot.read()
            guard case .decoded(let info) = snapshot.structuralPayload else {
                Issue.record("expected decoded structural payload")
                return
            }
            #expect(info.wrapperKind == .pipeTable)
            #expect(info.childKinds == [.pipeTableRow])
            #expect(info.projectionKind == .identity)
            #expect(info.adapter == .unsupported)
        }
    }

    private func firstBlockQuoteParagraphForest(
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        tree.withRoot { root in
            for rootIndex in 0..<root.childOrTokenCount {
                let rootChildKind = root.green { $0.child(at: rootIndex) }.kind
                guard rootChildKind == .blockQuote else { continue }

                return root.withChildNode(atRawIndex: rootIndex) { blockQuote in
                    for childIndex in 0..<blockQuote.childOrTokenCount {
                        let childKind = blockQuote.green { $0.child(at: childIndex) }.kind
                        guard childKind == .paragraph else { continue }
                        return LiminalForest(
                            parent: blockQuote.makeHandle(),
                            anchorChildIndex: childIndex,
                            headChildIndex: childIndex
                        )
                    }
                    return nil
                } ?? nil
            }
            return nil
        }
    }

    private func tableRowForest(
        containing offset: Int,
        in tree: SharedSyntaxTree<LiminalLanguage>
    ) -> LiminalForest? {
        guard var forest = LiminalForest.cstVisualEntry(
            at: TextSize(UInt32(offset)),
            in: tree
        ) else { return nil }
        while true {
            let parentKind = forest.parent.withCursor { $0.kind }
            let childKind = forest.parent.withCursor {
                $0.green { green in green.child(at: forest.anchorChildIndex) }.kind
            }
            if parentKind == .pipeTable, childKind == .pipeTableRow {
                return forest
            }
            guard let parent = forest.parentForest() else { return nil }
            forest = parent
        }
    }

    private func byteOffset(of needle: String, in source: String) throws -> Int {
        let range = try #require(source.range(of: needle))
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
    }
}
