public struct SourceLocation: Equatable, Sendable {
    public var offset: Int
    public var line: Int
    public var column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }
}

public struct SourceRange: Equatable, Sendable {
    public var start: SourceLocation
    public var end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
}

public enum DiagnosticSeverity: String, Sendable {
    case note
    case warning
    case error
}

public struct Diagnostic: Equatable, Sendable {
    public var severity: DiagnosticSeverity
    public var message: String
    public var range: SourceRange?

    public init(severity: DiagnosticSeverity, message: String, range: SourceRange? = nil) {
        self.severity = severity
        self.message = message
        self.range = range
    }
}
