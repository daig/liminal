public struct RenderDocument: Equatable, Sendable {
    public var sourceText: String
    public var blocks: [LiminalBlock]

    public init(document: LiminalDocument) {
        self.sourceText = document.sourceText ?? ""
        self.blocks = document.blocks
    }
}
