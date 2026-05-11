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

    @Test("explicit @content field with the right shape is accepted")
    func explicitContentFieldWithRightShapeIsAccepted() throws {
        // The generic typed/value form of v0.2 supplies @content fields
        // explicitly: `@ListItem{body: @{First}}`, `@BlockQuote{body: @{...}}`.
        // The validator must accept these as a legitimate alternative to
        // the surface body form.
        let listItem = LiminalNode(
            kind: .value,
            type: "ListItem",
            fields: [
                LiminalField(
                    name: "body",
                    value: .blockLiteral([
                        .node(LiminalNode(
                            kind: .block,
                            type: "Paragraph",
                            content: .inline([.text("First")])
                        ))
                    ])
                )
            ]
        )
        let document = LiminalDocument(items: [.value(listItem)])
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.isEmpty)
    }

    @Test("supplying @content both as explicit field and as surface body produces an error")
    func explicitAndSurfaceContentBothSuppliedProducesAnError() throws {
        // The Link constructor below carries both an explicit `body` field
        // and an inline `[surface]` body. Per spec §8.1 the surface body
        // already maps to the @content field; doubling them is ambiguous.
        let source = "Body @Link{href: \"T\", body: @[field]}[surface]\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'Link'") &&
            diag.message.contains("'body'") &&
            (diag.message.contains("both") || diag.message.contains("pick one"))
        })
    }

    @Test("explicit @content field with the wrong shape produces an error")
    func explicitContentFieldWithWrongShapeProducesAnError() throws {
        // WikiLink.body is `inline @content`. An explicit numeric value
        // cannot match `.inline`.
        let source = "Body @WikiLink{target: \"T\", body: 123}\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'body'") &&
            diag.message.contains("'WikiLink'")
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

    @Test("Phase 3b.3 user-declared type validates without unresolved warning")
    func phase3b3UserDeclaredTypeValidatesWithoutWarning() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str }
        :::
        @Person{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(!validated.diagnostics.contains { diag in
            diag.message.contains("unresolved type 'Person'")
        })
    }

    @Test("Phase 3b.3 user-declared type kind mismatch is still flagged")
    func phase3b3UserDeclaredTypeKindMismatchStillFlagged() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str }
        :::
        :::Person
        body
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("'Person'") &&
            diag.message.contains("'value'") &&
            diag.message.contains("'block'")
        })
    }

    @Test("Phase 3b.3 imported alias namespace skips unresolved warning")
    func phase3b3ImportedAliasNamespaceSkipsUnresolvedWarning() throws {
        let source = """
        ::use type "./schema.lim" as ext
        @ext.Person{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(!validated.diagnostics.contains { diag in
            diag.message.contains("unresolved type 'ext.Person'")
        })
    }

    @Test("Phase 3b.3 unaliased external reference still warns")
    func phase3b3UnaliasedExternalReferenceStillWarns() throws {
        let source = "@unknown.Whatever{}\n"
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'unknown.Whatever'"
        })
    }

    @Test("Phase 3b.3 user declaration colliding with prelude is diagnosed")
    func phase3b3UserDeclarationCollisionWithPreludeIsDiagnosed() throws {
        let source = """
        :::schema prelude
        type Document : document = { foo: str }
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message.contains("shadows prelude type") &&
            diag.message.contains("'Document'")
        })
    }

    @Test("Phase 3b.3 ::use data alias does not suppress unresolved-type warning")
    func phase3b3DataImportAliasDoesNotSuppressTypeWarning() throws {
        let source = """
        ::use data "./people.lim" as people
        @people.Person{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'people.Person'"
        })
    }

    @Test("Phase 3b.3 import filter restricts which qnames the alias resolves")
    func phase3b3ImportFilterRestrictsAliasResolution() throws {
        let source = """
        ::use type "./schema.lim" only { Person } as ext
        @ext.Person{name: "Ada"}
        @ext.Card{title: "Hi"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(!validated.diagnostics.contains { diag in
            diag.message.contains("unresolved type 'ext.Person'")
        })
        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'ext.Card'"
        })
    }

    @Test("Phase 3b.3 explicit empty filter excludes everything from the alias")
    func phase3b3EmptyFilterExcludesEverything() throws {
        let source = """
        ::use type "./schema.lim" only { } as ext
        @ext.Person{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'ext.Person'"
        })
    }

    @Test("Phase 3b.3 bare alias qname (no segment past alias) is unresolved")
    func phase3b3BareAliasQnameIsUnresolved() throws {
        let source = """
        ::use type "./schema.lim" as ext
        @ext{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unresolved type 'ext'"
        })
    }

    @Test("Phase 3b.3 separate reported sets emit shadow + duplicate per qname")
    func phase3b3ShadowAndDuplicateEmitSeparateWarnings() throws {
        let source = """
        :::schema a
        type Document : document = { foo: str }
        :::
        :::schema b
        type Document : document = { bar: str }
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let shadow = validated.diagnostics.filter { diag in
            diag.message.contains("shadows prelude type") &&
            diag.message.contains("'Document'")
        }
        let duplicate = validated.diagnostics.filter { diag in
            diag.message.contains("duplicate user-declared type") &&
            diag.message.contains("'Document'")
        }
        // Both kinds reported (sets are separate); shadow wins for resolution
        // but the duplicate signal is preserved.
        #expect(shadow.count == 1)
        #expect(duplicate.count == 1)
    }

    @Test("Phase 3c.2 validator catches missing required field on user-declared type")
    func phase3c2UserDeclaredRecordMissingFieldIsFlagged() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str }
        :::
        @Person{}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "missing required field 'name' on type 'Person'"
        })
    }

    @Test("Phase 3c.2 validator accepts a complete user-declared record")
    func phase3c2UserDeclaredRecordWithAllRequiredFieldsValidates() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str, age?: int }
        :::
        @Person{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        // No missing-field, no unknown-field, no kind-mismatch, no
        // unresolved-type diagnostics.
        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.allSatisfy { diag in
            !diag.message.contains("missing required field") &&
            !diag.message.contains("unknown field") &&
            !diag.message.contains("expects kind") &&
            !diag.message.contains("unresolved type")
        })
    }

    @Test("Phase 3c.2 validator skips type-shape check for deferred-form field types")
    func phase3c2ValidatorSkipsTypeCheckForDeferredFieldType() throws {
        // Originally used `tags: map<str>`; Phase 3.6 structures that
        // form, so the still-deferred `variant` keeps this regression
        // covered. The validator must still accept the field's value
        // even though the parser couldn't structure its declared type.
        let source = """
        :::schema prelude
        type Item : value = { name: str, payload: variant by kind { a: { v: str }, b: {} } }
        :::
        @Item{name: "Ada", payload: "anything"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.allSatisfy { diag in
            !diag.message.contains("missing required field") &&
            !diag.message.contains("unknown field 'payload'") &&
            !diag.message.contains("wrong shape")
        })
    }

    @Test("Phase 3c.2 validator preserves list shape around deferred element types")
    func phase3c2ValidatorPreservesListShapeAroundDeferredElementTypes() throws {
        // Originally used `[map<str>]`; Phase 3.6 structures `map<T>`,
        // so use the still-deferred `variant by …` as the inner element
        // to keep coverage on "list wrapper preserved around an
        // unstructured element type". The list shape is enforced; the
        // inner type's shape is skipped.
        let inner = "variant by kind { a: { v: str }, b: {} }"
        let validSource = """
        :::schema prelude
        type Item : value = { tags: [\(inner)] }
        :::
        @Item{tags: ["a", "b"]}
        """
        let validParsed = try LiminalParser().parse(validSource)
        let validDocument = LiminalLowerer().lower(validParsed)
        let valid = SchemaValidator().validate(validDocument, against: LiminalPrelude.schema)

        let validAdded = Array(valid.diagnostics.dropFirst(validDocument.diagnostics.count))
        #expect(validAdded.allSatisfy { diag in
            !diag.message.contains("wrong shape")
        })

        let invalidSource = """
        :::schema prelude
        type Item : value = { tags: [\(inner)] }
        :::
        @Item{tags: "not-list"}
        """
        let invalidParsed = try LiminalParser().parse(invalidSource)
        let invalidDocument = LiminalLowerer().lower(invalidParsed)
        let invalid = SchemaValidator().validate(invalidDocument, against: LiminalPrelude.schema)

        #expect(invalid.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "field 'tags' on type 'Item' has the wrong shape for declared type"
        })
    }

    @Test("Phase 3c.2 validator respects optional deferred field types")
    func phase3c2ValidatorRespectsOptionalDeferredFieldTypes() throws {
        let source = """
        :::schema prelude
        type Item : value = { name: str, tags: map<str>? }
        :::
        @Item{name: "Ada"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(!validated.diagnostics.contains { diag in
            diag.message == "missing required field 'tags' on type 'Item'"
        })
    }

    @Test("Phase 3c.2 validator flags unknown field on user-declared type")
    func phase3c2UserDeclaredRecordUnknownFieldIsFlagged() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str }
        :::
        @Person{name: "Ada", extra: "x"}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unknown field 'extra' on type 'Person'"
        })
    }

    @Test("Phase 3c.4 :::if and :::for resolve via the prelude inside templates")
    func phase3c4TemplateControlValidatesViaPrelude() throws {
        let source = """
        :::template Card(person: Person) -> blocks
        :::if{test: person.bio}
        ${person.bio}
        :::
        :::for{item: link, in: person.links}
        ${link.label}
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(!validated.diagnostics.contains {
            $0.message.contains("unresolved type 'if'") ||
            $0.message.contains("unresolved type 'for'")
        })
    }

    @Test("Phase 3c.4 :::if without test field is flagged")
    func phase3c4IfMissingTestFieldIsFlagged() throws {
        let source = """
        :::template Card() -> blocks
        :::if{}
        body
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "missing required field 'test' on type 'if'"
        })
    }

    @Test("Phase 3c.4 :::for without item or in is flagged")
    func phase3c4ForMissingRequiredFieldsIsFlagged() throws {
        let source = """
        :::template Card() -> blocks
        :::for{item: link}
        ${link}
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message == "missing required field 'in' on type 'for'"
        })
    }

    @Test("Phase 3c.4 unknown field on :::if is flagged")
    func phase3c4UnknownFieldOnIfIsFlagged() throws {
        let source = """
        :::template Card() -> blocks
        :::if{test: ok, extra: 1}
        body
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .warning &&
            diag.message == "unknown field 'extra' on type 'if'"
        })
    }

    @Test("Phase 3.5 user redeclaration of reserved type names is an error")
    func phase35ReservedTypeNameRedeclarationIsAnError() throws {
        let source = """
        :::schema prelude
        type if : value = { x: str }
        :::
        :::template Card() -> blocks
        :::if{test: ok}
        body
        :::
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("reserved") &&
            diag.message.contains("'if'")
        })
        // The user redeclared `if` as a value, but the reserved-name
        // rule skips both the shadow warning and the user-index update,
        // so the prelude `if` (kind: .block) continues to win for
        // resolution: the `:::if{test: ok}` inside the template body
        // does not produce an "unresolved type" or kind-mismatch error.
        #expect(!validated.diagnostics.contains { diag in
            diag.message.contains("unresolved type 'if'")
        })
        #expect(!validated.diagnostics.contains { diag in
            diag.message.contains("shadows prelude type") &&
            diag.message.contains("'if'")
        })
    }

    @Test("Phase 3.6 nested optional list element accepts null")
    func phase36NestedOptionalListElementAcceptsNull() throws {
        // Sanity construction: declare a record whose list field has an
        // optional element type, then feed it a list containing a null.
        // The validator must accept that — previously `[str?]` lowered
        // as `.list(.str)` and the null was rejected.
        let listField = SchemaField(
            name: "tags",
            type: .list(.optional(.str))
        )
        let declaration = SchemaTypeDeclaration(
            name: "Item",
            kind: .value,
            definition: .record([listField])
        )
        let schema = LiminalSchema(name: "test", types: [declaration])

        let document = LiminalDocument(items: [
            .value(LiminalNode(
                kind: .value,
                type: "Item",
                fields: [
                    LiminalField(
                        name: "tags",
                        value: .list([
                            .scalar(.string("a")),
                            .scalar(.null),
                            .scalar(.string("b"))
                        ])
                    )
                ]
            ))
        ])

        let validated = SchemaValidator().validate(document, against: schema)
        let added = Array(validated.diagnostics.dropFirst(document.diagnostics.count))
        #expect(added.allSatisfy {
            !$0.message.contains("wrong shape")
        })
    }

    @Test("Phase 3.6 nested optional list rejects null when type is not optional")
    func phase36NestedOptionalListRejectsNullWithoutOptional() throws {
        // Counter-check: `[str]` (no inner optional) still rejects null
        // list elements — we only added permissiveness for `.optional(T)`.
        let listField = SchemaField(name: "tags", type: .list(.str))
        let declaration = SchemaTypeDeclaration(
            name: "Item",
            kind: .value,
            definition: .record([listField])
        )
        let schema = LiminalSchema(name: "test", types: [declaration])

        let document = LiminalDocument(items: [
            .value(LiminalNode(
                kind: .value,
                type: "Item",
                fields: [
                    LiminalField(
                        name: "tags",
                        value: .list([
                            .scalar(.string("a")),
                            .scalar(.null)
                        ])
                    )
                ]
            ))
        ])

        let validated = SchemaValidator().validate(document, against: schema)
        #expect(validated.diagnostics.contains { diag in
            diag.severity == .error &&
            diag.message.contains("wrong shape")
        })
    }

    @Test("Phase 3.6 lowerer preserves nested optional in list element types")
    func phase36LowererPreservesNestedOptionalInList() throws {
        // Drive the lowerer end-to-end: `tags: [str?]` in a user schema
        // must lower as `.list(.optional(.str))`, not `.list(.str)`.
        let source = """
        :::schema prelude
        type Item : value = { tags: [str?] }
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)

        guard case .schema(let block) = document.items.first,
              let declaration = block.declarations.first,
              case .record(let fields) = declaration.definition
        else {
            Issue.record("expected lowered user-declared record")
            return
        }

        let tags = try #require(fields.first { $0.name.rawValue == "tags" })
        #expect(tags.type == .list(.optional(.str)))
        #expect(tags.isOptional == false)
    }

    @Test("Phase 3.6 lowerer hoists outer optional into SchemaField.isOptional")
    func phase36LowererHoistsOuterOptional() throws {
        // Backward-compat at the field boundary: `field: str?` continues
        // to lower with `isOptional: true` and `type: .str` (the outer
        // `.optional` wrapper is peeled into the field flag).
        let source = """
        :::schema prelude
        type Person : value = { nick: str? }
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)

        guard case .schema(let block) = document.items.first,
              let declaration = block.declarations.first,
              case .record(let fields) = declaration.definition
        else {
            Issue.record("expected lowered user-declared record")
            return
        }
        let nick = try #require(fields.first { $0.name.rawValue == "nick" })
        #expect(nick.type == .str)
        #expect(nick.isOptional == true)
    }

    @Test("Phase 3.6 enum schema type lowers to .enumeration with cases")
    func phase36EnumSchemaTypeLowersToEnumeration() throws {
        let source = """
        :::schema prelude
        type Color : value = enum { red, green, blue }
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)

        guard case .schema(let block) = document.items.first,
              let declaration = block.declarations.first
        else {
            Issue.record("expected lowered user-declared enum")
            return
        }
        #expect(declaration.definition == .enumeration(["red", "green", "blue"]))
    }

    @Test("Phase 3.6 map/ref/embed lower to their SchemaTypeExpression cases")
    func phase36MapRefEmbedLowerToTypeExpressions() throws {
        let source = """
        :::schema prelude
        type Tags : value = map<str>
        type Refs : value = ref<Person>
        type Pic : value = embed<Image>
        :::
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)

        guard case .schema(let block) = document.items.first else {
            Issue.record("expected lowered schema block")
            return
        }
        let byName = Dictionary(uniqueKeysWithValues: block.declarations.map { ($0.name.rawValue, $0) })

        #expect(byName["Tags"]?.definition == .map(.str))
        #expect(byName["Refs"]?.definition == .reference(.named("Person")))
        #expect(byName["Pic"]?.definition == .embed(.named("Image")))
    }

    @Test("Phase 3.6 enum field validation accepts known cases and rejects unknown")
    func phase36EnumFieldValidatesCases() throws {
        // Inline an `enum {...}` directly in the field value-type slot;
        // that exercises `.enumeration` at validate time without going
        // through named-type indirection (named-type-following is a
        // separate validator concern).
        let source = """
        :::schema prelude
        type Painted : value = { tint: enum { red, green, blue } }
        :::
        @Painted{tint: red}
        @Painted{tint: purple}
        """
        let parsed = try LiminalParser().parse(source)
        let document = LiminalLowerer().lower(parsed)
        let validated = SchemaValidator().validate(document, against: LiminalPrelude.schema)

        let shapeErrors = validated.diagnostics.filter {
            $0.severity == .error &&
            $0.message.contains("wrong shape") &&
            $0.message.contains("'tint'")
        }
        #expect(shapeErrors.count == 1, "expected exactly one wrong-shape error (purple), got \(shapeErrors.count)")
    }
}
