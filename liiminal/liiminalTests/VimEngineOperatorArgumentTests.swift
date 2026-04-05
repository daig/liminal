import XCTest
@testable import liiminal

@MainActor
final class VimEngineOperatorArgumentTests: XCTestCase {
    func testDeleteInnerWordParsesAsTextObjectArgument() {
        XCTAssertEqual(
            handle("diw"),
            .handled(.delete(.textObject(scope: .inner, kind: .word)))
        )
    }

    func testDeleteAroundParenAliasesResolveToSameSemanticObject() {
        XCTAssertEqual(
            handle("dab"),
            .handled(.delete(.textObject(scope: .around, kind: .parenBlock)))
        )
        XCTAssertEqual(
            handle("da("),
            .handled(.delete(.textObject(scope: .around, kind: .parenBlock)))
        )
        XCTAssertEqual(
            handle("da)"),
            .handled(.delete(.textObject(scope: .around, kind: .parenBlock)))
        )
    }

    func testChangeAndYankAcceptTextObjects() {
        XCTAssertEqual(
            handle("ci("),
            .handled(.change(.textObject(scope: .inner, kind: .parenBlock)))
        )
        XCTAssertEqual(
            handle("ya\""),
            .handled(.yank(.textObject(scope: .around, kind: .doubleQuote)))
        )
    }

    func testRepeatedOperatorsRemainCurrentLineArguments() {
        XCTAssertEqual(
            handle("3dd"),
            .handled(.delete(.currentLines(count: 3)))
        )
        XCTAssertEqual(
            handle("2cc"),
            .handled(.change(.currentLines(count: 2)))
        )
        XCTAssertEqual(
            handle("yy"),
            .handled(.yank(.currentLines(count: nil)))
        )
    }

    func testOperatorAndObjectCountsMultiply() {
        XCTAssertEqual(
            handle("2d3aw"),
            .handled(.delete(.textObject(scope: .around, kind: .word, count: 6)))
        )
    }

    func testChangeWordMotionBehaviorIsPreserved() {
        XCTAssertEqual(
            handle("cw"),
            .handled(.change(.characterwiseMotion(.wordForward)))
        )
    }

    private func handle(_ keys: String) -> VimHandleResult {
        let engine = VimEngine()
        var result: VimHandleResult = .ignored

        for character in keys {
            result = engine.handle(.character(character))
        }

        return result
    }
}
