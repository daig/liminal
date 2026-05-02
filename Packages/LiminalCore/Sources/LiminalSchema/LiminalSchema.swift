import LiminalModel

public struct LiminalSchema: Equatable, Sendable {
    public var name: String
    public var types: [SchemaTypeDeclaration]

    public init(name: String = "prelude", types: [SchemaTypeDeclaration] = []) {
        self.name = name
        self.types = types
    }

    public func type(named name: QualifiedName) -> SchemaTypeDeclaration? {
        types.first { $0.name == name }
    }
}

public struct SchemaTypeDeclaration: Equatable, Sendable {
    public var name: QualifiedName
    public var kind: NodeKind
    public var definition: SchemaTypeExpression
    public var modifiers: [SchemaModifier]

    public init(
        name: QualifiedName,
        kind: NodeKind,
        definition: SchemaTypeExpression,
        modifiers: [SchemaModifier] = []
    ) {
        self.name = name
        self.kind = kind
        self.definition = definition
        self.modifiers = modifiers
    }
}

public indirect enum SchemaTypeExpression: Equatable, Sendable {
    case str
    case bool
    case int
    case num
    case decimal
    case date
    case time
    case datetime
    case uri
    case id
    case inline
    case blocks
    case named(QualifiedName)
    case list(SchemaTypeExpression)
    case map(SchemaTypeExpression)
    case reference(SchemaTypeExpression)
    case embed(SchemaTypeExpression)
    case enumeration([String])
    case record([SchemaField])
    case variant(discriminator: FieldName, cases: [SchemaVariantCase])
}

public struct SchemaField: Equatable, Sendable {
    public var name: FieldName
    public var type: SchemaTypeExpression
    public var isOptional: Bool
    public var modifiers: [SchemaModifier]

    public init(
        name: FieldName,
        type: SchemaTypeExpression,
        isOptional: Bool = false,
        modifiers: [SchemaModifier] = []
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.modifiers = modifiers
    }
}

public struct SchemaVariantCase: Equatable, Sendable {
    public var name: String
    public var fields: [SchemaField]

    public init(name: String, fields: [SchemaField]) {
        self.name = name
        self.fields = fields
    }
}

public enum SchemaModifier: Equatable, Sendable {
    case content
    case defaultValue(LiminalValue)
    case surface(String)
    case readonly
    case deprecated(String)
}

public enum LiminalPrelude {
    public static var schema: LiminalSchema {
        LiminalSchema(name: "prelude", types: declarations)
    }

    public static var declarations: [SchemaTypeDeclaration] {
        [
            type("Document", kind: .value, fields: [
                field("blocks", .blocks)
            ]),
            type("Paragraph", kind: .block, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Heading", kind: .block, fields: [
                field("level", .int),
                field("body", .inline, modifiers: [.content])
            ]),
            type("Link", kind: .inline, fields: [
                field("href", .uri),
                field("title", .str, isOptional: true),
                field("body", .inline, modifiers: [.content])
            ]),
            type("Image", kind: .inline, fields: [
                field("src", .uri),
                field("alt", .inline),
                field("title", .str, isOptional: true)
            ]),
            type("CodeSpan", kind: .inline, fields: [
                field("text", .str)
            ]),
            type("CodeBlock", kind: .block, fields: [
                field("language", .str, isOptional: true),
                field("text", .str)
            ]),
            type("Math", kind: .inline, fields: [
                field("display", .bool),
                field("tex", .str)
            ]),
            type("Html", kind: .inline, fields: [
                field("raw", .str)
            ]),
            type("Table", kind: .block, fields: [
                field("columns", .list(.named("Column"))),
                field("rows", .list(.named("Row"))),
                field("caption", .inline, isOptional: true)
            ]),
            type("Column", kind: .value, fields: [
                field("label", .inline),
                field("align", .enumeration(["left", "center", "right"]), isOptional: true)
            ]),
            type("Row", kind: .value, fields: [
                field("cells", .list(.inline))
            ])
        ]
    }

    private static func type(
        _ name: QualifiedName,
        kind: NodeKind,
        fields: [SchemaField],
        modifiers: [SchemaModifier] = []
    ) -> SchemaTypeDeclaration {
        SchemaTypeDeclaration(
            name: name,
            kind: kind,
            definition: .record(fields),
            modifiers: modifiers
        )
    }

    private static func field(
        _ name: FieldName,
        _ type: SchemaTypeExpression,
        isOptional: Bool = false,
        modifiers: [SchemaModifier] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: type,
            isOptional: isOptional,
            modifiers: modifiers
        )
    }
}

public struct SchemaValidator: Sendable {
    public init() {}

    public func validate(_ document: LiminalDocument, against schema: LiminalSchema) -> LiminalDocument {
        document
    }
}
