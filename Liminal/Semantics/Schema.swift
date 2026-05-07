import CambiumCore

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
    /// Sentinel for type expressions the parser/lowerer didn't structure
    /// in this slice (e.g. `map<T>`, `ref<T>`, `embed<T>`, `enum`,
    /// `variant` — deferred to a follow-up TypeExpr sub-slice). The
    /// validator treats `.unknown` as "skip type-shape validation"; field
    /// presence and `isOptional` are still checked. Removed when the full
    /// TypeExpr surface lands.
    case unknown
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
            ]),

            // Template control structures (spec §10). Their reserved
            // surface forms are `:::if{test: …}` and `:::for{item: …, in: …}`.
            // The expression slots use `.unknown` because the value
            // parser captures `test` / `item` / `in` as bare scalars
            // today; structural template-expression parsing inside
            // typed-block fields remains future work — `.unknown` keeps
            // the validator's shape check permissive while still
            // enforcing field presence (`isOptional: false`).
            type("if", kind: .block, fields: [
                field("test", .unknown),
                field("body", .blocks, modifiers: [.content])
            ]),
            type("for", kind: .block, fields: [
                field("item", .unknown),
                field("in", .unknown),
                field("body", .blocks, modifiers: [.content])
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

public struct LiminalSchemaResolver: Sendable {
    public enum Resolution: Equatable, Sendable {
        case prelude(SchemaTypeDeclaration)
        case userDeclared(
            name: QualifiedName,
            kind: NodeKind?,
            definition: SchemaTypeExpression?
        )
        case importedNamespace(alias: String)
        case unresolved
    }

    /// One `::use type ... as <alias>` entry indexed for type lookup.
    /// `filter == nil` means "no `only { … }` was supplied — import all".
    /// `filter == []` means "explicit empty filter — import nothing".
    /// A non-empty array is a whitelist of qnames within the imported
    /// schema's namespace.
    private struct AliasedTypeImport: Sendable {
        var alias: String
        var filter: [QualifiedName]?
    }

    public let prelude: LiminalSchema
    public let diagnostics: [LiminalDiagnostic]

    private let preludeIndex: [QualifiedName: SchemaTypeDeclaration]
    private let userIndex: [QualifiedName: LiminalUserSchemaTypeDeclaration]
    private let typeImports: [String: AliasedTypeImport]

    public init(prelude: LiminalSchema, document: LiminalDocument) {
        self.prelude = prelude
        var preludeIndex: [QualifiedName: SchemaTypeDeclaration] = [:]
        for declaration in prelude.types {
            preludeIndex[declaration.name] = declaration
        }

        var userIndex: [QualifiedName: LiminalUserSchemaTypeDeclaration] = [:]
        var typeImports: [String: AliasedTypeImport] = [:]
        var diagnostics: [LiminalDiagnostic] = []
        var reportedShadows: Set<QualifiedName> = []
        var reportedDuplicates: Set<QualifiedName> = []
        // Track every qname seen in any user `:::schema` block, even when
        // shadowed. Without this, a doubly-declared shadowed name would
        // emit only the shadow warning since the second occurrence never
        // makes it into `userIndex`.
        var seenUserDeclarations: Set<QualifiedName> = []

        for item in document.items {
            switch item {
            case .schema(let block):
                for declaration in block.declarations {
                    let isPreludeShadow = preludeIndex[declaration.name] != nil
                    let isUserDuplicate = !seenUserDeclarations.insert(declaration.name).inserted

                    if isPreludeShadow,
                       reportedShadows.insert(declaration.name).inserted
                    {
                        diagnostics.append(LiminalDiagnostic(
                            severity: .warning,
                            message: "user-declared type '\(declaration.name.rawValue)' shadows prelude type; prelude shape will be used",
                            range: block.source?.range ?? .empty
                        ))
                    }
                    if isUserDuplicate,
                       reportedDuplicates.insert(declaration.name).inserted
                    {
                        diagnostics.append(LiminalDiagnostic(
                            severity: .warning,
                            message: "duplicate user-declared type '\(declaration.name.rawValue)'; first declaration will be used",
                            range: block.source?.range ?? .empty
                        ))
                    }
                    if !isPreludeShadow, !isUserDuplicate {
                        userIndex[declaration.name] = declaration
                    }
                }
            case .directive(let directive):
                // Only `::use type ... as <alias>` participates in type
                // resolution. `::use data ...` affects value-level reference
                // resolution (separate arc) and must not suppress
                // unresolved-type warnings under `@<alias>.X`.
                guard directive.name == "use",
                      directive.useKind == .type,
                      let alias = directive.alias
                else {
                    continue
                }
                typeImports[alias] = AliasedTypeImport(
                    alias: alias,
                    filter: directive.filterQNames
                )
            case .block, .value, .template:
                continue
            }
        }

        self.preludeIndex = preludeIndex
        self.userIndex = userIndex
        self.typeImports = typeImports
        self.diagnostics = diagnostics
    }

    public func resolve(_ name: QualifiedName) -> Resolution {
        if let declaration = preludeIndex[name] {
            return .prelude(declaration)
        }
        if let declaration = userIndex[name] {
            return .userDeclared(
                name: declaration.name,
                kind: declaration.kind,
                definition: declaration.definition
            )
        }
        // Alias-qualified type lookup: `@ext.Person` against `::use type
        // ... as ext`. Requires at least one segment past the alias (a
        // bare `@ext` carries no type within the imported namespace) and
        // respects the import filter.
        if name.parts.count >= 2,
           let prefix = name.parts.first,
           let importEntry = typeImports[prefix]
        {
            let imported = QualifiedName(parts: Array(name.parts.dropFirst()))
            if let filter = importEntry.filter, !filter.contains(imported) {
                return .unresolved
            }
            return .importedNamespace(alias: prefix)
        }
        return .unresolved
    }
}

public struct SchemaValidator: Sendable {
    public init() {}

    public func validate(
        _ document: LiminalDocument,
        against schema: LiminalSchema
    ) -> LiminalDocument {
        let resolver = LiminalSchemaResolver(prelude: schema, document: document)
        var diagnostics = document.diagnostics
        diagnostics.append(contentsOf: resolver.diagnostics)
        for item in document.items {
            walk(item, resolver: resolver, diagnostics: &diagnostics)
        }
        return LiminalDocument(
            syntaxTree: document.syntaxTree,
            items: document.items,
            diagnostics: diagnostics
        )
    }

    private func walk(
        _ item: LiminalDocumentItem,
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        switch item {
        case .block(.node(let node)), .value(let node):
            validate(node: node, resolver: resolver, diagnostics: &diagnostics)
        case .template(let template):
            // Template signature and shell are deferred to Phase 3c structured
            // parsing. The body items, however, are normal lowered document
            // items and should be validated so unresolved or malformed nodes
            // inside templates are reported. (`:::if` / `:::for` lower as
            // generic typed blocks today and will surface as unresolved-type
            // warnings until Phase 3c specializes them.)
            for nestedItem in template.items {
                walk(nestedItem, resolver: resolver, diagnostics: &diagnostics)
            }
        case .schema, .directive:
            // Schema and directive bodies are raw text today; structured
            // RHS parsing (TypeExpr) lands in Phase 3c. Nothing to validate
            // yet.
            break
        }
    }

    private func validate(
        node: LiminalNode,
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        let typeName = node.type
        switch resolver.resolve(typeName) {
        case .prelude(let declaration):
            if declaration.kind != node.kind {
                diagnostics.append(diagnostic(
                    .error,
                    "type '\(typeName.rawValue)' expects kind '\(declaration.kind.rawValue)' but node has kind '\(node.kind.rawValue)'",
                    node: node
                ))
            }

            if case .record(let declaredFields) = declaration.definition {
                validate(
                    fields: node.fields,
                    against: declaredFields,
                    onType: typeName,
                    node: node,
                    diagnostics: &diagnostics
                )
            }

            recurse(into: node, resolver: resolver, diagnostics: &diagnostics)

        case .userDeclared(_, let kind, let definition):
            // Kind check first.
            if let kind, kind != node.kind {
                diagnostics.append(diagnostic(
                    .error,
                    "type '\(typeName.rawValue)' expects kind '\(kind.rawValue)' but node has kind '\(node.kind.rawValue)'",
                    node: node
                ))
            }
            // Phase 3c.2: when the user-declared RHS parsed as a record,
            // validate fields against it the same way prelude records are
            // checked. RHS forms the parser doesn't yet structurally cover
            // (variant/enum/map/ref/embed) leave `definition == nil` and
            // fall through to kind-only checking.
            if case .record(let declaredFields) = definition {
                validate(
                    fields: node.fields,
                    against: declaredFields,
                    onType: typeName,
                    node: node,
                    diagnostics: &diagnostics
                )
            }
            recurse(into: node, resolver: resolver, diagnostics: &diagnostics)

        case .importedNamespace:
            // External alias prefix is recognized; actual type shape isn't
            // loaded (workspace concern). Skip validation, but recurse so any
            // nested local types still validate.
            recurse(into: node, resolver: resolver, diagnostics: &diagnostics)

        case .unresolved:
            diagnostics.append(diagnostic(
                .warning,
                "unresolved type '\(typeName.rawValue)'",
                node: node
            ))
            // Still recurse: nested constructs may use known types.
            recurse(into: node, resolver: resolver, diagnostics: &diagnostics)
        }
    }

    private func validate(
        fields nodeFields: [LiminalField],
        against declaredFields: [SchemaField],
        onType typeName: QualifiedName,
        node: LiminalNode,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        // Fields marked with .content live in node.content (the body),
        // not in node.fields. The lowerer maps `body: inline @content`
        // declarations into node.content so we look there for them.
        let declaredByName = firstOccurrenceLookup(of: declaredFields, by: \.name)

        // v0.2 §8.2: duplicate fields are syntactically valid; the schema
        // pass reports them as a single error per duplicated name. We keep
        // the first occurrence for shape checking and skip the rest.
        let nodeFieldsByName = duplicateAwareLookup(
            of: nodeFields,
            onType: typeName,
            node: node,
            diagnostics: &diagnostics
        )

        for declared in declaredFields {
            if declared.modifiers.contains(.content) {
                // @content fields can be supplied via the surface body
                // (node.content) or as an explicit record field — v0.2's
                // generic typed/value forms use the explicit shape, e.g.
                // `@ListItem{body: @{First}}` and `@BlockQuote{body: @{...}}`
                // (spec §6.4, §6.5). Validate whichever form the user used
                // against the declared content type; the field is required
                // only if neither form is provided.
                validateContentField(
                    declared: declared,
                    explicit: nodeFieldsByName[declared.name],
                    onType: typeName,
                    node: node,
                    diagnostics: &diagnostics
                )
            } else if let presentField = nodeFieldsByName[declared.name] {
                validate(
                    value: presentField.value,
                    against: declared.type,
                    isOptional: declared.isOptional,
                    fieldName: declared.name,
                    onType: typeName,
                    node: node,
                    diagnostics: &diagnostics
                )
            } else if !declared.isOptional {
                diagnostics.append(diagnostic(
                    .error,
                    "missing required field '\(declared.name.rawValue)' on type '\(typeName.rawValue)'",
                    node: node
                ))
            }
        }

        // Unknown fields (declared lookup misses), once per name in source
        // order. Fields whose name matches a declared @content slot are
        // valid — they were validated above as the explicit content form.
        var reported: Set<FieldName> = []
        for nodeField in nodeFields {
            guard reported.insert(nodeField.name).inserted else { continue }

            if declaredByName[nodeField.name] == nil {
                diagnostics.append(diagnostic(
                    .warning,
                    "unknown field '\(nodeField.name.rawValue)' on type '\(typeName.rawValue)'",
                    node: node
                ))
            }
        }
    }

    private func validate(
        value: LiminalValue,
        against type: SchemaTypeExpression,
        isOptional: Bool,
        fieldName: FieldName,
        onType typeName: QualifiedName,
        node: LiminalNode,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        if isNull(value) {
            if !isOptional {
                diagnostics.append(diagnostic(
                    .error,
                    "field '\(fieldName.rawValue)' on type '\(typeName.rawValue)' has the wrong shape for declared type",
                    node: node
                ))
            }
            return
        }
        if !valueMatches(value, type: type) {
            diagnostics.append(diagnostic(
                .error,
                "field '\(fieldName.rawValue)' on type '\(typeName.rawValue)' has the wrong shape for declared type",
                node: node
            ))
        }
    }

    private func validateContentField(
        declared: SchemaField,
        explicit: LiminalField?,
        onType typeName: QualifiedName,
        node: LiminalNode,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        // Per spec §8.1, the constructor body maps to the @content field.
        // Supplying both an explicit field and a surface body for the same
        // @content slot doubles the logical content value with no defined
        // precedence; report it.
        if explicit != nil, node.content != nil {
            diagnostics.append(diagnostic(
                .error,
                "type '\(typeName.rawValue)' supplies the @content body '\(declared.name.rawValue)' both as an explicit field and as the surface body; pick one",
                node: node
            ))
        }

        if let explicit {
            validate(
                value: explicit.value,
                against: declared.type,
                isOptional: declared.isOptional,
                fieldName: declared.name,
                onType: typeName,
                node: node,
                diagnostics: &diagnostics
            )
        }
        if node.content != nil {
            validate(
                content: node.content,
                declared: declared,
                onType: typeName,
                node: node,
                diagnostics: &diagnostics
            )
        } else if explicit == nil, !declared.isOptional {
            diagnostics.append(diagnostic(
                .error,
                "missing required content '\(declared.name.rawValue)' on type '\(typeName.rawValue)'",
                node: node
            ))
        }
    }

    private func duplicateAwareLookup(
        of fields: [LiminalField],
        onType typeName: QualifiedName,
        node: LiminalNode,
        diagnostics: inout [LiminalDiagnostic]
    ) -> [FieldName: LiminalField] {
        var lookup: [FieldName: LiminalField] = [:]
        var reportedDuplicates: Set<FieldName> = []

        for field in fields {
            if lookup[field.name] != nil {
                if !reportedDuplicates.contains(field.name) {
                    diagnostics.append(diagnostic(
                        .error,
                        "duplicate field '\(field.name.rawValue)' on type '\(typeName.rawValue)'",
                        node: node
                    ))
                    reportedDuplicates.insert(field.name)
                }
                continue
            }
            lookup[field.name] = field
        }
        return lookup
    }

    private func firstOccurrenceLookup<Value, Key: Hashable>(
        of values: [Value],
        by key: KeyPath<Value, Key>
    ) -> [Key: Value] {
        var lookup: [Key: Value] = [:]
        for value in values where lookup[value[keyPath: key]] == nil {
            lookup[value[keyPath: key]] = value
        }
        return lookup
    }

    private func isNull(_ value: LiminalValue) -> Bool {
        if case .scalar(.null) = value { return true }
        return false
    }

    private func validate(
        content: LiminalContent?,
        declared: SchemaField,
        onType typeName: QualifiedName,
        node: LiminalNode,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        guard let content else {
            if !declared.isOptional {
                diagnostics.append(diagnostic(
                    .error,
                    "missing required content '\(declared.name.rawValue)' on type '\(typeName.rawValue)'",
                    node: node
                ))
            }
            return
        }

        switch (content, declared.type) {
        case (.inline, .inline), (.blocks, .blocks):
            return
        case (.inline, .blocks):
            diagnostics.append(diagnostic(
                .error,
                "content '\(declared.name.rawValue)' on type '\(typeName.rawValue)' expects 'blocks' but got inline content",
                node: node
            ))
        case (.blocks, .inline):
            diagnostics.append(diagnostic(
                .error,
                "content '\(declared.name.rawValue)' on type '\(typeName.rawValue)' expects 'inline' but got block content",
                node: node
            ))
        default:
            // Other declared content shapes are unusual for @content; leave
            // detailed checking to a future iteration.
            return
        }
    }

    private func valueMatches(_ value: LiminalValue, type: SchemaTypeExpression) -> Bool {
        if case .unknown = type {
            // Deferred TypeExpr form — skip shape validation. (3c.2 sentinel.)
            return true
        }
        switch (value, type) {
        case (.scalar(let scalar), let primitive):
            return scalarMatches(scalar, type: primitive)
        case (.list(let values), .list(let inner)):
            return values.allSatisfy { valueMatches($0, type: inner) }
        case (.list, _), (_, .list):
            return false
        case (.record, .record):
            // Record-against-record is intentionally permissive in the base
            // validator; nested record schema checking lands later.
            return true
        case (.inlineLiteral, .inline):
            return true
        case (.blockLiteral, .blocks):
            return true
        case (.node(let inner), .named(let qname)):
            return inner.type == qname
        case (.node(let inner), .block):
            return inner.kind == .block
        case (.node(let inner), .value):
            return inner.kind == .value
        case (.node(let inner), .template):
            return inner.kind == .template
        case (.node(let inner), .inline):
            return inner.kind == .inline
        case (.reference, .reference):
            return true
        case (.embed, .embed):
            return true
        default:
            return false
        }
    }

    private func scalarMatches(_ scalar: LiminalScalar, type: SchemaTypeExpression) -> Bool {
        // Numeric types (.int, .num, .decimal) accept only numerically-shaped
        // scalars per the parser's literal classification (v0.2 §2.2). Bare
        // scalars represent unparsed text such as `1815-12-10` or `cover.png`
        // — they're appropriate for date/uri/target, not int/num/decimal.
        // Null is handled separately at the field level via isOptional.
        switch (scalar, type) {
        case (.string, .str), (.bare, .str):
            return true
        case (.boolean, .bool):
            return true
        case (.integer, .int):
            return true
        case (.integer, .num), (.number, .num):
            return true
        case (.integer, .decimal), (.number, .decimal):
            return true
        case (.string, .date), (.bare, .date),
             (.string, .time), (.bare, .time),
             (.string, .datetime), (.bare, .datetime):
            return true
        case (.string, .uri), (.bare, .uri):
            return true
        case (.string, .id), (.bare, .id):
            return true
        case (.string, .target), (.bare, .target):
            return true
        case (.string, .type), (.bare, .type):
            return true
        case (.bare(let raw), .enumeration(let cases)),
             (.string(let raw), .enumeration(let cases)):
            return cases.contains(raw)
        default:
            return false
        }
    }

    private func recurse(
        into node: LiminalNode,
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        switch node.content {
        case .inline(let inlines):
            recurse(into: inlines, resolver: resolver, diagnostics: &diagnostics)
        case .blocks(let blocks):
            recurse(into: blocks, resolver: resolver, diagnostics: &diagnostics)
        case nil:
            break
        }

        for field in node.fields {
            recurse(into: field.value, resolver: resolver, diagnostics: &diagnostics)
        }
    }

    private func recurse(
        into inlines: [LiminalInline],
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        for inline in inlines {
            if case .node(let nested) = inline {
                validate(node: nested, resolver: resolver, diagnostics: &diagnostics)
            }
        }
    }

    private func recurse(
        into blocks: [LiminalBlock],
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        for block in blocks {
            if case .node(let nested) = block {
                validate(node: nested, resolver: resolver, diagnostics: &diagnostics)
            }
        }
    }

    private func recurse(
        into value: LiminalValue,
        resolver: LiminalSchemaResolver,
        diagnostics: inout [LiminalDiagnostic]
    ) {
        switch value {
        case .scalar, .reference, .embed:
            break
        case .list(let values):
            for nested in values {
                recurse(into: nested, resolver: resolver, diagnostics: &diagnostics)
            }
        case .record(let fields):
            for field in fields {
                recurse(into: field.value, resolver: resolver, diagnostics: &diagnostics)
            }
        case .node(let nested):
            validate(node: nested, resolver: resolver, diagnostics: &diagnostics)
        case .inlineLiteral(let inlines):
            recurse(into: inlines, resolver: resolver, diagnostics: &diagnostics)
        case .blockLiteral(let blocks):
            recurse(into: blocks, resolver: resolver, diagnostics: &diagnostics)
        }
    }

    private func diagnostic(
        _ severity: LiminalDiagnosticSeverity,
        _ message: String,
        node: LiminalNode
    ) -> LiminalDiagnostic {
        LiminalDiagnostic(
            severity: severity,
            message: message,
            range: node.source?.range ?? .empty
        )
    }
}
