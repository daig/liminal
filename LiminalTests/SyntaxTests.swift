import CambiumCore
import Testing
@testable import Liminal

@Suite("Syntax")
struct SyntaxTests {
    @Test("syntax kinds use stable Phase 0 raw bands")
    func syntaxKindRawBandsAreStable() {
        #expect(LiminalLanguage.serializationVersion == 7)

        #expect(LiminalKind.whitespace.rawValue == 1)
        #expect(LiminalKind.newline.rawValue == 2)

        #expect(LiminalKind.atSign.rawValue == 10)
        #expect(LiminalKind.semicolon.rawValue == 41)
        #expect(LiminalKind.rawPayloadText.rawValue == 72)
        #expect(LiminalKind.errorText.rawValue == 82)

        #expect(LiminalKind.root.rawValue == 100)
        #expect(LiminalKind.atxHeading.rawValue == 106)
        #expect(LiminalKind.typedBlock.rawValue == 115)

        #expect(LiminalKind.inlineContent.rawValue == 200)
        #expect(LiminalKind.mdLink.rawValue == 209)
        #expect(LiminalKind.wikiEmbed.rawValue == 213)

        #expect(LiminalKind.value.rawValue == 300)
        #expect(LiminalKind.schemaBlock.rawValue == 312)
        #expect(LiminalKind.templateBlock.rawValue == 319)

        #expect(LiminalKind.missing.rawValue == 900)
        #expect(LiminalKind.error.rawValue == 901)
    }

    @Test("syntax kinds satisfy Cambium language classification")
    func kindClassificationUsesCambiumLanguageContract() {
        #expect(LiminalLanguage.isTrivia(.whitespace))
        #expect(LiminalLanguage.isTrivia(.newline))
        #expect(!LiminalLanguage.isTrivia(.commentBlock))
        #expect(!LiminalLanguage.isTrivia(.commentText))

        #expect(LiminalLanguage.isNode(.root))
        #expect(LiminalLanguage.isNode(.paragraph))
        #expect(LiminalLanguage.isNode(.mdLink))
        #expect(LiminalLanguage.isNode(.schemaBlock))
        #expect(LiminalLanguage.isNode(.missing))
        #expect(LiminalLanguage.isNode(.error))

        #expect(LiminalLanguage.isToken(.rawPayloadText))
        #expect(LiminalLanguage.isToken(.errorText))
        #expect(LiminalLanguage.isToken(.qname))
        #expect(LiminalLanguage.isToken(.commentText))
        #expect(!LiminalLanguage.isToken(.root))

        #expect(LiminalLanguage.name(for: .rawPayloadText) == "rawPayloadText")
        #expect(LiminalLanguage.name(for: .errorText) == "errorText")
        #expect(LiminalLanguage.kind(for: RawSyntaxKind(100)) == .root)
        #expect(LiminalLanguage.kind(for: RawSyntaxKind(900)) == .missing)
    }

    @Test("static punctuation and dynamic text token contracts are pinned")
    func staticAndDynamicTokenContractsArePinned() {
        #expect(string(for: LiminalLanguage.staticText(for: .atSign)) == "@")
        #expect(string(for: LiminalLanguage.staticText(for: .leftBracket)) == "[")
        #expect(string(for: LiminalLanguage.staticText(for: .rightParen)) == ")")
        #expect(string(for: LiminalLanguage.staticText(for: .backslash)) == "\\")
        #expect(string(for: LiminalLanguage.staticText(for: .doubleQuote)) == "\"")
        #expect(string(for: LiminalLanguage.staticText(for: .semicolon)) == ";")

        #expect(LiminalLanguage.staticText(for: .whitespace) == nil)
        #expect(LiminalLanguage.staticText(for: .qname) == nil)
        #expect(LiminalLanguage.staticText(for: .rawPayloadText) == nil)
        #expect(LiminalLanguage.staticText(for: .errorText) == nil)
        #expect(LiminalLanguage.staticText(for: .commentText) == nil)
    }

    @Test(
        "parser preserves source bytes in the Cambium root tree",
        arguments: [
            ParseExpectation(description: "empty source", source: "", rootChildKinds: []),
            ParseExpectation(description: "single line ASCII", source: "plain text", rootChildKinds: [.paragraph]),
            ParseExpectation(
                description: "multiline source",
                source: "First paragraph\n\nSecond paragraph\n",
                rootChildKinds: [.paragraph, .blankLine, .paragraph]
            ),
            ParseExpectation(
                description: "unicode source",
                source: "Body with unicode: λ, 文字, and emoji: 🧠\n",
                rootChildKinds: [.paragraph]
            ),
            ParseExpectation(
                description: "markdown-like source",
                source: "# Typed documents\n\n- [[Note#Heading]]\n- `code`\n",
                rootChildKinds: [.atxHeading, .blankLine, .list]
            )
        ]
    )
    func parserBuildsLosslessRootTree(_ expectation: ParseExpectation) throws {
        let result = try LiminalParser().parse(expectation.source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == expectation.source)

        let byteLength = try TextSize(byteCountOf: expectation.source)
        result.tree.withRoot { root in
            #expect(root.kind == .root)
            #expect(root.textLength == byteLength)

            var childKinds: [LiminalKind] = []
            root.forEachChild { child in
                childKinds.append(child.kind)
            }

            #expect(childKinds == expectation.rootChildKinds)
        }
    }

    @Test("typed root overlay wraps the parsed Cambium root")
    func typedRootOverlayWrapsParsedCambiumRoot() throws {
        let source = "# Typed documents\n\nBody with unicode: λ\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax
        let byteLength = try TextSize(byteCountOf: source)

        #expect(RootSyntax.kind == .root)
        #expect(root.sourceText == source)
        #expect(root.range == TextRange(start: .zero, length: byteLength))
        #expect(RootSyntax(result.tree.rootHandle())?.syntax == root.syntax)
    }

    @Test("typed root overlay exposes Slice 1 document items")
    func typedRootOverlayExposesSlice1DocumentItems() throws {
        let source = "plain `code` and [[Target|Alias]]\n![[Embed#Heading|payload]]\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(root.documentItems.count == 2)
        #expect(root.tokens.isEmpty)
        #expect(root.rawPayloadToken == nil)

        guard case .paragraph(let paragraph) = root.documentItems[0] else {
            Issue.record("expected paragraph")
            return
        }
        let inlineContent = try #require(paragraph.inlineContent)
        #expect(inlineContent.inlineNodes.map(\.range).count == 2)

        guard case .wikiEmbedBlock(let embed) = root.documentItems[1] else {
            Issue.record("expected wiki embed block")
            return
        }
        #expect(embed.targetText == "Embed#Heading")
        #expect(embed.payloadText == "payload")
    }

