import CambiumBuilder
import CambiumCore
import CambiumIncremental
import CambiumSyntaxMacros

@CambiumSyntaxKind
public enum LiminalKind: UInt32, Sendable {
    case whitespace = 1
    case newline = 2

    @StaticText("@")
    case atSign = 10
    @StaticText("!")
    case bang = 11
    @StaticText("&")
    case ampersand = 12
    @StaticText("#")
    case hash = 13
    @StaticText("^")
    case caret = 14
    @StaticText("$")
    case dollar = 15
    @StaticText("[")
    case leftBracket = 16
    @StaticText("]")
    case rightBracket = 17
    @StaticText("(")
    case leftParen = 18
    @StaticText(")")
    case rightParen = 19
    @StaticText("{")
    case leftBrace = 20
    @StaticText("}")
    case rightBrace = 21
    @StaticText("<")
    case lessThan = 22
    @StaticText(">")
    case greaterThan = 23
    @StaticText(",")
    case comma = 24
    @StaticText(":")
    case colon = 25
    @StaticText("|")
    case pipe = 26
    @StaticText("`")
    case backtick = 27
    @StaticText("~")
    case tilde = 28
    @StaticText("*")
    case star = 29
    @StaticText("_")
    case underscore = 30
    @StaticText("-")
    case dash = 31
    @StaticText("+")
    case plus = 32
    @StaticText(".")
    case dot = 33
    @StaticText("/")
    case slash = 34
    @StaticText("\\")
    case backslash = 35
    @StaticText("%")
    case percent = 36
    @StaticText("=")
    case equals = 37
    @StaticText("?")
    case questionMark = 38
    @StaticText("'")
    case singleQuote = 39
    @StaticText("\"")
    case doubleQuote = 40

    case hashRun = 50
    case colonRun = 51
    case fenceRun = 52
    case listMarker = 53
    case orderedListMarker = 54
    case taskMarker = 55
    case identifier = 56
    case qname = 57
    case anchor = 58
    case fieldName = 59
    case quotedStringLiteral = 60
    case integerLiteral = 61
    case numberLiteral = 62
    case booleanLiteral = 63
    case nullLiteral = 64
    case bareScalarLiteral = 65
    case inlineText = 66
    case codeText = 67
    case mathText = 68
    case htmlText = 69
    case frontmatterText = 70
    case commentText = 71
    case rawPayloadText = 72
    case linkDestinationText = 73
    case linkTitleText = 74
    case wikiTargetText = 75
    case embedTargetText = 76
    case interpolationText = 77
    case externalReferenceText = 78
    case schemaText = 79
    case templateText = 80
    case directiveText = 81

    case root = 100
    case blankLine = 101
    case frontmatter = 102
    case directive = 103
    case valueDeclaration = 104
    case paragraph = 105
    case atxHeading = 106
    case thematicBreak = 107
    case list = 108
    case listItem = 109
    case blockQuote = 110
    case fencedCodeBlock = 111
    case mathBlock = 112
    case htmlBlock = 113
    case commentBlock = 114
    case typedBlock = 115
    case pipeTable = 116
    case pipeTableHeader = 117
    case pipeTableDelimiter = 118
    case pipeTableRow = 119
    case pipeTableCell = 120
    case structuredEmbedBlock = 121
    case wikiEmbedBlock = 122
    case blockIdSuffix = 123

    case inlineContent = 200
    case softBreak = 201
    case hardBreak = 202
    case codeSpan = 203
    case escapedPunctuation = 204
    case emphasis = 205
    case strong = 206
    case strikethrough = 207
    case highlight = 208
    case mdLink = 209
    case mdImage = 210
    case autolink = 211
    case wikilink = 212
    case wikiEmbed = 213
    case structuredEmbed = 214
    case mathInline = 215
    case htmlInline = 216
    case inlineComment = 217
    case footnoteInline = 218
    case interpolation = 219
    case typedInline = 220
    case linkLabel = 221
    case linkDestination = 222
    case linkTitle = 223
    case wikiTarget = 224
    case embedTarget = 225

