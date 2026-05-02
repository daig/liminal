import LiminalText

public struct DocumentSyntax: Equatable, Sendable {
    public var source: String

    public init(source: String) {
        self.source = source
    }
}

public struct ParseResult: Equatable, Sendable {
    public var document: DocumentSyntax
    public var diagnostics: [Diagnostic]

    public init(document: DocumentSyntax, diagnostics: [Diagnostic] = []) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

public struct LiminalParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> ParseResult {
        ParseResult(document: DocumentSyntax(source: source))
    }
}
