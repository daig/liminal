import CambiumBuilder
import CambiumCore
import CambiumIncremental

public enum LiminalKind: UInt32, Sendable {
    case sourceText = 1

    case root = 100
    case missing = 198
    case error = 199
}

extension LiminalKind: SyntaxKind {
    public static func rawKind(for kind: LiminalKind) -> RawSyntaxKind {
        RawSyntaxKind(kind.rawValue)
    }

    public static func kind(for raw: RawSyntaxKind) -> LiminalKind {
        guard let kind = LiminalKind(rawValue: raw.rawValue) else {
            preconditionFailure("Unknown Liminal syntax kind \(raw.rawValue)")
        }
        return kind
    }

    public static func staticText(for kind: LiminalKind) -> StaticString? {
        switch kind {
        case .sourceText, .root, .missing, .error:
            nil
        }
    }

    public static func name(for kind: LiminalKind) -> String {
        switch kind {
        case .sourceText:
            "sourceText"
        case .root:
            "root"
        case .missing:
            "missing"
        case .error:
            "error"
        }
    }
}

public enum LiminalLanguage: SyntaxLanguage {
    public typealias Kind = LiminalKind

    public static let rootKind: LiminalKind = .root
    public static let missingKind: LiminalKind = .missing
    public static let errorKind: LiminalKind = .error
    public static let serializationID = "dog.lambda.liminal.markup"
    public static let serializationVersion: UInt32 = 1

    public static func isNode(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .root, .missing, .error:
            true
        case .sourceText:
            false
        }
    }

    public static func isToken(_ kind: LiminalKind) -> Bool {
        !isNode(kind)
    }
}

public struct LiminalDiagnostic: Equatable, Sendable {
    public var severity: LiminalDiagnosticSeverity
    public var message: String
    public var range: TextRange

    public init(
        severity: LiminalDiagnosticSeverity,
        message: String,
        range: TextRange = .empty
    ) {
        self.severity = severity
        self.message = message
        self.range = range
    }
}

public enum LiminalDiagnosticSeverity: String, Equatable, Sendable {
    case note
    case warning
    case error
}

public struct LiminalParseResult: Sendable {
    public var tree: SharedSyntaxTree<LiminalLanguage>
    public var diagnostics: [LiminalDiagnostic]

    public init(
        tree: SharedSyntaxTree<LiminalLanguage>,
        diagnostics: [LiminalDiagnostic] = []
    ) {
        self.tree = tree
        self.diagnostics = diagnostics
    }

    public var sourceText: String {
        tree.withRoot { root in
            root.makeString()
        }
    }
}

public struct LiminalParser {
    public init() {}

    public func parse(_ source: String) throws -> LiminalParseResult {
        var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
        try buildRoot(source, with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        return LiminalParseResult(tree: tree)
    }

    fileprivate func parse(
        _ source: String,
        context: consuming GreenTreeContext<LiminalLanguage>
    ) throws -> LiminalParseSessionBuildOutput {
        var builder = GreenTreeBuilder<LiminalLanguage>(context: consume context)
        try buildRoot(source, with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        let nextContext = build.intoContext()
        return LiminalParseSessionBuildOutput(
            result: LiminalParseResult(tree: tree),
            context: consume nextContext
        )
    }

    private func buildRoot(
        _ source: String,
        with builder: inout GreenTreeBuilder<LiminalLanguage>
    ) throws {
        builder.startNode(.root)
        if !source.isEmpty {
            try builder.largeToken(.sourceText, text: source)
        }
        try builder.finishNode()
    }
}

struct LiminalParseSessionBuildOutput: ~Copyable {
    var result: LiminalParseResult
    var context: GreenTreeContext<LiminalLanguage>
}

public final class LiminalParseSession {
    private var context: GreenTreeContext<LiminalLanguage>?
    private var lastTree: SharedSyntaxTree<LiminalLanguage>?

    public init() {}

    @discardableResult
    public func parse(
        _ source: String,
        edits: [TextEdit] = []
    ) throws -> LiminalParseResult {
        _ = edits

        let parser = LiminalParser()
        let output: LiminalParseSessionBuildOutput
        if let existing = context.take() {
            output = try parser.parse(source, context: consume existing)
        } else {
            output = try parser.parse(
                source,
                context: GreenTreeContext(policy: .parseSession(maxEntries: 16_384))
            )
        }

        let result = output.result
        context = consume output.context
        lastTree = result.tree
        return result
    }

    public var currentTree: SharedSyntaxTree<LiminalLanguage>? {
        lastTree
    }
}