    case value = 300
    case typedConstructor = 301
    case fields = 302
    case field = 303
    case listValue = 304
    case recordValue = 305
    case inlineLiteral = 306
    case blockLiteral = 307
    case reference = 308
    case externalReference = 309
    case structuredEmbedValue = 310
    case scalarValue = 311
    case schemaBlock = 312
    case schemaHeader = 313
    case schemaTypeDeclaration = 314
    case schemaTemplateTypeDeclaration = 315
    case schemaTypeExpression = 316
    case schemaField = 317
    case schemaModifier = 318
    case templateBlock = 319
    case templateSignature = 320
    case templateParameter = 321
    case templateBody = 322
    case useDirective = 323

    case missing = 900
    case error = 901
}

public enum LiminalLanguage: SyntaxLanguage {
    public typealias Kind = LiminalKind

    public static let rootKind: LiminalKind = .root
    public static let missingKind: LiminalKind = .missing
    public static let errorKind: LiminalKind = .error
    public static let serializationID = "dog.lambda.liminal.markup"
    public static let serializationVersion: UInt32 = 2

    public static func isTrivia(_ kind: LiminalKind) -> Bool {
        switch kind {
        case .whitespace, .newline:
            true
        default:
            false
        }
    }

    public static func isNode(_ kind: LiminalKind) -> Bool {
        switch kind {
        case
            .root,
            .blankLine,
            .frontmatter,
            .directive,
            .valueDeclaration,
            .paragraph,
            .atxHeading,
            .thematicBreak,
            .list,
            .listItem,
            .blockQuote,
            .fencedCodeBlock,
            .mathBlock,
            .htmlBlock,
            .commentBlock,
            .typedBlock,
            .pipeTable,
            .pipeTableHeader,
            .pipeTableDelimiter,
            .pipeTableRow,
            .pipeTableCell,
            .structuredEmbedBlock,
            .wikiEmbedBlock,
            .blockIdSuffix,
            .inlineContent,
            .softBreak,
            .hardBreak,
            .codeSpan,
            .escapedPunctuation,
            .emphasis,
            .strong,
            .strikethrough,
            .highlight,
            .mdLink,
            .mdImage,
            .autolink,
            .wikilink,
            .wikiEmbed,
            .structuredEmbed,
            .mathInline,
            .htmlInline,
            .inlineComment,
            .footnoteInline,
            .interpolation,
            .typedInline,
            .linkLabel,
            .linkDestination,
            .linkTitle,
            .wikiTarget,
            .embedTarget,
            .value,
            .typedConstructor,
            .fields,
            .field,
            .listValue,
            .recordValue,
            .inlineLiteral,
            .blockLiteral,
            .reference,
            .externalReference,
            .structuredEmbedValue,
            .scalarValue,
            .schemaBlock,
            .schemaHeader,
            .schemaTypeDeclaration,
            .schemaTemplateTypeDeclaration,
            .schemaTypeExpression,
            .schemaField,
            .schemaModifier,
            .templateBlock,
            .templateSignature,
            .templateParameter,
            .templateBody,
            .useDirective,
            .missing,
            .error:
            true
        default:
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

    public var rootSyntax: RootSyntax {
        RootSyntax(unchecked: tree.rootHandle())
    }
}

public struct LiminalParser {
    public init() {}

    public func parse(_ source: String) throws -> LiminalParseResult {
        var builder = GreenTreeBuilder<LiminalLanguage>(policy: .documentLocal)
        var parser = LiminalSlice1CSTParser(source: source)
        try parser.parse(with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        return LiminalParseResult(tree: tree, diagnostics: parser.diagnostics)
    }

    fileprivate func parse(
        _ source: String,
        context: consuming GreenTreeContext<LiminalLanguage>
    ) throws -> LiminalParseSessionBuildOutput {
        var builder = GreenTreeBuilder<LiminalLanguage>(context: consume context)
        var parser = LiminalSlice1CSTParser(source: source)
        try parser.parse(with: &builder)
        let build = try builder.finish()
        let tree = build.snapshot.makeSyntaxTree().intoShared()
        let nextContext = build.intoContext()
        return LiminalParseSessionBuildOutput(
            result: LiminalParseResult(tree: tree, diagnostics: parser.diagnostics),
            context: consume nextContext
        )
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
