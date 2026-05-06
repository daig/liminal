import Testing
@testable import Liminal

@Suite("Schema Validator")
struct SchemaValidatorTests {
    @Test("clean prelude-shaped document produces no validation diagnostics")
    func cleanDocumentProducesNoValidationDiagnostics() throws {
        let source = "# Heading\n\nParagraph text with [[Target]].\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics == document.diagnostics)
    }

    @Test("unknown typed constructor produces unresolved-type warning")
    func unknownTypedConstructorProducesUnresolvedTypeWarning() throws {
        let source = "@DoesNotExist{x: 1}\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'DoesNotExist'"
        })
    }

    @Test("kind mismatch produces an error")
    func kindMismatchProducesAnError() {
        // Heading is declared as a block in the prelude. Forge a value-kinded
        // node to force the kind-mismatch path.
        let badNode = LiminalNode(
            kind: .value,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.integer("1")))
            ],
            content: .inline([.text("Title")])
        )
        let document = LiminalDocument(items: [.value(badNode)])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let kindMismatch = validated.diagnostics.first { diag in
            diag.severity == .error &&
            diag.message.contains("'Heading'") &&
            diag.message.contains("'block'") &&
            diag.message.contains("'value'")
        }
        #expect(kindMismatch != nil)
    }

    @Test("missing required field produces an error")
    func missingRequiredFieldProducesAnError() {
        let headingMissingLevel = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [],
            content: .inline([.text("Title")])
        )
        let document = LiminalDocument(items: [.block(.node(headingMissingLevel))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "missing required field 'level' on type 'Heading'"
        })
    }

    @Test("missing required content produces an error")
    func missingRequiredContentProducesAnError() {
        let headingMissingContent = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.integer("1")))
            ]
        )
        let document = LiminalDocument(items: [.block(.node(headingMissingContent))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "missing required content 'body' on type 'Heading'"
        })
    }

    @Test("unknown field produces a warning")
    func unknownFieldProducesAWarning() {
        let headingWithExtra = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.integer("1"))),
                LiminalField(name: "unexpected", value: .scalar(.string("extra")))
            ],
            content: .inline([.text("Title")])
        )
        let document = LiminalDocument(items: [.block(.node(headingWithExtra))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unknown field 'unexpected' on type 'Heading'"
        })
    }

    @Test("schema and directive shells are not validated; template signature is also skipped")
    func schemaAndDirectiveShellsAreNotValidated() throws {
        let source = """
        ::use type "./schema.lim" as schema
        :::schema prelude
        body
        :::
        :::template Card(p: P) -> blocks
        Hello
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        // Schema/directive bodies are raw text today; the template's
        // signature/shell is also deferred. The template body ("Hello",
        // a clean paragraph) IS walked but produces no diagnostics, so
        // the overall diagnostic count is unchanged.
        #expect(validated.diagnostics == document.diagnostics)
    }

    @Test("template body items are walked for validation")
    func templateBodyItemsAreWalkedForValidation() throws {
        // The template body contains an unresolved typed inline that
        // should be flagged: walking template.items is what catches
        // typos and malformed nodes inside templates.
        let source = """
        :::template Card(p: P) -> blocks
        Body @DoesNotExist[label]
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'DoesNotExist'"
        })
    }

    @Test("field with wrong scalar shape produces an error")
    func fieldWithWrongScalarShapeProducesAnError() throws {
        // Link.href is declared `.uri`; an integer scalar does not match
        // any text-shaped type. Use an inline @Link constructor inside a
        // paragraph so the kind check passes (Link is .inline).
        let source = "Body @Link{href: 123}[label]\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'href'") &&
            diag.message.contains("'Link'")
        })
    }

    @Test("typed-block Paragraph reports content kind mismatch")
    func typedBlockParagraphReportsContentKindMismatch() throws {
        // :::Paragraph uses the typed-block surface, whose body parses as
        // block content (.blocks). But Paragraph's prelude declaration says
        // body is `inline @content`, so the content kind doesn't match.
        let source = """
        :::Paragraph
        body content
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'body'") &&
            diag.message.contains("'Paragraph'") &&
            diag.message.contains("inline")
        })
    }

    @Test("duplicate fields produce a single duplicate-field error per name")
    func duplicateFieldsProduceADuplicateFieldError() throws {
        // v0.2 §8.2: duplicate fields are syntactically valid; the schema
        // pass reports them as an error rather than crashing.
        let source = "Body @Link{href: \"a\", href: \"b\"}[label]\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        let dupes = added.filter { diag in
            diag.severity == .error &&
            diag.message == "duplicate field 'href' on type 'Link'"
        }
        // Exactly one duplicate-field diagnostic per duplicated name (not
        // one per offending occurrence).
        #expect(dupes.count == 1)
    }

    @Test("null on a required field produces a wrong-shape error")
    func nullOnRequiredFieldProducesAWrongShapeError() {
        // Heading.level is required (.int); the explicit null literal must
        // not satisfy a required typed field.
        let badNode = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.null))
            ],
            content: .inline([.text("Title")])
        )
        let document = LiminalDocument(items: [.block(.node(badNode))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'level'") &&
            diag.message.contains("'Heading'")
        })
    }

    @Test("null on an optional field is accepted without error")
    func nullOnOptionalFieldIsAccepted() {
        // CodeBlock.language is optional; null is an acceptable explicit
        // absence marker.
        let codeBlock = LiminalNode(
            kind: .block,
            type: "CodeBlock",
            fields: [
                LiminalField(name: "language", value: .scalar(.null)),
                LiminalField(name: "text", value: .scalar(.string("print()\n")))
            ]
        )
        let document = LiminalDocument(items: [.block(.node(codeBlock))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.isEmpty)
    }

    @Test("bare scalar in a numeric field produces a wrong-shape error")
    func bareScalarInNumericFieldProducesWrongShapeError() {
        // Heading.level is .int. A bare scalar like `one` is unparsed text
        // and must not satisfy a numeric type.
        let badNode = LiminalNode(
            kind: .block,
            type: "Heading",
            fields: [
                LiminalField(name: "level", value: .scalar(.bare("one")))
            ],
            content: .inline([.text("Title")])
        )
        let document = LiminalDocument(items: [.block(.node(badNode))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'level'") &&
            diag.message.contains("'Heading'")
        })
    }

    @Test("explicit field for a @content slot produces an error")
    func explicitFieldForContentSlotProducesAnError() throws {
        // WikiLink.body is declared as `inline @content`; supplying it as
        // an explicit record field instead of via the body literal must
        // be flagged.
        let source = "Body @WikiLink{target: \"T\", body: 123}\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'body'") &&
            diag.message.contains("'WikiLink'") &&
            diag.message.contains("@content")
        })
    }

    @Test("enum field value outside declared cases produces an error")
    func enumFieldValueOutsideDeclaredCasesProducesAnError() {
        // List.marker is declared as enum {dash, asterisk, plus, decimal_dot}.
        let badList = LiminalNode(
            kind: .block,
            type: "List",
            fields: [
                LiminalField(name: "ordered", value: .scalar(.boolean(false))),
                LiminalField(name: "marker", value: .scalar(.bare("circle"))),
                LiminalField(name: "items", value: .list([]))
            ]
        )
        let document = LiminalDocument(items: [.block(.node(badList))])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'marker'") &&
            diag.message.contains("'List'")
        })
    }

    @Test("recursive validation finds issues in nested content")
    func recursiveValidationFindsIssuesInNestedContent() throws {
        // A typed inline whose name is not in the prelude lives inside a
        // paragraph; the validator should descend into Paragraph.content
        // and flag the nested unresolved type.
        let source = "Body @DoesNotExist[label]\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'DoesNotExist'"
        })
    }

    @Test("validation diagnostics carry the offending node's source range")
    func validationDiagnosticsCarrySourceRange() throws {
        let source = "@DoesNotExist{x: 1}\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let unresolved = try #require(validated.diagnostics.first { diag in
            diag.message == "unresolved type 'DoesNotExist'"
        })
        // Range should be non-empty and equal to the lowered node's source range.
        #expect(unresolved.range != .empty)
    }
}
