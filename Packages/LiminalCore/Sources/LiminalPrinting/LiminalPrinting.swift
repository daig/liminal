import LiminalModel
import LiminalSurfaces

public enum PrintMode: Sendable {
    case lossless
    case canonical
}

public struct LiminalPrinter: Sendable {
    public init() {}

    public func print(_ document: LiminalDocument, mode: PrintMode = .lossless) -> String {
        document.source
    }
}
