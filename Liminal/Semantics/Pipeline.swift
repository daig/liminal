public struct LiminalLowerer: Sendable {
    public init() {}

    public func lower(_ parseResult: LiminalParseResult) -> LiminalDocument {
        LiminalDocument(parseResult: parseResult)
    }
}

public enum PrintMode: Sendable {
    case lossless
    case canonical
}

public struct LiminalPrinter: Sendable {
    public init() {}

    public func print(_ document: LiminalDocument, mode: PrintMode = .lossless) -> String {
        switch mode {
        case .lossless:
            document.sourceText ?? ""
        case .canonical:
            document.sourceText ?? ""
        }
    }
}

public struct SurfaceIdentifier: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public protocol SurfaceReader: Sendable {
    var identifier: SurfaceIdentifier { get }
}

public protocol SurfacePrinter: Sendable {
    var identifier: SurfaceIdentifier { get }
}
