import XCTest
import LiminalText

final class LiminalTextTests: XCTestCase {
    func testDiagnosticCarriesMessageAndSeverity() {
        let diagnostic = Diagnostic(severity: .warning, message: "placeholder")

        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.message, "placeholder")
    }
}
