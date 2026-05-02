import LiminalModel
import LiminalSyntax

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
