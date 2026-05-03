import CambiumCore

public enum NodeKind: String, Hashable, Sendable {
    case document
    case block
    case inline
    case value
    case template
}

public struct QualifiedName: Hashable, Sendable, ExpressibleByStringLiteral {
    public var parts: [String]

    public init(parts: [String]) {
        self.parts = parts
    }

    public init(_ rawValue: String) {
        self.parts = rawValue.split(separator: ".").map(String.init)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var rawValue: String {
        parts.joined(separator: ".")
    }
}

public struct Anchor: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct FieldName: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct LiminalField: Equatable, Sendable {
    public var name: FieldName
    public var value: LiminalValue

    public init(name: FieldName, value: LiminalValue) {
        self.name = name
        self.value = value
    }
}

public enum LiminalScalar: Equatable, Sendable {
    case string(String)
    case integer(String)
    case number(String)
    case boolean(Bool)
    case null
    case bare(String)
}

public indirect enum LiminalValue: Equatable, Sendable {
    case scalar(LiminalScalar)
    case list([LiminalValue])
    case record([LiminalField])
    case node(LiminalNode)
    case inlineLiteral([LiminalInline])
    case blockLiteral([LiminalBlock])
    case reference(LiminalReference)
    case embed(LiminalEmbed)
}

public indirect enum LiminalInline: Equatable, Sendable {
    case text(String)
    case node(LiminalNode)
    case embed(LiminalEmbed)
    case interpolation(LiminalTemplateExpression)
}

public indirect enum LiminalBlock: Equatable, Sendable {
    case node(LiminalNode)
}

public enum LiminalDocumentItem: Equatable, Sendable {
    case block(LiminalBlock)
}

public indirect enum LiminalContent: Equatable, Sendable {
    case inline([LiminalInline])
    case blocks([LiminalBlock])
}

public struct LiminalNode: Equatable, Sendable {
    public var kind: NodeKind
    public var type: QualifiedName
    public var id: Anchor?
    public var fields: [LiminalField]
    public var content: LiminalContent?
    public var source: SurfaceForm?

    public init(
        kind: NodeKind,
        type: QualifiedName,
        id: Anchor? = nil,
        fields: [LiminalField] = [],
        content: LiminalContent? = nil,
        source: SurfaceForm? = nil
    ) {
        self.kind = kind
        self.type = type
        self.id = id
        self.fields = fields
        self.content = content
        self.source = source
    }
}

public enum LiminalReference: Equatable, Sendable {
    case local(Anchor)
    case qualified(namespace: QualifiedName, id: Anchor)
    case external(String)
}

public struct LiminalEmbed: Equatable, Sendable {
    public var expectedType: QualifiedName?
    public var fallback: [LiminalInline]
    public var target: String

    public init(
        expectedType: QualifiedName? = nil,
        fallback: [LiminalInline] = [],
        target: String
    ) {
        self.expectedType = expectedType
        self.fallback = fallback
        self.target = target
    }
}

public struct LiminalTemplateExpression: Equatable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct SurfaceForm: Equatable, Sendable {
    public var name: String?
    public var range: TextRange?
    public var rawSource: String?

    public init(
        name: String? = nil,
        range: TextRange? = nil,
        rawSource: String? = nil
    ) {
        self.name = name
        self.range = range
        self.rawSource = rawSource
    }
}

public struct LiminalDocument: Sendable {
    public var syntaxTree: SharedSyntaxTree<LiminalLanguage>?
    public var items: [LiminalDocumentItem]
    public var diagnostics: [LiminalDiagnostic]

    public var blocks: [LiminalBlock] {
        items.compactMap { item in
            guard case .block(let block) = item else {
                return nil
            }
            return block
        }
    }

    public init(
        syntaxTree: SharedSyntaxTree<LiminalLanguage>? = nil,
        items: [LiminalDocumentItem] = [],
        diagnostics: [LiminalDiagnostic] = []
    ) {
        self.syntaxTree = syntaxTree
        self.items = items
        self.diagnostics = diagnostics
    }

    public var sourceText: String? {
        syntaxTree?.withRoot { root in
            root.makeString()
        }
    }
}
