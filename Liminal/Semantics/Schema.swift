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
    case target
    case type
    case inline
    case block
    case blocks
    case value
    case template
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
            // Document structure
            type("Document", kind: .document, fields: [
                field("items", .list(.named("DocumentItem")))
            ]),
            SchemaTypeDeclaration(
                name: "DocumentItem",
                kind: .value,
                definition: .variant(discriminator: "kind", cases: [
                    SchemaVariantCase(name: "block", fields: [
                        SchemaField(name: "block", type: .block)
                    ]),
                    SchemaVariantCase(name: "value", fields: [
                        SchemaField(name: "value", type: .value)
                    ]),
                    SchemaVariantCase(name: "schema", fields: [
                        SchemaField(name: "name", type: .str, isOptional: true),
                        SchemaField(name: "raw", type: .str)
                    ]),
                    SchemaVariantCase(name: "template", fields: [
                        SchemaField(name: "template", type: .template)
                    ]),
                    SchemaVariantCase(name: "directive", fields: [
                        SchemaField(name: "raw", type: .str)
                    ])
                ])
            ),
            type("Frontmatter", kind: .value, fields: [
                field("format", .enumeration(["yaml"])),
                field("raw", .str)
            ]),

            // Block surfaces
            type("Paragraph", kind: .block, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Heading", kind: .block, fields: [
                field("level", .int),
                field("body", .inline, modifiers: [.content])
            ]),
            type("ThematicBreak", kind: .block, fields: []),
            type("BlockQuote", kind: .block, fields: [
                field("body", .blocks, modifiers: [.content])
            ]),
            type("List", kind: .block, fields: [
                field("ordered", .bool),
                field("marker", .enumeration(["dash", "asterisk", "plus", "decimal_dot"])),
                field("start", .int, isOptional: true),
                field("items", .list(.named("ListItem")))
            ]),
            type("ListItem", kind: .value, fields: [
                field("task", .enumeration(["unchecked", "checked"]), isOptional: true),
                field("body", .blocks, modifiers: [.content])
            ]),
            type("CodeBlock", kind: .block, fields: [
                field("language", .str, isOptional: true),
                field("info", .str, isOptional: true),
                field("text", .str)
            ]),
            type("MathBlock", kind: .block, fields: [
                field("tex", .str)
            ]),
            type("HtmlBlock", kind: .block, fields: [
                field("raw", .str)
            ]),
            type("CommentBlock", kind: .block, fields: [
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
            ]),
            type("EmbedBlock", kind: .block, fields: [
                field("expected", .type, isOptional: true),
                field("fallback", .inline, isOptional: true),
                field("target", .target)
            ]),
            type("WikiEmbedBlock", kind: .block, fields: [
                field("target", .target),
                field("payload", .str, isOptional: true)
            ]),

            // Inline surfaces
            type("SoftBreak", kind: .inline, fields: []),
            type("HardBreak", kind: .inline, fields: []),
            type("Emphasis", kind: .inline, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Strong", kind: .inline, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Strikethrough", kind: .inline, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Highlight", kind: .inline, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("CodeSpan", kind: .inline, fields: [
                field("text", .str)
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
            type("WikiLink", kind: .inline, fields: [
                field("target", .target),
                field("body", .inline, isOptional: true, modifiers: [.content])
            ]),
            type("EmbedInline", kind: .inline, fields: [
                field("expected", .type, isOptional: true),
                field("fallback", .inline, isOptional: true),
                field("target", .target)
            ]),
            type("WikiEmbedInline", kind: .inline, fields: [
                field("target", .target),
                field("payload", .str, isOptional: true)
            ]),
            type("MathInline", kind: .inline, fields: [
                field("tex", .str)
            ]),
            type("HtmlInline", kind: .inline, fields: [
                field("raw", .str)
            ]),
            type("CommentInline", kind: .inline, fields: [
                field("raw", .str)
            ]),
            type("FootnoteInline", kind: .inline, fields: [
                field("body", .inline, modifiers: [.content])
            ]),
            type("Interpolation", kind: .inline, fields: [
                field("expr", .str)
            ]),

            // Value-position surfaces
            type("EmbedValue", kind: .value, fields: [
                field("expected", .type, isOptional: true),
                field("fallback", .inline, isOptional: true),
                field("target", .target)
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

    public func validate(
        _ document: LiminalDocument,
        against schema: LiminalSchema
    ) -> LiminalDocument {
        _ = schema
        return document
    }
}