    @Test("markdown links and images expose CST title tokens")
    func markdownLinksAndImagesExposeCSTTitleTokens() throws {
        let source = #"See [site]( https://example.org "Title" ) and ![Alt](image.png 'Caption')."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes,
              inlineNodes.count == 2,
              case .mdLink(let link) = inlineNodes[0],
              case .mdImage(let image) = inlineNodes[1]
        else {
            Issue.record("expected markdown link and image nodes")
            return
        }

        #expect(link.destinationText == "https://example.org")
        #expect(link.titleText == "Title")
        #expect(image.destinationText == "image.png")
        #expect(image.titleText == "Caption")
    }

    @Test("reference target accessors expose direct CST tokens and ranges")
    func referenceTargetAccessorsExposeDirectCSTTokensAndRanges() throws {
        let source = #"See [[Target|Alias]] and [site](https://example.org "Title")."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes,
              inlineNodes.count == 2,
              case .wikilink(let wikilink) = inlineNodes[0],
              case .mdLink(let link) = inlineNodes[1]
        else {
            Issue.record("expected wikilink and markdown link nodes")
            return
        }

        #expect(wikilink.targetTextToken?.text == "Target")
        let wikilinkTargetRange = try sourceRange(of: "Target", in: source)
        #expect(wikilink.targetTextToken?.range == wikilinkTargetRange)
        #expect(link.destinationTextToken?.text == "https://example.org")
        let linkDestinationRange = try sourceRange(of: "https://example.org", in: source)
        #expect(link.destinationTextToken?.range == linkDestinationRange)
        #expect(link.titleTextToken?.text == "Title")
    }

    @Test("Slice 3 parser emits block ID suffixes for paragraphs and headings")
    func slice3ParserEmitsBlockIDSuffixesForParagraphsAndHeadings() throws {
        let source = "Paragraph text ^para-id\n# Heading `code` ^heading-id ###\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 2)

        guard case .paragraph(let paragraph) = root.documentItems[0] else {
            Issue.record("expected paragraph")
            return
        }
        let paragraphBlockIDRange = try sourceRange(of: "para-id", in: source)
        #expect(paragraph.inlineContent?.sourceText == "Paragraph text")
        #expect(paragraph.blockIdToken?.text == "para-id")
        #expect(paragraph.blockIdToken?.range == paragraphBlockIDRange)

        guard case .atxHeading(let heading) = root.documentItems[1] else {
            Issue.record("expected heading")
            return
        }
        let headingBlockIDRange = try sourceRange(of: "heading-id", in: source)
        #expect(heading.inlineContent?.sourceText == "Heading `code`")
        #expect(heading.blockIdToken?.text == "heading-id")
        #expect(heading.blockIdToken?.range == headingBlockIDRange)
    }

