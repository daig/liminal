import LiminalModel
import LiminalSyntax

public struct LiminalLowerer: Sendable {
    public init() {}

    public func lower(_ syntax: DocumentSyntax) -> LiminalDocument {
        LiminalDocument(source: syntax.source)
    }
}
