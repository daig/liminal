import Foundation
import LiminalModel
import LiminalSchema
import LiminalText

public struct LiminalVault: Equatable, Sendable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }
}

public struct WorkspaceDiagnostic: Equatable, Sendable {
    public var fileURL: URL
    public var diagnostic: Diagnostic

    public init(fileURL: URL, diagnostic: Diagnostic) {
        self.fileURL = fileURL
        self.diagnostic = diagnostic
    }
}
