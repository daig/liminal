import Foundation
import XCTest
@testable import liiminal

final class VimTextObjectResolverTests: XCTestCase {
    func testWordAndWORDObjectsApplyWhitespaceRulesAndCounts() {
        let source = "alpha  beta\ngamma/delta  omega"

        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .word), marker: "pha"),
            "alpha"
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .word), marker: "pha"),
            "alpha  "
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .word), marker: "  b"),
            "  "
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .word), marker: "  b"),
            "  beta"
        )
        XCTAssertEqual(
            selectedText(
                in: source,
                object: .textObject(scope: .inner, kind: .word, count: 2),
                marker: "pha"
            ),
            "alpha  beta"
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .wordBig), marker: "mma/d"),
            "gamma/delta"
        )
    }

    func testSentenceObjectsResolveCharacterwise() {
        let source = "One. Two! Three?"

        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .sentence), marker: "One"),
            "One."
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .sentence), marker: "One"),
            "One. "
        )
        XCTAssertEqual(
            selectedText(
                in: source,
                object: .textObject(scope: .inner, kind: .sentence, count: 2),
                marker: "Two"
            ),
            "Two! Three?"
        )
    }

    func testSentenceObjectsStopAtParagraphBoundariesWithoutEarlierPunctuation() {
        let source = """
        $$
        x + 1
        $$

        %%hello%%
        bles efficient, "keyboard-driven editing without" a mouse, wow Command-line for saving/quitting, and Replace.

        """

        XCTAssertEqual(
            selectedText(
                in: source,
                object: .textObject(scope: .inner, kind: .sentence),
                marker: "bles"
            ),
            """
            %%hello%%
            bles efficient, "keyboard-driven editing without" a mouse, wow Command-line for saving/quitting, and Replace.
            """
        )
    }

    func testParagraphObjectsAreLinewise() {
        let source = "first\nsecond\n\nthird\n"

        let inner = selection(
            in: source,
            object: .textObject(scope: .inner, kind: .paragraph),
            marker: "first"
        )
        XCTAssertEqual(inner?.linewise, true)
        XCTAssertEqual(text(for: inner, in: source), "first\nsecond\n")

        let around = selection(
            in: source,
            object: .textObject(scope: .around, kind: .paragraph),
            marker: "first"
        )
        XCTAssertEqual(around?.linewise, true)
        XCTAssertEqual(text(for: around, in: source), "first\nsecond\n\n")
    }

    func testBlockObjectsExcludeOrIncludeDelimitersAndRejectEmptyInnerBlocks() {
        let source = "before (inner [value]) after"

        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .parenBlock), marker: "nner"),
            "inner [value]"
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .parenBlock), marker: "nner"),
            "(inner [value])"
        )
        XCTAssertNil(
            selection(
                in: "()",
                object: .textObject(scope: .inner, kind: .parenBlock),
                marker: "()"
            )
        )
    }

    func testQuoteObjectsHonorSingleLineRulesAndSpecialSecondInnerCount() {
        let source = "pre \"hi\" post\n\"two\nlines\""

        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .doubleQuote), marker: "hi"),
            "hi"
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .doubleQuote), marker: "hi"),
            "\"hi\" "
        )
        XCTAssertEqual(
            selectedText(
                in: source,
                object: .textObject(scope: .inner, kind: .doubleQuote, count: 2),
                marker: "hi"
            ),
            "\"hi\""
        )
        XCTAssertNil(
            selection(
                in: source,
                object: .textObject(scope: .inner, kind: .doubleQuote),
                marker: "\"two"
            )
        )
    }

    func testQuoteObjectsCanTargetTheNextQuotedRegionFromEarlierOnTheLine() {
        let source = "before \"quoted\" after"

        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .inner, kind: .doubleQuote), marker: "befo"),
            "quoted"
        )
        XCTAssertEqual(
            selectedText(in: source, object: .textObject(scope: .around, kind: .doubleQuote), marker: "befo"),
            "\"quoted\" "
        )
    }

    func testTagObjectsHandleEmptyInnerAndNestedCountExpansion() {
        let emptySource = "<div><span></span></div>"
        XCTAssertEqual(
            selectedText(in: emptySource, object: .textObject(scope: .inner, kind: .tagBlock), marker: "span"),
            "<span>"
        )
        XCTAssertEqual(
            selectedText(in: emptySource, object: .textObject(scope: .around, kind: .tagBlock), marker: "span"),
            "<span></span>"
        )

        let nestedSource = "<div><span>hi</span></div>"
        XCTAssertEqual(
            selectedText(
                in: nestedSource,
                object: .textObject(scope: .inner, kind: .tagBlock, count: 2),
                marker: "hi"
            ),
            "<span>hi</span>"
        )
    }

    func testLinewiseChangeResultKeepsClipboardStyle() {
        let source = "first\nsecond\n\nthird\n" as NSString
        let selection = VimSelectionResult(
            range: NSRange(location: 0, length: 13),
            cursorAnchor: 0,
            linewise: true
        )

        let result = VimChangeResolver.changeResult(replacing: selection, in: source, from: 0)
        XCTAssertEqual(result.replacementString, "\n")
        XCTAssertEqual(result.insertionLocation, 0)
        XCTAssertEqual(result.clipboardPayload?.style, .linewise)
        XCTAssertEqual(result.clipboardPayload?.text, "first\nsecond\n")
    }

    private func selection(
        in source: String,
        object: VimOperatorArgument,
        marker: String
    ) -> VimSelectionResult? {
        let text = source as NSString
        let markerRange = text.range(of: marker)
        XCTAssertNotEqual(markerRange.location, NSNotFound)

        guard case .object(.text(let objectArgument)) = object else {
            XCTFail("Expected text object argument")
            return nil
        }

        return VimTextObjectResolver.selectionResult(
            for: objectArgument,
            in: text,
            from: markerRange.location
        )
    }

    private func selectedText(
        in source: String,
        object: VimOperatorArgument,
        marker: String
    ) -> String? {
        text(for: selection(in: source, object: object, marker: marker), in: source)
    }

    private func text(for selection: VimSelectionResult?, in source: String) -> String? {
        guard let selection else { return nil }
        return (source as NSString).substring(with: selection.range)
    }
}
