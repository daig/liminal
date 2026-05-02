import LiminalModel

public struct RenderDocument: Equatable, Sendable {
    public var source: String

    public init(document: LiminalDocument) {
        self.source = document.source
    }
}