    @Test("invalid block ID suffix candidates remain inline text")
    func invalidBlockIDSuffixCandidatesRemainInlineText() throws {
        let source = "Paragraph^id\n\nParagraph ^\n\nParagraph ^id extra\n"
        let root = try LiminalParser().parse(source).rootSyntax
        let paragraphs = root.documentItems.compactMap { item -> ParagraphSyntax? in
            guard case .paragraph(let paragraph) = item else {
                return nil
            }
            return paragraph
        }

        #expect(paragraphs.count == 3)
        #expect(paragraphs.allSatisfy { $0.blockIdToken == nil })
        #expect(paragraphs.map { $0.inlineContent?.sourceText ?? "" } == [
            "Paragraph^id",
            "Paragraph ^",
            "Paragraph ^id extra"
        ])
    }

    @Test("Slice 4 parser emits recursive list CST")
    func slice4ParserEmitsRecursiveListCST() throws {
        let source = """
        - [ ] First [[Target]] ^item-id
              - Nested
        2. Ordered
        3. Next
        + Plus
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 3)

        guard case .list(let dashList) = root.documentItems[0] else {
            Issue.record("expected dash list")
            return
        }
        #expect(dashList.isOrdered == false)
        #expect(dashList.markerText == "-")
        #expect(dashList.items.count == 1)
        #expect(dashList.items[0].taskState == .unchecked)
        #expect(dashList.items[0].blockIdToken?.text == "item-id")
        #expect(dashList.items[0].documentItems.count == 2)
        guard case .list(let nestedList) = dashList.items[0].documentItems[1] else {
            Issue.record("expected nested list")
            return
        }
        #expect(nestedList.items.count == 1)

        guard case .list(let orderedList) = root.documentItems[1] else {
            Issue.record("expected ordered list")
            return
        }
        #expect(orderedList.isOrdered)
        #expect(orderedList.startNumber == 2)
        #expect(orderedList.items.count == 2)

        guard case .list(let plusList) = root.documentItems[2] else {
            Issue.record("expected plus marker list")
            return
        }
        #expect(plusList.markerText == "+")
    }

    @Test("Slice 4 parser emits blockquotes and rejects lazy continuation")
    func slice4ParserEmitsBlockquotesAndRejectsLazyContinuation() throws {
        let source = """
        > Quote [[Target]]
        > More
        > - Item
        after quote

        - item
        lazy continuation
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.sourceText == source)
        #expect(result.diagnostics.isEmpty)
        #expect(root.documentItems.count == 5)

        guard case .blockQuote(let quote) = root.documentItems[0] else {
            Issue.record("expected blockquote")
            return
        }
        #expect(quote.documentItems.count == 2)
        guard case .paragraph(let quoteParagraph) = quote.documentItems[0],
              case .list = quote.documentItems[1]
        else {
            Issue.record("expected paragraph and list inside blockquote")
            return
        }
        #expect(quoteParagraph.inlineContent?.plainText == "Quote Target More")

        guard case .paragraph(let afterQuote) = root.documentItems[1],
              case .list(let list) = root.documentItems[3],
              case .paragraph(let lazyParagraph) = root.documentItems[4]
        else {
            Issue.record("expected lazy continuation to become a following paragraph")
            return
        }
        #expect(afterQuote.inlineContent?.plainText == "after quote")
        #expect(list.items.count == 1)
        #expect(lazyParagraph.inlineContent?.plainText == "lazy continuation")
    }

    @Test("Slice 5 parser emits content block CST losslessly")
    func slice5ParserEmitsContentBlockCSTLosslessly() throws {
        let source = """
        ---
        title: Ada
        ---

        ```swift linenos
        print("hello")
        ```

        $$
        E = mc^2
        $$

        %%
        hidden [[Not Indexed]]
        %%
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 7)

        guard case .frontmatter(let frontmatter) = root.documentItems[0],
              case .fencedCodeBlock(let codeBlock) = root.documentItems[2],
              case .mathBlock(let mathBlock) = root.documentItems[4],
              case .commentBlock(let commentBlock) = root.documentItems[6]
        else {
            Issue.record("expected frontmatter, code, math, and comment blocks")
            return
        }

        #expect(frontmatter.rawYamlText == "title: Ada\n")
        #expect(codeBlock.infoText == "swift linenos")
        #expect(codeBlock.languageText == "swift")
        #expect(codeBlock.codeText == #"print("hello")"# + "\n")
        #expect(mathBlock.texText == "E = mc^2\n")
        #expect(commentBlock.rawText == "hidden [[Not Indexed]]\n")
    }

    @Test("Slice 5 parser emits rich inline CST")
    func slice5ParserEmitsRichInlineCST() throws {
        let source = #"~~deleted [[Target]]~~ ==marked== ^[note [[Foot]]] \(x^2\) %% hidden %% $x$"#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineContent = paragraph.inlineContent
        else {
            Issue.record("expected paragraph")
            return
        }

        let inlineNodes = inlineContent.inlineNodes
        #expect(inlineNodes.count == 5)
        guard case .strikethrough(let strike) = inlineNodes[0],
              case .highlight(let highlight) = inlineNodes[1],
              case .footnoteInline(let footnote) = inlineNodes[2],
              case .mathInline(let math) = inlineNodes[3],
              case .inlineComment(let comment) = inlineNodes[4]
        else {
            Issue.record("expected slice 5 inline nodes")
            return
        }

        #expect(strike.inlineContent?.plainText == "deleted Target")
        #expect(highlight.inlineContent?.plainText == "marked")
        #expect(footnote.inlineContent?.plainText == "note Foot")
        #expect(math.texText == "x^2")
        #expect(comment.rawText == " hidden ")
        #expect(inlineContent.plainText.hasSuffix(" $x$"))
    }

    @Test("Slice 5 parser recovers incomplete content blocks and rich inline")
    func slice5ParserRecoversIncompleteContentBlocksAndRichInline() throws {
        let blockSource = "```swift\nunterminated\n"
        let blockResult = try LiminalParser().parse(blockSource)
        #expect(blockResult.sourceText == blockSource)
        #expect(blockResult.diagnostics.map(\.message) == [
            "missing closing code block fence"
        ])

        let inlineSource = #"%% hidden \(math ^[footnote ~~strike ==highlight"#
        let inlineResult = try LiminalParser().parse(inlineSource)
        #expect(inlineResult.sourceText == inlineSource)
        #expect(inlineResult.diagnostics.map(\.message).contains("missing closing inline comment delimiter"))
    }

    @Test("frontmatter parser emits leading BOM as whitespace trivia")
    func frontmatterParserEmitsLeadingBOMAsWhitespaceTrivia() throws {
        let source = "\u{FEFF}---\ntitle: Ada\n---\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)

        guard case .frontmatter(let frontmatter) = root.documentItems.first else {
            Issue.record("expected frontmatter")
            return
        }

        // BOM is preserved in the source bytes but kept out of the YAML payload.
        #expect(frontmatter.rawYamlText == "title: Ada\n")
        #expect(frontmatter.sourceText.hasPrefix("\u{FEFF}"))
    }

    @Test("raw payload inline delimiters ignore backslash escapes")
    func rawPayloadInlineDelimitersIgnoreBackslashEscapes() throws {
        // Math content is raw text per spec §7.10 — `\)` always closes
        // at the first occurrence, even when preceded by a backslash
        // that would mark it as escaped in non-raw contexts.
        // Source `\(x \\) y\)` would, under escape-honoring rules, treat
        // the first `\)` (at position 5-6) as escaped and close at the
        // second `\)`. Under raw rules, it closes at position 5-6.
        let mathSource = #"\(x \\) y\)"#
        let mathRoot = try LiminalParser().parse(mathSource).rootSyntax
        guard case .paragraph(let mathParagraph) = mathRoot.documentItems.first,
              let mathInlines = mathParagraph.inlineContent?.inlineNodes,
              case .mathInline(let math) = mathInlines.first
        else {
            Issue.record("expected math inline node")
            return
        }
        #expect(math.texText == "x \\")
        #expect(mathRoot.sourceText == mathSource)

        // Comment content is raw text per spec §7.12 — `%%` always
        // closes at the first occurrence even when preceded by `\`.
        let commentSource = #"text %%a \%% rest %%"#
        let commentRoot = try LiminalParser().parse(commentSource).rootSyntax
        guard case .paragraph(let commentParagraph) = commentRoot.documentItems.first,
              let commentInlines = commentParagraph.inlineContent?.inlineNodes,
              case .inlineComment(let comment) = commentInlines.first
        else {
            Issue.record("expected inline comment node")
            return
        }
        #expect(comment.rawText == "a \\")
        #expect(commentRoot.sourceText == commentSource)
    }

    @Test("Slice 6 parser emits pipe table CST losslessly")
    func slice6ParserEmitsPipeTableCSTLosslessly() throws {
        let source = """
        | Name | Born | Note |
        | :--- | ---: | :---: |
        | Ada \\| Countess | 1815 | [[Ada]] |

        Plain | Header
        --- | ---:
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 3)

        guard case .pipeTable(let table) = root.documentItems[0],
              case .blankLine = root.documentItems[1],
              case .pipeTable(let noOuterPipeTable) = root.documentItems[2]
        else {
            Issue.record("expected two pipe tables separated by a blank line")
            return
        }

        #expect(table.headerCells.map { $0.inlineContent?.plainText ?? "" } == [
            "Name",
            "Born",
            "Note"
        ])
        #expect(table.alignments == [.left, .right, .center])
        #expect(table.bodyRows.count == 1)
        #expect(table.bodyRows[0].map { $0.inlineContent?.plainText ?? "" } == [
            "Ada | Countess",
            "1815",
            "Ada"
        ])

        #expect(noOuterPipeTable.headerCells.map { $0.inlineContent?.plainText ?? "" } == [
            "Plain",
            "Header"
        ])
        #expect(noOuterPipeTable.alignments == [nil, .right])
    }

    @Test("Slice 6 parser keeps mismatched table rows in the CST with diagnostics")
    func slice6ParserKeepsMismatchedTableRowsInCSTWithDiagnostics() throws {
        let source = """
        | A | B |
        | --- |
        | one |
        | two | three | extra |
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.message) == [
            "pipe table header and delimiter column counts differ",
            "pipe table body row column count differs from header",
            "pipe table body row column count differs from header"
        ])

        guard case .pipeTable(let table) = root.documentItems.first else {
            Issue.record("expected pipe table")
            return
        }
        #expect(table.headerCells.count == 2)
        #expect(table.alignments.count == 1)
        #expect(table.bodyRows.map(\.count) == [1, 3])
    }

    @Test("Slice 6 invalid table delimiters remain paragraph text")
    func slice6InvalidTableDelimitersRemainParagraphText() throws {
        let source = """
        A | B
        -- | ---
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 1)
        guard case .paragraph(let paragraph) = root.documentItems.first else {
            Issue.record("expected paragraph")
            return
        }
        #expect(paragraph.inlineContent?.plainText == "A | B -- | ---")
    }

    @Test("Slice 6 parses only explicit HtmlBlock fences as HTML blocks")
    func slice6ParsesOnlyExplicitHtmlBlockFencesAsHTMLBlocks() throws {
        let source = """
        <div>paragraph</div>
        :::HtmlBlock
        <div>raw</div>
        :::
        :::HtmlBlock
        unterminated
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.message) == [
            "missing closing HtmlBlock fence"
        ])
        #expect(root.documentItems.count == 3)

        guard case .paragraph(let paragraph) = root.documentItems[0],
              case .htmlBlock(let htmlBlock) = root.documentItems[1],
              case .htmlBlock(let incompleteHtmlBlock) = root.documentItems[2]
        else {
            Issue.record("expected paragraph followed by explicit HTML blocks")
            return
        }

        #expect(paragraph.inlineContent?.plainText == "<div>paragraph</div>")
        #expect(htmlBlock.rawText == "<div>raw</div>\n")
        #expect(incompleteHtmlBlock.rawText == "unterminated")
        #expect(root.firstDescendantToken(kind: .htmlText)?.text == "<div>raw</div>\n")
    }

    @Test("Slice 7 parser emits language-level item CST losslessly")
    func slice7ParserEmitsLanguageLevelItemCSTLosslessly() throws {
        let source = """
        ::use type "./schema.lim" as schema
        :::schema prelude
        type Person : value = {
          name: str
        }
        :::
        :::template PersonCard(person: Person) -> blocks
        :::if{test: person.bio}
        Bio ${person.bio} [[Target]]
        :::
        :::
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 3)

        guard case .directive(let directive) = root.documentItems[0],
              case .schemaBlock(let schema) = root.documentItems[1],
              case .templateBlock(let template) = root.documentItems[2]
        else {
            Issue.record("expected directive, schema, and template document items")
            return
        }

        #expect(directive.keywordText == "use")
        #expect(directive.bodyText == #"type "./schema.lim" as schema"#)
        #expect(schema.nameText == "prelude")
        #expect(schema.rawText.contains("type Person : value"))
        #expect(template.signatureText == "PersonCard(person: Person) -> blocks")
        #expect(template.documentItems.count == 1)

        guard case .typedBlock(let control) = template.documentItems[0],
              let paragraph = control.documentItems.first,
              case .paragraph(let bodyParagraph) = paragraph,
              let inlineNodes = bodyParagraph.inlineContent?.inlineNodes,
              inlineNodes.count == 2,
              case .interpolation(let interpolation) = inlineNodes[0],
              case .wikilink(let wikilink) = inlineNodes[1]
        else {
            Issue.record("expected template control body with interpolation and wikilink")
            return
        }

        #expect(control.typeName == "if")
        #expect(interpolation.expressionText == "person.bio")
        #expect(wikilink.targetText == "Target")
    }

    @Test("Phase 3b.2 parser structures ::use directive bodies")
    func phase3b2ParserStructuresUseDirective() throws {
        let source = """
        ::use type "./schema.lim" as schema
        ::use data "./people.lim" only { Entry, Citation } as people
        ::use "./bibliography.lim"
        ::use ./bare-path
        """
        let result = try LiminalParser().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(result.rootSyntax.documentItems.count == 4)

        let directives = result.rootSyntax.documentItems.compactMap { item -> UseDirectiveSyntax? in
            guard case .directive(let directive) = item else { return nil }
            return directive.useDirective
        }
        #expect(directives.count == 4)

        // 0: kind + quoted target + alias
        #expect(directives[0].kindText == "type")
        #expect(directives[0].targetText == "./schema.lim")
        #expect(directives[0].targetIsQuoted)
        #expect(directives[0].filterQNames.isEmpty)
        #expect(directives[0].aliasText == "schema")

        // 1: kind + filter + alias
        #expect(directives[1].kindText == "data")
        #expect(directives[1].targetText == "./people.lim")
        #expect(directives[1].filterQNames == ["Entry", "Citation"])
        #expect(directives[1].aliasText == "people")

        // 2: just a quoted target
        #expect(directives[2].kindText == nil)
        #expect(directives[2].targetText == "./bibliography.lim")
        #expect(directives[2].targetIsQuoted)
        #expect(directives[2].filterQNames.isEmpty)
        #expect(directives[2].aliasText == nil)

        // 3: bare-scalar target
        #expect(directives[3].kindText == nil)
        #expect(directives[3].targetText == "./bare-path")
        #expect(!directives[3].targetIsQuoted)
        #expect(directives[3].aliasText == nil)
    }

    @Test("Phase 3b.2 parser preserves the slice 7 ::use bodyText contract")
    func phase3b2ParserPreservesUseDirectiveBodyText() throws {
        let source = #"::use type "./schema.lim" as schema"# + "\n"
        let result = try LiminalParser().parse(source)

        guard case .directive(let directive) = result.rootSyntax.documentItems.first else {
            Issue.record("expected directive document item")
            return
        }

        #expect(directive.keywordText == "use")
        #expect(directive.bodyText == #"type "./schema.lim" as schema"#)
    }

    @Test("Phase 3b.2 parser recovers from malformed ::use directives")
    func phase3b2ParserRecoversMalformedUseDirective() throws {
        // Missing closing `}` in the filter.
        let unclosedFilter = "::use \"./schema.lim\" only { Foo, Bar\n"
        let unclosedResult = try LiminalParser().parse(unclosedFilter)
        #expect(unclosedResult.sourceText == unclosedFilter)
        #expect(unclosedResult.diagnostics.contains { $0.message.contains("missing closing `}`") })

        // Missing alias identifier after `as`.
        let missingAlias = "::use \"./schema.lim\" as\n"
        let missingAliasResult = try LiminalParser().parse(missingAlias)
        #expect(missingAliasResult.sourceText == missingAlias)
        #expect(missingAliasResult.diagnostics.contains {
            $0.message.contains("expected alias identifier")
        })
    }

    @Test("Phase 3b.1 parser structures :::schema declaration shells")
    func phase3b1ParserStructuresSchemaDeclarations() throws {
        let source = """
        :::schema prelude
        type Person : value = {
          name: str
        }
        type Card : block = { title: str }
        type Render : template = PersonCard(p: Person) -> blocks
        :::
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 1)

        guard case .schemaBlock(let schema) = root.documentItems.first else {
            Issue.record("expected schema block")
            return
        }

        #expect(schema.declarations.count == 2)
        #expect(schema.templateDeclarations.count == 1)

        #expect(schema.declarations[0].qnameText == "Person")
        #expect(schema.declarations[0].nodeKindText == "value")
        #expect(schema.declarations[0].rhsText.contains("name: str"))

        #expect(schema.declarations[1].qnameText == "Card")
        #expect(schema.declarations[1].nodeKindText == "block")

        #expect(schema.templateDeclarations[0].qnameText == "Render")
        #expect(schema.templateDeclarations[0].nodeKindText == "template")
        #expect(schema.templateDeclarations[0].signatureText.contains("PersonCard"))
    }

    @Test("Phase 3b.1 parser preserves schema rawText for slice 7 sources")
    func phase3b1ParserPreservesSchemaRawText() throws {
        // Re-run the slice 7 source verbatim and confirm `schema.rawText`
        // (now derived from `body.sourceText`) still produces the same
        // substring the slice 7 test pinned.
        let source = """
        ::use type "./schema.lim" as schema
        :::schema prelude
        type Person : value = {
          name: str
        }
        :::
        :::template PersonCard(person: Person) -> blocks
        :::if{test: person.bio}
        Bio ${person.bio} [[Target]]
        :::
        :::
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.sourceText == source)
        #expect(result.diagnostics.isEmpty)

        guard case .schemaBlock(let schema) = root.documentItems[1] else {
            Issue.record("expected schema block document item")
            return
        }
        #expect(schema.rawText.contains("type Person : value"))
        #expect(schema.rawText.contains("name: str"))
    }

    @Test("Phase 3b.1 parser recovers from a malformed schema declaration")
    func phase3b1ParserRecoversMalformedSchemaDeclaration() throws {
        let source = """
        :::schema prelude
        type Person value = {}
        type Card : block = {}
        :::
        """
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.contains { $0.message.contains("expected `:`") })

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        // Recovery doesn't drop subsequent declarations.
        let names = schema.declarations.map(\.qnameText)
        #expect(names.contains("Card"))
    }

    @Test("Phase 3c.1 parser structures interpolation expressions")
    func phase3c1ParserStructuresInterpolationExpressions() throws {
        // One line per shape — each interpolation should expose a structured
        // .interpolationExpression child whose source text equals the body
        // between `${` and `}`.
        let cases: [(source: String, expectedBody: String)] = [
            ("Hello ${person}\n", "person"),
            ("Hello ${person.name}\n", "person.name"),
            ("Hello ${items[0]}\n", "items[0]"),
            ("Hello ${a ?? b}\n", "a ?? b"),
            ("Hello ${(a)}\n", "(a)"),
            (#"Hello ${"literal"}"# + "\n", #""literal""#),
            ("Hello ${42}\n", "42"),
            ("Hello ${1.5}\n", "1.5"),
            ("Hello ${-1}\n", "-1"),
            ("Hello ${-1.5}\n", "-1.5"),
            ("Hello ${true}\n", "true"),
            ("Hello ${null}\n", "null"),
            ("Hello ${&ada}\n", "&ada")
        ]

        for testCase in cases {
            let result = try LiminalParser().parse(testCase.source)
            #expect(result.diagnostics.isEmpty, "diagnostics for \(testCase.source.debugDescription)")
            #expect(result.sourceText == testCase.source)

            let interpolation = firstInterpolation(in: result.rootSyntax)
            let interp = try #require(interpolation, "no interpolation in \(testCase.source.debugDescription)")
            #expect(
                interp.expressionText == testCase.expectedBody,
                "expressionText mismatch for \(testCase.source.debugDescription): got \(interp.expressionText.debugDescription)"
            )
            #expect(
                interp.expression != nil,
                "missing structured expression for \(testCase.source.debugDescription)"
            )
        }

        let negativeInteger = try LiminalParser().parse("Hello ${-1}\n")
        #expect(negativeInteger.rootSyntax.firstDescendantToken(kind: .integerLiteral)?.text == "-1")

        let negativeNumber = try LiminalParser().parse("Hello ${-1.5}\n")
        #expect(negativeNumber.rootSyntax.firstDescendantToken(kind: .numberLiteral)?.text == "-1.5")
    }

    @Test("Phase 3c.1 parenthesized expression nests inside outer wrapper")
    func phase3c1ParenthesizedExpressionNestsWrapper() throws {
        let source = "Hello ${(person.name)}\n"
        let result = try LiminalParser().parse(source)
        let interpolation = try #require(firstInterpolation(in: result.rootSyntax))
        let outer = try #require(interpolation.expression)
        #expect(outer.subExpressions.count == 1)
        let inner = outer.subExpressions[0]
        #expect(inner.sourceText == "person.name")
    }

    @Test("Phase 3c.1 parser recovers from malformed interpolation expressions")
    func phase3c1ParserRecoversMalformedInterpolationExpression() throws {
        // Unterminated `${...` keeps the slice 7 diagnostic.
        let unterminated = "Hello ${person.name\n"
        let unterm = try LiminalParser().parse(unterminated)
        #expect(unterm.sourceText == unterminated)
        #expect(unterm.diagnostics.contains {
            $0.message == "missing closing interpolation delimiter"
        })

        // Stray `??` with no rhs.
        let danglingCoalesce = "Hello ${a ?? }\n"
        let dangling = try LiminalParser().parse(danglingCoalesce)
        #expect(dangling.sourceText == danglingCoalesce)
        #expect(dangling.diagnostics.contains {
            $0.message.contains("missing right-hand side after `??`")
        })

        // Unparseable garbage falls back to .interpolationText salvage so
        // the bytes round-trip without losing source content.
        let garbage = "Hello ${@@@}\n"
        let garbageResult = try LiminalParser().parse(garbage)
        #expect(garbageResult.sourceText == garbage)
        #expect(garbageResult.diagnostics.contains {
            $0.message == "unrecognized interpolation expression token"
        })

        // Trailing garbage after an otherwise valid prefix also diagnoses
        // while preserving the original bytes.
        let trailingGarbage = "Hello ${person @@@}\n"
        let trailingResult = try LiminalParser().parse(trailingGarbage)
        #expect(trailingResult.sourceText == trailingGarbage)
        #expect(trailingResult.diagnostics.contains {
            $0.message == "unrecognized interpolation expression token"
        })

        // The grammar allows only one `??` operator in this slice; a second
        // one is salvaged and diagnosed instead of being silently accepted.
        let repeatedCoalesce = "Hello ${a ?? b ?? c}\n"
        let repeatedResult = try LiminalParser().parse(repeatedCoalesce)
        #expect(repeatedResult.sourceText == repeatedCoalesce)
        #expect(repeatedResult.diagnostics.contains {
            $0.message == "unrecognized interpolation expression token"
        })

        // Empty expression bodies are invalid but remain lossless.
        let empty = "Hello ${}\n"
        let emptyResult = try LiminalParser().parse(empty)
        #expect(emptyResult.sourceText == empty)
        #expect(emptyResult.diagnostics.contains {
            $0.message == "missing interpolation expression"
        })

        let emptyParens = "Hello ${()}\n"
        let emptyParensResult = try LiminalParser().parse(emptyParens)
        #expect(emptyParensResult.sourceText == emptyParens)
        #expect(emptyParensResult.diagnostics.contains {
            $0.message == "missing interpolation expression"
        })
    }

    @Test("Phase 3c.2 parser structures schema RHS into TypeExpr CST")
    func phase3c2ParserStructuresSchemaRHS() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str, age?: int @readonly }
        type Tags : value = [str]
        type Maybe : value = str?
        type Card : block = { title: str @content }
        :::
        """
        let result = try LiminalParser().parse(source)
        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }

        #expect(schema.declarations.count == 4)

        // Person — record with two fields.
        let person = try #require(schema.declarations[0].definition)
        #expect(person.isRecord)
        let personFields = person.recordFields
        #expect(personFields.map(\.fieldNameText) == ["name", "age"])
        #expect(personFields[0].valueType?.qnameText == "str")
        #expect(personFields[0].isOptional == false)
        #expect(personFields[1].isOptional == true)
        #expect(personFields[1].valueType?.qnameText == "int")
        #expect(personFields[1].modifiers.map(\.modifierName) == ["readonly"])

        // Tags — list of str.
        let tags = try #require(schema.declarations[1].definition)
        #expect(tags.isList)
        #expect(tags.listElementType?.qnameText == "str")

        // Maybe — optional str.
        let maybe = try #require(schema.declarations[2].definition)
        #expect(maybe.qnameText == "str")
        #expect(maybe.isOptional)

        // Card — record with @content modifier.
        let card = try #require(schema.declarations[3].definition)
        #expect(card.isRecord)
        let titleField = try #require(card.recordFields.first)
        #expect(titleField.modifiers.map(\.modifierName) == ["content"])
    }

    @Test("Phase 3c.2 parser captures modifier arguments as raw text")
    func phase3c2ParserCapturesModifierArgumentsAsRawText() throws {
        let source = """
        :::schema prelude
        type Greeting : value = { msg: str @default("hello") }
        :::
        """
        let result = try LiminalParser().parse(source)
        #expect(result.diagnostics.isEmpty)

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        let definition = try #require(schema.declarations.first?.definition)
        let modifier = try #require(definition.recordFields.first?.modifiers.first)
        #expect(modifier.modifierName == "default")
        #expect(modifier.argumentsText == #""hello""#)
    }

    @Test("Phase 3c.2 parser preserves rhsText source bytes through structuring")
    func phase3c2ParserPreservesRhsTextBytes() throws {
        let source = """
        :::schema prelude
        type Person : value = { name: str, age?: int }
        :::
        """
        let result = try LiminalParser().parse(source)
        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        // rhsText now derives from the structured definition's source text;
        // it must continue to match the literal RHS bytes the caller wrote.
        #expect(schema.declarations[0].rhsText == "{ name: str, age?: int }")
    }

    @Test("Phase 3c.2 parser recovers from a malformed schema RHS")
    func phase3c2ParserRecoversMalformedSchemaRHS() throws {
        let source = """
        :::schema prelude
        type Foo : value = { name: str
        type Bar : value = str
        :::
        """
        let result = try LiminalParser().parse(source)
        #expect(result.sourceText == source)
        // Foo's record never closed — diagnostic surfaces, but Bar still
        // parses cleanly. Recovery doesn't drop the next declaration.
        #expect(result.diagnostics.contains { $0.message.contains("missing `}`") })

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        let names = schema.declarations.map(\.qnameText)
        #expect(names.contains("Bar"))
    }

    @Test("Phase 3c.2 modifier argument scan is string-aware")
    func phase3c2ModifierArgumentScanIsStringAware() throws {
        let source = """
        :::schema prelude
        type Greeting : value = { msg: str @default(")") }
        type Note : value = { tag: str @deprecated("use foo()") }
        :::
        """
        let result = try LiminalParser().parse(source)
        #expect(result.diagnostics.isEmpty)
        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        let greetingMod = try #require(
            schema.declarations[0].definition?.recordFields.first?.modifiers.first
        )
        #expect(greetingMod.modifierName == "default")
        #expect(greetingMod.argumentsText == #"")""#)

        let noteMod = try #require(
            schema.declarations[1].definition?.recordFields.first?.modifiers.first
        )
        #expect(noteMod.modifierName == "deprecated")
        #expect(noteMod.argumentsText == #""use foo()""#)
    }

    @Test("Phase 3c.2 deferred TypeExpr forms leave definition unstructured")
    func phase3c2DeferredTypeExprFormsLeaveDefinitionUnstructured() throws {
        let source = """
        :::schema prelude
        type Tags : value = map<str>
        type Refs : value = ref<Person>
        type Pic : value = embed<Image>
        type Color : value = enum { red, green, blue }
        type Maybe : value = variant by kind { yes: { v: str }, no: {} }
        :::
        """
        let result = try LiminalParser().parse(source)
        #expect(result.sourceText == source)

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        for declaration in schema.declarations {
            // Each deferred form leaves an empty `.schemaTypeExpression`
            // wrapper — qnameText/isRecord/isList all false — so lowering
            // returns nil and the validator falls back to kind-only.
            let definition = try #require(declaration.definition)
            #expect(definition.qnameText == nil)
            #expect(definition.isRecord == false)
            #expect(definition.isList == false)
        }
    }

    @Test("Phase 3c.2 deferred form inside a record field doesn't shadow as named type")
    func phase3c2DeferredFormInsideRecordFieldDoesNotShadow() throws {
        // `tags: map<str>` previously degraded to `.named("map")`; the
        // outer record now structures cleanly while the field's inner
        // definition is unstructured.
        let source = """
        :::schema prelude
        type Item : value = { name: str, tags: map<str> }
        :::
        """
        let result = try LiminalParser().parse(source)

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        let definition = try #require(schema.declarations.first?.definition)
        #expect(definition.isRecord)
        let fields = definition.recordFields
        #expect(fields.map(\.fieldNameText) == ["name", "tags"])

        let nameType = try #require(fields[0].valueType)
        #expect(nameType.qnameText == "str")

        let tagsType = try #require(fields[1].valueType)
        // The tags field's value type is the deferred form — no qname,
        // not a record, not a list.
        #expect(tagsType.qnameText == nil)
        #expect(tagsType.isRecord == false)
        #expect(tagsType.isList == false)
    }

    @Test("Phase 3c.2 rhsText preserves trailing modifier salvage bytes")
    func phase3c2RhsTextPreservesTrailingSalvageBytes() throws {
        let source = """
        :::schema prelude
        type A : value = str @deprecated("old")
        :::
        """
        let result = try LiminalParser().parse(source)

        guard case .schemaBlock(let schema) = result.rootSyntax.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        // rhsText must include the trailing salvage bytes; previously
        // returned only `str` because the structured wrapper stopped at
        // the TypeExpr.
        #expect(schema.declarations[0].rhsText == #"str @deprecated("old")"#)
    }

    @Test("Phase 3c.1 parser keeps slice 7 expressionText contract")
    func phase3c1ParserPreservesSlice7ExpressionTextContract() throws {
        // Re-runs the slice 7 wikilink+interpolation source verbatim and
        // confirms `interpolation.expressionText` still returns the body
        // text the slice 7 test pinned (`"person.bio"`).
        let source = """
        :::template PersonCard(person: Person) -> blocks
        :::if{test: person.bio}
        Bio ${person.bio} [[Target]]
        :::
        :::
        """
        let result = try LiminalParser().parse(source)
        let interpolation = try #require(firstInterpolation(in: result.rootSyntax))
        #expect(interpolation.expressionText == "person.bio")
    }

    @Test("Slice 7 parser recovers incomplete language-level syntax")
    func slice7ParserRecoversIncompleteLanguageLevelSyntax() throws {
        let directiveResult = try LiminalParser().parse("::use\n")
        #expect(directiveResult.sourceText == "::use\n")
        #expect(directiveResult.diagnostics.map(\.message) == [
            "missing use directive body"
        ])

        let schemaSource = ":::schema prelude\nbody\n"
        let schemaResult = try LiminalParser().parse(schemaSource)
        #expect(schemaResult.sourceText == schemaSource)
        #expect(schemaResult.diagnostics.map(\.message) == [
            "missing closing schema fence"
        ])

        let templateSource = ":::template Card() -> blocks\n${person.name\n"
        let templateResult = try LiminalParser().parse(templateSource)
        #expect(templateResult.sourceText == templateSource)
        #expect(templateResult.diagnostics.map(\.message).contains("missing closing interpolation delimiter"))
        #expect(templateResult.diagnostics.map(\.message).contains("missing closing template fence"))
    }

    @Test("Slice 7 external references preserve target text without recovery")
    func slice7ExternalReferencesPreserveTargetTextWithoutRecovery() throws {
        let source = "@Refs{local: &ada, qualified: &people.ada, external: &<./people.lim#ada>}\n"
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)

        guard case .valueDeclaration(let declaration) = root.documentItems.first,
              let fields = declaration.constructor?.fields?.fields
        else {
            Issue.record("expected value declaration with reference fields")
            return
        }

        let referenceTexts = fields.compactMap { field -> String? in
            guard case .reference(let reference) = field.value?.payload else {
                return nil
            }
            return reference.externalTargetText ?? reference.qnameText
        }
        #expect(referenceTexts == ["ada", "people.ada", "./people.lim#ada"])
    }

    @Test("typed block fences support same-colon-count nesting")
    func typedBlockFencesSupportSameColonCountNesting() throws {
        let source = """
        :::Outer
        :::Inner
        body
        :::
        :::
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 1)

        guard case .typedBlock(let outer) = root.documentItems.first else {
            Issue.record("expected outer typed block")
            return
        }
        #expect(outer.typeName == "Outer")
        #expect(outer.documentItems.count == 1)

        guard case .typedBlock(let inner) = outer.documentItems.first else {
            Issue.record("expected nested typed block")
            return
        }
        #expect(inner.typeName == "Inner")

        guard case .paragraph(let paragraph) = inner.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes
        else {
            Issue.record("expected nested body paragraph")
            return
        }
        #expect(inlineNodes.isEmpty)
        #expect(paragraph.sourceText == "body\n")
    }

    @Test("schema block close detection skips nested colon-fence-like content")
    func schemaBlockCloseDetectionSkipsNestedColonFenceLikeContent() throws {
        let source = """
        :::schema prelude
        :::Callout
        body
        :::
        :::
        """
        let result = try LiminalParser().parse(source)
        let root = result.rootSyntax

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)
        #expect(root.documentItems.count == 1)

        guard case .schemaBlock(let schema) = root.documentItems.first else {
            Issue.record("expected schema block")
            return
        }
        #expect(schema.nameText == "prelude")
        // The schema's close fence is the OUTER `:::`; the inner `:::Callout`
        // colon-fence content stays inside the schema's raw body text.
        #expect(schema.rawText.contains(":::Callout"))
        #expect(schema.rawText.contains("body"))
    }

    @Test("inline content plaintext projection follows CST inline semantics")
    func inlineContentPlainTextProjectionFollowsCSTInlineSemantics() throws {
        #expect(try paragraphPlainText("Plain text\n") == "Plain text")
        #expect(try paragraphPlainText("Use `code`\n") == "Use code")
        #expect(try paragraphPlainText("a\nb\\\nc\n") == "a b\nc")
        #expect(try paragraphPlainText("[[Target|Alias]] and [[Solo]]\n") == "Alias and Solo")
        #expect(try paragraphPlainText("![Alt](image.png)\n") == "Alt")
        #expect(try paragraphPlainText("See @Badge[Label]\n") == "See Label")
        #expect(try paragraphPlainText("[[Target|See `code`]]\n") == "See code")
        #expect(try paragraphPlainText(#"~~gone~~ ==marked== ^[note] \(x\) %%hidden%% $x$"#) == "gone marked note x  $x$")
    }

    @Test("escaped punctuation is represented by explicit CST nodes")
    func escapedPunctuationIsRepresentedByExplicitCSTNodes() throws {
        let source = #"Escaped \*literal\* and \[bracket\]."#
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .paragraph(let paragraph) = root.documentItems.first,
              let inlineNodes = paragraph.inlineContent?.inlineNodes
        else {
            Issue.record("expected paragraph")
            return
        }

        let escapedText = inlineNodes.compactMap { inline -> String? in
            guard case .escapedPunctuation(let punctuation) = inline else {
                return nil
            }
            return punctuation.escapedText
        }
        #expect(escapedText == ["*", "*", "[", "]"])
    }

    @Test("Slice 2 parser emits generic typed and value document items losslessly")
    func slice2ParserEmitsGenericTypedAndValueDocumentItemsLosslessly() throws {
        let source = """
        @Person#ada{name: "Ada", born: 1815-12-10}[Ada]

        :::Callout#warning{kind: warning}
        Body [[Note]]
        :::

        !{Person}[Ada](#ada)

        :::MathBlock
        E = mc^2
        :::
        :::HtmlBlock
        <div>raw</div>
        :::
        """
        let result = try LiminalParser().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.sourceText == source)

        result.tree.withRoot { root in
            var childKinds: [LiminalKind] = []
            root.forEachChild { child in
                childKinds.append(child.kind)
            }

            #expect(childKinds == [
                .valueDeclaration,
                .blankLine,
                .typedBlock,
                .blankLine,
                .structuredEmbedBlock,
                .blankLine,
                .mathBlock,
                .htmlBlock
            ])
        }
    }

    @Test("typed root overlay exposes Slice 2 constructs")
    func typedRootOverlayExposesSlice2Constructs() throws {
        let source = """
        @Person#ada{name: "Ada"}[Ada]
        :::Callout#warning{kind: warning}
        Body
        :::
        !{Person}[Ada](#ada)
        """
        let root = try LiminalParser().parse(source).rootSyntax

        guard case .valueDeclaration(let declaration) = root.documentItems[0],
              let constructor = declaration.constructor
        else {
            Issue.record("expected value declaration")
            return
        }
        #expect(constructor.typeName == "Person")
        #expect(constructor.idText == "ada")
        #expect(constructor.fields?.fields.map(\.name) == ["name"])
        #expect(constructor.inlineContent?.sourceText == "Ada")

        guard case .typedBlock(let block) = root.documentItems[1] else {
            Issue.record("expected typed block")
            return
        }
        #expect(block.typeName == "Callout")
        #expect(block.idText == "warning")
        #expect(block.fields?.fields.map(\.name) == ["kind"])
        #expect(block.documentItems.count == 1)

        guard case .structuredEmbedBlock(let embed) = root.documentItems[2] else {
            Issue.record("expected structured embed block")
            return
        }
        #expect(embed.expectedType == "Person")
        #expect(embed.fallbackContent?.sourceText == "Ada")
        #expect(embed.targetText == "#ada")
    }

    @Test("typed dispatch points accept emitted Slice 1 nodes and reject root")
    func typedDispatchPointsAcceptEmittedSlice1NodesAndRejectRoot() throws {
        let result = try LiminalParser().parse("# Heading\n\nBody with [link](target)\n")
        let rootHandle = result.tree.rootHandle()

        #expect(DocumentItemSyntax(rootHandle) == nil)
        #expect(BlockSyntax(rootHandle) == nil)
        #expect(InlineSyntax(rootHandle) == nil)
        #expect(ValueSyntax(rootHandle) == nil)

        guard case .atxHeading(let heading) = result.rootSyntax.documentItems[0] else {
            Issue.record("expected heading")
            return
        }
        #expect(DocumentItemSyntax(heading.syntax) != nil)
        #expect(BlockSyntax(heading.syntax) != nil)
        #expect(heading.level == 1)

        guard case .paragraph(let paragraph) = result.rootSyntax.documentItems[2],
              let linkNode = paragraph.inlineContent?.inlineNodes.first
        else {
            Issue.record("expected paragraph link")
            return
        }
        #expect(InlineSyntax(linkNode.syntax) != nil)
    }

    @Test("Slice 1 parser emits recoverable diagnostics for incomplete inline constructs")
    func slice1ParserEmitsRecoverableDiagnosticsForIncompleteInlineConstructs() throws {
        let source = "Broken [[wikilink\nand `code\n"
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.severity) == [.error, .error])
        #expect(result.diagnostics.map(\.message) == [
            "missing closing wikilink",
            "missing closing code span delimiter"
        ])
    }

    @Test("Slice 2 parser recovers inside incomplete typed value syntax")
    func slice2ParserRecoversInsideIncompleteTypedValueSyntax() throws {
        let source = "@Person{name \"Ada\""
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.severity).allSatisfy { $0 == .error })
        #expect(result.diagnostics.map(\.message).contains("missing field colon"))
        #expect(result.diagnostics.map(\.message).contains("missing closing fields delimiter"))
    }

    @Test("structured syntax errors use error text instead of raw payload text")
    func structuredSyntaxErrorsUseErrorTextInsteadOfRawPayloadText() throws {
        let source = "@Person{=bad}"
        let result = try LiminalParser().parse(source)

        #expect(result.sourceText == source)
        #expect(result.diagnostics.map(\.message).contains("expected field"))
        #expect(result.rootSyntax.firstDescendantToken(kind: .errorText)?.text == "=bad")
        #expect(result.rootSyntax.firstDescendantToken(kind: .rawPayloadText) == nil)
    }

    @Test("parse session exposes the most recently parsed tree")
    func parseSessionKeepsCurrentTreeAcrossParses() throws {
        let session = LiminalParseSession()

        let first = try session.parse("one")
        let second = try session.parse("two")

        #expect(first.sourceText == "one")
        #expect(second.sourceText == "two")
        #expect(session.currentTree?.treeID == second.tree.treeID)
    }
}

