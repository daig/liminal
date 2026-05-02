import LiminalLowering
import LiminalSyntax
import LiminalWorkspace

public struct LiminalEditorSession: Sendable {
    public var source: String

    public init(source: String = "") {
        self.source = source
    }

    public func parse() -> ParseResult {
        LiminalParser().parse(source)
    }
}
