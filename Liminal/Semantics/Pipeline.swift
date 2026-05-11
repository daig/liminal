import CambiumCore
import Foundation

public struct LiminalLowerer: Sendable {
    public init() {}

    public func lower(_ parseResult: LiminalParseResult) -> LiminalDocument {
        let items = parseResult.rootSyntax.documentItems.compactMap(lowerDocumentItem)
        return LiminalDocument(
            syntaxTree: parseResult.tree,
            items: items,
            diagnostics: parseResult.diagnostics
        )
    }

    private func lowerDocumentItem(_ item: DocumentItemSyntax) -> LiminalDocumentItem? {
        switch item {
        case .blankLine:
            nil
        case .frontmatter(let frontmatter):
            .value(LiminalNode(
                kind: .value,
                type: "Frontmatter",
                fields: [
                    field("format", .scalar(.bare("yaml"))),
                    field("raw", .scalar(.string(frontmatter.rawYamlText)))
                ],
                source: surface("frontmatter", frontmatter.syntax)
            ))
        case .directive(let directive):
            .directive(lowerDirective(directive))
        case .schemaBlock(let schema):
            .schema(lowerSchemaBlock(schema))
        case .templateBlock(let template):
            .template(LiminalTemplateBlock(
                signature: template.signatureText,
                parsedSignature: template.signature.flatMap(lowerTemplateSignature),
                rawBodyText: template.rawBodyText,
                items: template.documentItems.compactMap(lowerDocumentItem),
                source: surface("templateBlock", template.syntax)
            ))
        case .paragraph(let paragraph):
            lowerParagraph(paragraph).map { .block(.node($0)) }
        case .atxHeading(let heading):
            lowerHeading(heading).map { .block(.node($0)) }
        case .valueDeclaration(let declaration):
            // Syntactic classification only. Phase 3 schema resolution can
            // reclassify generic constructors once their type kind is known.
            declaration.constructor.map { .value(lowerTypedConstructor($0, kind: .value)) }
        case .typedBlock(let block):
            // Syntactic classification only; schema validation owns final type
            // resolution and context checks.
            .block(.node(lowerTypedBlock(block)))
        case .fencedCodeBlock(let block):
            .block(.node(lowerFencedCodeBlock(block)))
        case .mathBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "MathBlock",
                fields: [
                    field("tex", .scalar(.string(block.texText)))
                ],
                source: surface("mathBlock", block.syntax)
            )))
        case .htmlBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "HtmlBlock",
                fields: [
                    field("raw", .scalar(.string(block.rawText)))
                ],
                source: surface("htmlBlock", block.syntax)
            )))
        case .commentBlock(let block):
            .block(.node(LiminalNode(
                kind: .block,
                type: "CommentBlock",
                fields: [
                    field("raw", .scalar(.string(block.rawText)))
                ],
                source: surface("commentBlock", block.syntax)
            )))
        case .list(let list):
            .block(.node(lowerList(list)))
        case .blockQuote(let quote):
            .block(.node(lowerBlockQuote(quote)))
        case .pipeTable(let table):
            .block(.node(lowerPipeTable(table)))
        case .structuredEmbedBlock(let embed):
            .block(.node(lowerStructuredEmbedBlock(embed)))
        case .wikiEmbedBlock(let embed):
            .block(.node(lowerWikiEmbedBlock(embed)))
        }
    }

    private func lowerDirective(_ directive: DirectiveSyntax) -> LiminalDirective {
        let useDirective = directive.useDirective
        let useKind = useDirective?.kindText.flatMap(LiminalUseKind.init(rawValue:))
        let targetText = useDirective?.targetText ?? ""
        let targetIsQuoted = useDirective?.targetIsQuoted ?? false
        let filterQNames: [QualifiedName]?
        if let useDirective, useDirective.hasFilter {
            filterQNames = useDirective.filterQNames.map { QualifiedName($0) }
        } else {
            filterQNames = nil
        }
        let alias = useDirective?.aliasText
        return LiminalDirective(
            name: directive.keywordText,
            rawText: directive.bodyText,
            useKind: useKind,
            targetText: targetText,
            targetIsQuoted: targetIsQuoted,
            filterQNames: filterQNames,
            alias: alias,
            source: surface("directive", directive.syntax)
        )
    }

    private func lowerSchemaBlock(_ schema: SchemaBlockSyntax) -> LiminalSchemaBlock {
        var declarations: [LiminalUserSchemaTypeDeclaration] = []
        for decl in schema.declarations {
            declarations.append(LiminalUserSchemaTypeDeclaration(
                name: QualifiedName(decl.qnameText),
                kind: NodeKind(rawValue: decl.nodeKindText),
                rawRHS: decl.rhsText,
                definition: decl.definition.flatMap(lowerSchemaTypeExpression),
                modifiers: decl.modifiers.compactMap(lowerSchemaModifier)
            ))
        }
        for decl in schema.templateDeclarations {
            declarations.append(LiminalUserSchemaTypeDeclaration(
                name: QualifiedName(decl.qnameText),
                kind: .template,
                rawRHS: decl.signatureText,
                templateSignature: decl.signature.flatMap(lowerTemplateSignature)
            ))
        }
        return LiminalSchemaBlock(
            name: schema.nameText,
            rawText: schema.rawText,
            declarations: declarations,
            source: surface("schemaBlock", schema.syntax)
        )
    }

    private func lowerSchemaTypeExpression(
        _ syntax: SchemaTypeExpressionSyntax
    ) -> SchemaTypeExpression? {
        guard let raw = lowerRawSchemaTypeExpression(syntax) else {
            return nil
        }
        // 3.6: surface trailing `?` as a structural `.optional` wrapper
        // so nested positions (`[str?]`, `map<int?>`) preserve the
        // marker. At the field-value boundary the outer wrapper is
        // hoisted into `SchemaField.isOptional` by `lowerSchemaField`,
        // keeping the existing field-level optional semantics intact.
        return syntax.isOptional ? .optional(raw) : raw
    }

    private func lowerRawSchemaTypeExpression(
        _ syntax: SchemaTypeExpressionSyntax
    ) -> SchemaTypeExpression? {
        if syntax.isEnum {
            // Phase 3.6: structured `enum { Ident, ... }` — surface the
            // declared case names so the validator can enforce
            // membership against bare-scalar / string values.
            return .enumeration(syntax.enumCaseNames)
        }
        if syntax.isVariant {
            // Phase 3.6: structured `variant by F { case: { … }, ... }`.
            // The discriminator field name and the variant cases (each
            // with its own record payload) are lifted into the lowered
            // shape; validator-side dispatch on the discriminator
            // remains a future concern.
            let discriminator = FieldName(syntax.variantDiscriminatorText ?? "")
            let cases = syntax.variantCases.map { caseSyntax -> SchemaVariantCase in
                let payloadFields = caseSyntax.payloadType?.recordFields.map(lowerSchemaField) ?? []
                return SchemaVariantCase(name: caseSyntax.nameText, fields: payloadFields)
            }
            return .variant(discriminator: discriminator, cases: cases)
        }
        if let keyword = syntax.angleTypeKeyword {
            // Phase 3.6: `map<T>` / `ref<T>` / `embed<T>` — recurse
            // through the inner type expression.
            let elementSyntax = syntax.angleElementType
            let element = elementSyntax.flatMap(lowerSchemaTypeExpression) ?? .deferred
            switch keyword {
            case "map":
                return .map(element)
            case "ref":
                return .reference(element)
            case "embed":
                return .embed(element)
            default:
                return nil
            }
        }
        if syntax.isList {
            // List type — recurse into the element type.
            guard let elementSyntax = syntax.listElementType else {
                return nil
            }
            let element = lowerSchemaTypeExpression(elementSyntax) ?? .deferred
            return .list(element)
        }
        if syntax.isRecord {
            let fields = syntax.recordFields.map(lowerSchemaField)
            return .record(fields)
        }
        if let qname = syntax.qnameText {
            return primitiveType(named: qname) ?? .named(QualifiedName(qname))
        }
        return nil
    }

    private func lowerSchemaField(_ syntax: SchemaFieldSyntax) -> SchemaField {
        // The field is optional iff the field name carries `?` OR the
        // value type itself is optional (`field: T?`). Validation treats
        // both forms uniformly per spec §9.
        let valueTypeSyntax = syntax.valueType
        // Fields whose value type the parser couldn't structure (only
        // reachable for malformed RHS after Phase 3.6) lower to
        // `.deferred` so the validator skips type-shape checks for
        // them while still honouring presence and optionality. The
        // parser already surfaced the underlying diagnostic; this
        // just keeps validation from piling on.
        var valueType = valueTypeSyntax.flatMap(lowerSchemaTypeExpression) ?? .deferred
        let typeLevelOptional = valueTypeSyntax?.isOptional ?? false
        // 3.6: lowerSchemaTypeExpression wraps the result in `.optional`
        // when the type expression ends in `?`. At the field-value
        // boundary we hoist that one level into `isOptional` so the
        // existing field-level semantics still apply — nested optional
        // wrappers (`[str?]`) stay in place because their `?` was
        // consumed by inner wrappers, not the outer field-value one.
        if case .optional(let inner) = valueType {
            valueType = inner
        }
        let modifiers = syntax.modifiers.compactMap(lowerSchemaModifier)
        return SchemaField(
            name: FieldName(syntax.fieldNameText),
            type: valueType,
            isOptional: syntax.isOptional || typeLevelOptional,
            modifiers: modifiers
        )
    }

    private func lowerSchemaModifier(_ syntax: SchemaModifierSyntax) -> SchemaModifier? {
        // Phase 3.6 (G4): decode the arg-carrying modifiers
        // (`@default`, `@surface`, `@deprecated`) into their respective
        // `SchemaModifier` cases. `@default` accepts the simple scalar
        // value grammar (literal / quoted-string / bare / boolean /
        // null); record / list / typed-constructor defaults remain
        // undecoded (return nil so the modifier doesn't surface in a
        // half-broken state).
        switch syntax.modifierName {
        case "content":
            return .content
        case "readonly":
            return .readonly
        case "default":
            guard let raw = syntax.argumentsText,
                  let value = decodeSchemaModifierScalar(raw)
            else {
                return nil
            }
            return .defaultValue(value)
        case "surface":
            guard let raw = syntax.argumentsText else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .surface(trimmed)
        case "deprecated":
            guard let raw = syntax.argumentsText else { return nil }
            return .deprecated(decodeSchemaModifierString(raw))
        default:
            return nil
        }
    }

    /// Phase 3.6 (G4): decode the scalar value form of a `@default(...)`
    /// argument. Recognises quoted strings, booleans, null, ASCII
    /// integers and decimals, falling back to a bare scalar. Returns
    /// nil for inputs that don't fit any of those — record / list /
    /// typed-constructor defaults stay undecoded for now.
    private func decodeSchemaModifierScalar(_ raw: String) -> LiminalValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            let inner = String(trimmed.dropFirst().dropLast())
            return .scalar(.string(inner))
        }
        if trimmed == "true" { return .scalar(.boolean(true)) }
        if trimmed == "false" { return .scalar(.boolean(false)) }
        if trimmed == "null" { return .scalar(.null) }

        // Numbers — integer if no decimal/exponent, number otherwise.
        if !trimmed.isEmpty,
           trimmed.allSatisfy({ isAsciiDigit($0) || $0 == "-" })
        {
            return .scalar(.integer(trimmed))
        }
        if Double(trimmed) != nil,
           trimmed.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
        {
            return .scalar(.number(trimmed))
        }

        // Record / list / typed constructor — deferred. Returning nil
        // surfaces as "no decoded modifier" so the validator doesn't
        // act on partial info.
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("@") {
            return nil
        }
        return .scalar(.bare(trimmed))
    }

    /// Phase 3.6 (G4): decode a quoted-string modifier argument like
    /// `@deprecated("old")` or `@surface("Bar")`. Strips surrounding
    /// quotes when present, falls back to trimmed text otherwise.
    private func decodeSchemaModifierString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private func isAsciiDigit(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return value >= 48 && value <= 57
    }

    private func lowerTemplateSignature(
        _ syntax: TemplateSignatureSyntax
    ) -> LiminalTemplateSignature? {
        // The signature must at least have a name to be useful; recovery
        // paths emit `.missing` for the name and we treat those as nil so
        // consumers can detect them.
        guard let name = syntax.qnameText else { return nil }
        let parameters = syntax.parameters.map { paramSyntax in
            let typeSyntax = paramSyntax.valueType
            var type = typeSyntax.flatMap(lowerSchemaTypeExpression) ?? .deferred
            // 3.6: peel the outer `.optional` wrapper at the param
            // boundary so the existing `isOptional` flag carries the
            // signal (mirrors `lowerSchemaField`).
            if case .optional(let inner) = type {
                type = inner
            }
            return LiminalTemplateParameter(
                name: paramSyntax.nameText,
                type: type,
                isOptional: typeSyntax?.isOptional ?? false
            )
        }
        let result = syntax.resultText.flatMap(LiminalTemplateResult.init(rawValue:))
        return LiminalTemplateSignature(
            name: QualifiedName(name),
            parameters: parameters,
            result: result
        )
    }

    private func primitiveType(named text: String) -> SchemaTypeExpression? {
        switch text {
        case "str": return .str
        case "bool": return .bool
        case "int": return .int
        case "num": return .num
        case "decimal": return .decimal
        case "date": return .date
        case "time": return .time
        case "datetime": return .datetime
        case "uri": return .uri
        case "id": return .id
        case "target": return .target
        case "type": return .type
        case "inline": return .inline
        case "block": return .block
        case "blocks": return .blocks
        case "value": return .value
        case "template": return .template
        default:
            return nil
        }
    }

    private func lowerParagraph(_ paragraph: ParagraphSyntax) -> LiminalNode? {
        let inlines = lowerInlineContent(paragraph.inlineContent)
        guard !inlines.isEmpty || paragraph.blockIdToken != nil else {
            return nil
        }

        return LiminalNode(
            kind: .block,
            type: "Paragraph",
            id: paragraph.blockIdToken.map { Anchor($0.text) },
            content: .inline(inlines),
            source: surface("paragraph", paragraph.syntax)
        )
    }

    private func lowerHeading(_ heading: AtxHeadingSyntax) -> LiminalNode? {
        guard (1...6).contains(heading.level) else {
            return nil
        }

        return LiminalNode(
            kind: .block,
            type: "Heading",
            id: heading.blockIdToken.map { Anchor($0.text) },
            fields: [
                field("level", .scalar(.integer(String(heading.level))))
            ],
            content: .inline(lowerInlineContent(heading.inlineContent)),
            source: surface("atxHeading", heading.syntax)
        )
    }

    private func lowerWikiEmbedBlock(_ embed: WikiEmbedBlockSyntax) -> LiminalNode {
        var fields = [
            field("target", .scalar(.string(embed.targetText)))
        ]
        if let payload = embed.payloadText {
            fields.append(field("payload", .scalar(.string(payload))))
        }

        return LiminalNode(
            kind: .block,
            type: "WikiEmbedBlock",
            fields: fields,
            source: surface("wikiEmbedBlock", embed.syntax)
        )
    }

    private func lowerFencedCodeBlock(_ block: FencedCodeBlockSyntax) -> LiminalNode {
        var fields: [LiminalField] = []
        if let language = block.languageText {
            fields.append(field("language", .scalar(.bare(language))))
        }
        // Per spec §6.6 the `info` field carries the raw info string;
        // only `language` is trimmed. Gate emission on the normalized
        // form so a whitespace-only info string doesn't produce a field.
        if !block.normalizedInfoText.isEmpty {
            fields.append(field("info", .scalar(.string(block.infoText))))
        }
        fields.append(field("text", .scalar(.string(block.codeText))))

        return LiminalNode(
            kind: .block,
            type: "CodeBlock",
            fields: fields,
            source: surface("fencedCodeBlock", block.syntax)
        )
    }

    private func lowerList(_ list: ListSyntax) -> LiminalNode {
        var fields = [
            field("ordered", .scalar(.boolean(list.isOrdered))),
            field("marker", .scalar(.bare(listMarkerName(for: list)))),
            field("items", .list(list.items.map { .node(lowerListItem($0)) }))
        ]
        if let startNumber = list.startNumber {
            fields.insert(
                field("start", .scalar(.integer(String(startNumber)))),
                at: 2
            )
        }

        return LiminalNode(
            kind: .block,
            type: "List",
            fields: fields,
            source: surface("list", list.syntax)
        )
    }

    private func lowerListItem(_ item: ListItemSyntax) -> LiminalNode {
        var fields: [LiminalField] = []
        if let taskState = item.taskState {
            fields.append(field("task", .scalar(.bare(taskState == .checked ? "checked" : "unchecked"))))
        }

        return LiminalNode(
            kind: .value,
            type: "ListItem",
            id: item.blockIdToken.map { Anchor($0.text) },
            fields: fields,
            content: .blocks(lowerDocumentItemsToBlocks(item.documentItems)),
            source: surface("listItem", item.syntax)
        )
    }

    private func lowerBlockQuote(_ quote: BlockQuoteSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: "BlockQuote",
            content: .blocks(lowerDocumentItemsToBlocks(quote.documentItems)),
            source: surface("blockQuote", quote.syntax)
        )
    }

    private func lowerPipeTable(_ table: PipeTableSyntax) -> LiminalNode {
        let alignments = table.alignments
        let columns = table.headerCells.enumerated().map { index, cell in
            var fields = [
                field("label", .inlineLiteral(lowerInlineContent(cell.inlineContent)))
            ]
            if index < alignments.count, let alignment = alignments[index] {
                fields.append(field("align", .scalar(.bare(alignment.rawValue))))
            }
            return LiminalValue.node(LiminalNode(
                kind: .value,
                type: "Column",
                fields: fields,
                source: surface("pipeTableCell", cell.syntax)
            ))
        }

        let rows = table.rows.map { row in
            LiminalValue.node(LiminalNode(
                kind: .value,
                type: "Row",
                fields: [
                    field("cells", .list(row.cells.map { cell in
                        .inlineLiteral(lowerInlineContent(cell.inlineContent))
                    }))
                ],
                source: surface("pipeTableRow", row.syntax)
            ))
        }

        return LiminalNode(
            kind: .block,
            type: "Table",
            fields: [
                field("columns", .list(columns)),
                field("rows", .list(rows))
            ],
            source: surface("pipeTable", table.syntax)
        )
    }

    private func listMarkerName(for list: ListSyntax) -> String {
        if list.isOrdered {
            return "decimal_dot"
        }

        switch list.markerText {
        case "-":
            return "dash"
        case "*":
            return "asterisk"
        case "+":
            return "plus"
        default:
            return "unknown"
        }
    }

    private func lowerInlineContent(_ content: InlineContentSyntax?) -> [LiminalInline] {
        guard let content else {
            return []
        }

        return content.syntax.withCursor { node in
            var result: [LiminalInline] = []
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where token.kind == .inlineText:
                    result.append(.text(token.makeString()))
                case .node(let child) where child.kind == .softBreak:
                    result.append(.node(LiminalNode(
                        kind: .inline,
                        type: "SoftBreak",
                        source: surface("softBreak", child.makeHandle())
                    )))
                case .node(let child) where child.kind == .hardBreak:
                    result.append(.node(LiminalNode(
                        kind: .inline,
                        type: "HardBreak",
                        source: surface("hardBreak", child.makeHandle())
                    )))
                case .node(let child):
                    if let inline = lowerInlineNode(child.makeHandle()) {
                        result.append(inline)
                    }
                default:
                    break
                }
            }
            return result
        }
    }

    private func lowerInlineNode(_ syntax: SyntaxNodeHandle<LiminalLanguage>) -> LiminalInline? {
        switch InlineSyntax(syntax) {
        case .codeSpan(let codeSpan):
            .node(LiminalNode(
                kind: .inline,
                type: "CodeSpan",
                fields: [
                    field("text", .scalar(.string(codeSpan.codeText)))
                ],
                source: surface("codeSpan", codeSpan.syntax)
            ))
        case .escapedPunctuation(let punctuation):
            .text(punctuation.escapedText)
        case .strikethrough(let strikethrough):
            strikethrough.isIncomplete
                ? .text(strikethrough.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "Strikethrough",
                    content: .inline(lowerInlineContent(strikethrough.inlineContent)),
                    source: surface("strikethrough", strikethrough.syntax)
                ))
        case .highlight(let highlight):
            highlight.isIncomplete
                ? .text(highlight.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "Highlight",
                    content: .inline(lowerInlineContent(highlight.inlineContent)),
                    source: surface("highlight", highlight.syntax)
                ))
        case .mdLink(let link):
            lowerMarkdownLink(link)
        case .mdImage(let image):
            lowerMarkdownImage(image)
        case .wikilink(let wikilink):
            lowerWikilink(wikilink)
        case .wikiEmbed(let embed):
            lowerWikiEmbed(embed)
        case .typedInline(let typedInline):
            typedInline.constructor.map { constructor in
                .node(lowerTypedConstructor(constructor, kind: .inline))
            }
        case .structuredEmbed(let embed):
            lowerStructuredEmbedInline(embed)
        case .mathInline(let math):
            .node(LiminalNode(
                kind: .inline,
                type: "MathInline",
                fields: [
                    field("tex", .scalar(.string(math.texText)))
                ],
                source: surface("mathInline", math.syntax)
            ))
        case .interpolation(let interpolation):
            .interpolation(LiminalTemplateExpression(interpolation.expressionText))
        case .inlineComment(let comment):
            .node(LiminalNode(
                kind: .inline,
                type: "CommentInline",
                fields: [
                    field("raw", .scalar(.string(comment.rawText)))
                ],
                source: surface("inlineComment", comment.syntax)
            ))
        case .footnoteInline(let footnote):
            footnote.isIncomplete
                ? .text(footnote.sourceText)
                : .node(LiminalNode(
                    kind: .inline,
                    type: "FootnoteInline",
                    content: .inline(lowerInlineContent(footnote.inlineContent)),
                    source: surface("footnoteInline", footnote.syntax)
                ))
        case nil:
            nil
        }
    }

    private func lowerMarkdownLink(_ link: MdLinkSyntax) -> LiminalInline {
        var fields = [
            field("href", .scalar(.bare(link.destinationText)))
        ]
        if let title = link.titleText {
            fields.append(field("title", .scalar(.string(title))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "Link",
            fields: fields,
            content: .inline(lowerInlineContent(link.labelContent)),
            source: surface("mdLink", link.syntax)
        ))
    }

    private func lowerMarkdownImage(_ image: MdImageSyntax) -> LiminalInline {
        var fields = [
            field("src", .scalar(.bare(image.destinationText))),
            field("alt", .inlineLiteral(lowerInlineContent(image.altContent)))
        ]
        if let title = image.titleText {
            fields.append(field("title", .scalar(.string(title))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "Image",
            fields: fields,
            source: surface("mdImage", image.syntax)
        ))
    }

    private func lowerWikilink(_ wikilink: WikilinkSyntax) -> LiminalInline {
        let alias = wikilink.aliasContent.map(lowerInlineContent)
        return .node(LiminalNode(
            kind: .inline,
            type: "WikiLink",
            fields: [
                field("target", .scalar(.string(wikilink.targetText)))
            ],
            content: alias.map(LiminalContent.inline),
            source: surface("wikilink", wikilink.syntax)
        ))
    }

    private func lowerWikiEmbed(_ embed: WikiEmbedSyntax) -> LiminalInline {
        var fields = [
            field("target", .scalar(.string(embed.targetText)))
        ]
        if let payload = embed.payloadText {
            fields.append(field("payload", .scalar(.string(payload))))
        }

        return .node(LiminalNode(
            kind: .inline,
            type: "WikiEmbedInline",
            fields: fields,
            source: surface("wikiEmbed", embed.syntax)
        ))
    }

    private func lowerTypedBlock(_ block: TypedBlockSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: QualifiedName(block.typeName),
            id: block.idText.map { Anchor($0) },
            fields: lowerFields(block.fields),
            content: .blocks(lowerDocumentItemsToBlocks(block.documentItems)),
            source: surface("typedBlock", block.syntax)
        )
    }

    private func lowerTypedConstructor(
        _ constructor: TypedConstructorSyntax,
        kind: NodeKind
    ) -> LiminalNode {
        LiminalNode(
            kind: kind,
            type: QualifiedName(constructor.typeName),
            id: constructor.idText.map { Anchor($0) },
            fields: lowerFields(constructor.fields),
            content: constructor.inlineContent.map { .inline(lowerInlineContent($0)) },
            source: surface("typedConstructor", constructor.syntax)
        )
    }

    private func lowerStructuredEmbedBlock(_ embed: StructuredEmbedBlockSyntax) -> LiminalNode {
        LiminalNode(
            kind: .block,
            type: "EmbedBlock",
            fields: structuredEmbedFields(
                expectedType: embed.expectedType,
                fallbackContent: embed.fallbackContent,
                targetText: embed.targetText
            ),
            source: surface("structuredEmbedBlock", embed.syntax)
        )
    }

    private func lowerStructuredEmbedInline(_ embed: StructuredEmbedSyntax) -> LiminalInline {
        .node(LiminalNode(
            kind: .inline,
            type: "EmbedInline",
            fields: structuredEmbedFields(
                expectedType: embed.expectedType,
                fallbackContent: embed.fallbackContent,
                targetText: embed.targetText
            ),
            source: surface("structuredEmbed", embed.syntax)
        ))
    }

    private func lowerStructuredEmbedValue(_ embed: StructuredEmbedValueSyntax) -> LiminalValue {
        .embed(LiminalEmbed(
            expectedType: embed.expectedType.map { QualifiedName($0) },
            fallback: lowerInlineContent(embed.fallbackContent),
            target: embed.targetText
        ))
    }

    private func structuredEmbedFields(
        expectedType: String?,
        fallbackContent: InlineContentSyntax?,
        targetText: String
    ) -> [LiminalField] {
        var result: [LiminalField] = []
        if let expectedType {
            result.append(field("expected", .scalar(.bare(expectedType))))
        }
        if let fallbackContent {
            result.append(field("fallback", .inlineLiteral(lowerInlineContent(fallbackContent))))
        }
        result.append(field("target", .scalar(.string(targetText))))
        return result
    }

    private func lowerFields(_ fields: FieldsSyntax?) -> [LiminalField] {
        fields?.fields.map { fieldSyntax in
            field(
                FieldName(fieldSyntax.name),
                fieldSyntax.value.map(lowerValue) ?? .scalar(.null)
            )
        } ?? []
    }

    private func lowerValue(_ value: ValueNodeSyntax) -> LiminalValue {
        guard let payload = value.payload else {
            return .scalar(.null)
        }

        switch payload {
        case .scalar(let scalar):
            return lowerScalarValue(scalar)
        case .list(let list):
            return .list(list.values.map(lowerValue))
        case .record(let record):
            return .record(lowerFields(record.fields))
        case .typedConstructor(let constructor):
            return .node(lowerTypedConstructor(constructor, kind: .value))
        case .inlineLiteral(let literal):
            return .inlineLiteral(lowerInlineContent(literal.inlineContent))
        case .blockLiteral(let literal):
            return .blockLiteral(lowerDocumentItemsToBlocks(literal.documentItems))
        case .reference(let reference):
            return .reference(lowerReference(reference))
        case .structuredEmbedValue(let embed):
            return lowerStructuredEmbedValue(embed)
        }
    }

    private func lowerScalarValue(_ scalar: ScalarValueSyntax) -> LiminalValue {
        guard let token = scalar.token else {
            return .scalar(.null)
        }

        switch token.kind {
        case .quotedStringLiteral:
            return .scalar(.string(decodeQuotedString(token.text)))
        case .integerLiteral:
            return .scalar(.integer(token.text))
        case .numberLiteral:
            return .scalar(.number(token.text))
        case .booleanLiteral:
            return .scalar(.boolean(token.text == "true"))
        case .nullLiteral:
            return .scalar(.null)
        default:
            return .scalar(.bare(token.text))
        }
    }

    private func lowerReference(_ reference: ReferenceSyntax) -> LiminalReference {
        if let externalTargetText = reference.externalTargetText {
            return .external(externalTargetText)
        }

        let qname = QualifiedName(reference.qnameText ?? "")
        guard qname.parts.count > 1 else {
            return .local(Anchor(qname.rawValue))
        }

        let namespace = QualifiedName(parts: Array(qname.parts.dropLast()))
        return .qualified(namespace: namespace, id: Anchor(qname.parts.last ?? ""))
    }

    private func lowerDocumentItemsToBlocks(_ items: [DocumentItemSyntax]) -> [LiminalBlock] {
        items.compactMap { item in
            switch lowerDocumentItem(item) {
            case .block(let block)?:
                block
            case .value?, .schema?, .template?, .directive?, nil:
                nil
            }
        }
    }

    private func decodeQuotedString(_ text: String) -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else {
            return text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        var result = ""
        var cursor = text.index(after: text.startIndex)
        let end = text.index(before: text.endIndex)
        while cursor < end {
            let character = text[cursor]
            if character == "\\", text.index(after: cursor) < end {
                cursor = text.index(after: cursor)
                switch text[cursor] {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    result.append(text[cursor])
                }
            } else {
                result.append(character)
            }
            cursor = text.index(after: cursor)
        }
        return result
    }

    private func field(_ name: FieldName, _ value: LiminalValue) -> LiminalField {
        LiminalField(name: name, value: value)
    }

    private func surface(
        _ name: String,
        _ syntax: SyntaxNodeHandle<LiminalLanguage>
    ) -> SurfaceForm {
        SurfaceForm(
            name: name,
            range: syntax.textRange
        )
    }
}

public enum PrintMode: Sendable {
    case lossless
    case canonical
}

public struct LiminalPrinter: Sendable {
    public init() {}

    public func print(_ document: LiminalDocument, mode: PrintMode = .lossless) -> String {
        switch mode {
        case .lossless:
            document.sourceText ?? ""
        case .canonical:
            document.sourceText ?? ""
        }
    }
}

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