private func string(for text: StaticString?) -> String? {
    text?.withUTF8Buffer { bytes in
        String(decoding: bytes, as: UTF8.self)
    }
}

private func paragraphPlainText(_ source: String) throws -> String {
    let root = try LiminalParser().parse(source).rootSyntax
    guard case .paragraph(let paragraph) = root.documentItems.first,
          let inlineContent = paragraph.inlineContent
    else {
        Issue.record("expected paragraph")
        return ""
    }
    return inlineContent.plainText
}

private func sourceRange(of needle: String, in source: String) throws -> TextRange {
    let range = try #require(source.range(of: needle))
    let start = source[..<range.lowerBound].utf8.count
    return TextRange(
        start: TextSize(UInt32(start)),
        length: TextSize(UInt32(needle.utf8.count))
    )
}

private func firstInterpolation(in root: RootSyntax) -> InterpolationSyntax? {
    for item in root.documentItems {
        if let found = findInterpolation(in: item) {
            return found
        }
    }
    return nil
}

private func findInterpolation(in item: DocumentItemSyntax) -> InterpolationSyntax? {
    switch item {
    case .paragraph(let paragraph):
        return paragraph.inlineContent.flatMap(findInterpolation(in:))
    case .atxHeading(let heading):
        return heading.inlineContent.flatMap(findInterpolation(in:))
    case .templateBlock(let template):
        for nested in template.documentItems {
            if let found = findInterpolation(in: nested) { return found }
        }
        return nil
    case .typedBlock(let block):
        for nested in block.documentItems {
            if let found = findInterpolation(in: nested) { return found }
        }
        return nil
    default:
        return nil
    }
}

private func findInterpolation(in inlineContent: InlineContentSyntax) -> InterpolationSyntax? {
    for node in inlineContent.inlineNodes {
        if case .interpolation(let interpolation) = node {
            return interpolation
        }
    }
    return nil
}

struct ParseExpectation: CustomTestStringConvertible, Sendable {
    var description: String
    var source: String
    var rootChildKinds: [LiminalKind]

    var testDescription: String {
        description
    }
}
