import Cambium
import LiminalSemantics
import LiminalSyntax
import LiminalWorkspace

public final class LiminalEditorSession {
    public private(set) var source: String
    public private(set) var parseResult: LiminalParseResult?

    private let parseSession: LiminalParseSession

    public init(source: String = "", parseSession: LiminalParseSession = LiminalParseSession()) {
        self.source = source
        self.parseSession = parseSession
    }

    @discardableResult
    public func replaceSource(_ source: String, edits: [TextEdit] = []) throws -> LiminalParseResult {
        self.source = source
        let result = try parseSession.parse(source, edits: edits)
        self.parseResult = result
        return result
    }

    @discardableResult
    public func parse() throws -> LiminalParseResult {
        let result = try parseSession.parse(source)
        self.parseResult = result
        return result
    }

    public func lowerCurrentDocument() throws -> LiminalDocument {
        let result: LiminalParseResult
        if let parseResult {
            result = parseResult
        } else {
            result = try parse()
        }
        return LiminalLowerer().lower(result)
    }
}
