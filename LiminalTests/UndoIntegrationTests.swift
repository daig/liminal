import AppKit
import CambiumCore
import Testing
@testable import Liminal

@Suite("Editor undo integration")
@MainActor
struct UndoIntegrationTests {
    @Test("dw then undo restores the original text and session source")
    func deleteWordUndoRestoresSource() throws {
        let original = "one two\n"
        let fixture = try makeUndoFixture(original)
        fixture.placeCursor(atUTF16: 0)

        fixture.coordinator.applyOperator(
            .delete,
            target: .motion(.wordForwardStart),
            count: 1
        )

        #expect(fixture.textView.string != original)
        fixture.coordinator.undo(count: 1)

        #expect(fixture.textView.string == original)
        #expect(fixture.document.session.source == CambiumSource(original))
    }

    @Test("paste then undo restores the original text and redo reapplies it")
    func pasteUndoRedoRoundTrip() throws {
        let pasteboardName = NSPasteboard.Name("LiminalUndoIntegration-\(UUID().uuidString)")
        SystemPasteboard.pasteboard = NSPasteboard(name: pasteboardName)
        defer { SystemPasteboard.pasteboard = .general }

        let original = "ab\n"
        let fixture = try makeUndoFixture(original)
        fixture.placeCursor(atUTF16: 0)
        SystemPasteboard.write(text: "X", kind: .characterwise)

        fixture.coordinator.paste(after: true)
        let pasted = fixture.textView.string
        #expect(pasted != original)

        fixture.coordinator.undo(count: 1)
        #expect(fixture.textView.string == original)
        #expect(fixture.document.session.source == CambiumSource(original))

        fixture.coordinator.redo(count: 1)
        #expect(fixture.textView.string == pasted)
        #expect(fixture.document.session.source == CambiumSource(pasted))
    }

    @Test("change session undo restores the pre-change text")
    func changeSessionUndoRestoresSource() throws {
        let original = "one two\n"
        let fixture = try makeUndoFixture(original)
        fixture.placeCursor(atUTF16: 0)

        fixture.coordinator.applyOperator(
            .change,
            target: .motion(.wordForwardStart),
            count: 1
        )
        fixture.insertTextAtSelection("three ")
        fixture.coordinator.commitInsertSession()

        #expect(fixture.textView.string == "three two\n")
        fixture.coordinator.undo(count: 1)

        #expect(fixture.textView.string == original)
        #expect(fixture.document.session.source == CambiumSource(original))
    }

    @Test("undo repaint keeps syntax highlighting from the installed CST")
    func undoRepaintsHighlightsFromInstalledTree() throws {
        let wasEnabled = EditorPreferences.shared.highlightingEnabled
        EditorPreferences.shared.highlightingEnabled = true
        defer { EditorPreferences.shared.highlightingEnabled = wasEnabled }

        let original = "# Title\nbody\n"
        let fixture = try makeUndoFixture(original)
        fixture.coordinator.applyHighlights()
        let bodyLocation = (original as NSString).range(of: "body").location
        fixture.setKernAttribute(at: bodyLocation)
        #expect(fixture.fontIsBold(at: 2))

        fixture.placeCursor(atUTF16: 0)
        fixture.coordinator.applyOperator(
            .delete,
            target: .charsAtCursor(before: false),
            count: 1
        )
        fixture.coordinator.undo(count: 1)

        #expect(fixture.textView.string == original)
        #expect(fixture.document.session.parseResult == nil)
        #expect(fixture.fontIsBold(at: 2))
        #expect(fixture.hasKernAttribute(at: bodyLocation))
    }
}

@MainActor
private final class UndoFixture {
    let document: LiminalSourceDocument
    let coordinator: LiminalTextView.Coordinator
    let textView: VimTextView

    init(source: String) throws {
        let document = LiminalSourceDocument()
        try document.session.replaceSource(CambiumSource(source))
        self.document = document

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(textContainer)
        let textView = VimTextView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 400),
            textContainer: textContainer
        )
        textView.string = source
        textView.allowsUndo = false
        self.textView = textView

        let coordinator = LiminalTextView.Coordinator(document: document)
        coordinator.textView = textView
        textStorage.delegate = coordinator
        textView.delegate = coordinator
        textView.vimController = document.vimController
        document.vimController.delegate = coordinator
        document.seedInitialUndoSnapshotIfNeeded()
        self.coordinator = coordinator
    }

    func placeCursor(atUTF16 location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    func insertTextAtSelection(_ text: String) {
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    func fontIsBold(at location: Int) -> Bool {
        guard let font = textView.textStorage?.attribute(
            .font,
            at: location,
            effectiveRange: nil
        ) as? NSFont else {
            return false
        }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    func setKernAttribute(at location: Int) {
        textView.textStorage?.addAttribute(
            .kern,
            value: 7,
            range: NSRange(location: location, length: 1)
        )
    }

    func hasKernAttribute(at location: Int) -> Bool {
        textView.textStorage?.attribute(
            .kern,
            at: location,
            effectiveRange: nil
        ) != nil
    }
}

@MainActor
private func makeUndoFixture(_ source: String) throws -> UndoFixture {
    try UndoFixture(source: source)
}
