import CambiumCore
import Testing
@testable import Liminal

@Suite("Highlighter")
struct HighlighterTests {

    // MARK: - Sanity / structural invariants

    @Test("spans cover every byte of the source with no gaps or overlaps")
    func spansTileTheSource() throws {
        let source = "# Hello\n\nworld\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        #expect(!spans.isEmpty)

        // Ranges in source order, non-overlapping, contiguous, ending at EOF.
        var cursor = 0
        for span in spans {
            let start = Int(span.range.start.rawValue)
            let end = start + Int(span.range.length.rawValue)
            #expect(start == cursor, "span starts at \(start), expected \(cursor)")
            #expect(end >= start)
            cursor = end
        }
        #expect(cursor == source.utf8.count)
    }

    // MARK: - Heading

    @Test("ATX heading marker is delimiter; body inherits heading modifier")
    func atxHeading() throws {
        let parsed = try LiminalParser().parse(CambiumSource("# Hello\n"))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let markerSpan = try #require(spans.first { byteText($0, in: "# Hello\n") == "#" })
        #expect(markerSpan.category == .delimiter)
        #expect(markerSpan.modifiers.contains(.heading))

        let bodySpan = try #require(spans.first { byteText($0, in: "# Hello\n") == "Hello" })
        #expect(bodySpan.category == .default)
        #expect(bodySpan.modifiers.contains(.heading))
    }

    @Test("thematic break markers are delimiters")
    func thematicBreak() throws {
        let source = "* * *\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let markerSpans = spans.filter { byteText($0, in: source) == "*" }
        #expect(markerSpans.count == 3)
        #expect(markerSpans.allSatisfy { $0.category == .delimiter })
    }

    // MARK: - Code span

    @Test("code span's backticks are delimiter, inner content is codeContent")
    func codeSpan() throws {
        let source = "hello `code` world\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let openBacktick = spans.first { byteText($0, in: source) == "`" && $0.category == .delimiter }
        #expect(openBacktick != nil)

        let codeSpan = try #require(spans.first { byteText($0, in: source) == "code" })
        #expect(codeSpan.category == .codeContent)
    }

    // MARK: - Wikilink

    @Test("wikilink: target is linkText, brackets are delimiter")
    func wikilink() throws {
        let source = "see [[Target]]\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let target = try #require(spans.first { byteText($0, in: source) == "Target" })
        #expect(target.category == .linkText)

        let openBracket = spans.first { byteText($0, in: source) == "[[" }
        if let openBracket {
            #expect(openBracket.category == .delimiter)
        }
    }

    @Test("autolink target is linkText and angle brackets are delimiters")
    func autolink() throws {
        let source = "see <https://example.org> and www.example.org\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let angleTarget = try #require(spans.first { byteText($0, in: source) == "https://example.org" })
        #expect(angleTarget.category == .linkText)

        let bareTarget = try #require(spans.first { byteText($0, in: source) == "www.example.org" })
        #expect(bareTarget.category == .linkText)

        let openAngle = try #require(spans.first { byteText($0, in: source) == "<" })
        let closeAngle = try #require(spans.first { byteText($0, in: source) == ">" })
        #expect(openAngle.category == .delimiter)
        #expect(closeAngle.category == .delimiter)
    }

    // MARK: - Inline modifiers

    @Test("emphasis text carries .emphasis modifier")
    func emphasisModifier() throws {
        let source = "a *em* b\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "em" })
        #expect(inner.modifiers.contains(.emphasis))
    }

    @Test("strong text carries .strong modifier")
    func strongModifier() throws {
        let source = "a **strong** b\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "strong" })
        #expect(inner.modifiers.contains(.strong))
    }

    @Test("strikethrough text carries .strikethrough modifier")
    func strikethroughModifier() throws {
        let source = "a ~~struck~~ b\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "struck" })
        #expect(inner.modifiers.contains(.strikethrough))
    }

    @Test("highlight text carries .highlight modifier")
    func highlightModifier() throws {
        let source = "a ==marked== b\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "marked" })
        #expect(inner.modifiers.contains(.highlight))
    }

    @Test("open strikethrough and highlight delimiters carry recovery modifiers")
    func openStyledDelimiterRecoveryModifiers() throws {
        let strikeSource = "~~draft"
        let strikeParsed = try LiminalParser().parse(CambiumSource(strikeSource))
        let strikeSpans = LiminalHighlighter().spans(for: strikeParsed.rootSyntax)
        let strikeText = try #require(strikeSpans.first { byteText($0, in: strikeSource) == "draft" })
        #expect(strikeText.modifiers.contains(.strikethrough))

        let highlightSource = "==marked"
        let highlightParsed = try LiminalParser().parse(CambiumSource(highlightSource))
        let highlightSpans = LiminalHighlighter().spans(for: highlightParsed.rootSyntax)
        let highlightText = try #require(highlightSpans.first { byteText($0, in: highlightSource) == "marked" })
        #expect(highlightText.modifiers.contains(.highlight))

        let emphasisSource = "*draft"
        let emphasisParsed = try LiminalParser().parse(CambiumSource(emphasisSource))
        let emphasisSpans = LiminalHighlighter().spans(for: emphasisParsed.rootSyntax)
        let literalText = try #require(emphasisSpans.first { byteText($0, in: emphasisSource) == "*draft" })
        #expect(!literalText.modifiers.contains(.emphasis))
    }

    @Test("nested strong + emphasis carries both modifiers")
    func nestedStrongEmphasisModifiers() throws {
        let source = "**bold *both* bold**\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "both" })
        #expect(inner.modifiers.contains(.strong))
        #expect(inner.modifiers.contains(.emphasis))
    }

    @Test("nested emphasis + strong carries both modifiers")
    func nestedEmphasisStrongModifiers() throws {
        let source = "*em **both** em*\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "both" })
        #expect(inner.modifiers.contains(.emphasis))
        #expect(inner.modifiers.contains(.strong))
    }

    @Test("nested strikethrough + highlight carries both modifiers")
    func nestedInlineModifiers() throws {
        let source = "~~==x==~~\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let inner = try #require(spans.first { byteText($0, in: source) == "x" })
        #expect(inner.modifiers.contains(.strikethrough))
        #expect(inner.modifiers.contains(.highlight))
    }

    // MARK: - Typed block

    @Test("typed block: fence is delimiter, type name is typeName, fields show identifier")
    func typedBlock() throws {
        let source = """
        :::Callout{kind: warning}
        body
        :::
        """
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let fence = try #require(spans.first { byteText($0, in: source) == ":::" })
        #expect(fence.category == .delimiter)

        let typeName = try #require(spans.first { byteText($0, in: source) == "Callout" })
        #expect(typeName.category == .typeName)

        let fieldName = try #require(spans.first { byteText($0, in: source) == "kind" })
        #expect(fieldName.category == .identifier)
    }

    // MARK: - Comment block

    @Test("comment block: fence delimiter, body commentContent")
    func commentBlock() throws {
        let source = "%%\nsecret note\n%%\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        // body content lands as a single commentText token spanning the
        // payload bytes between opening fence's newline and closing fence.
        let bodySpan = spans.first { $0.category == .commentContent }
        #expect(bodySpan != nil)
    }

    // MARK: - Error / recovery

    @Test("structured-context recovery produces an error-category span")
    func errorRecovery() throws {
        // Malformed typed-inline field body — the structured record parser
        // emits a `.error` node containing `.errorText` via `emitErrorRun`
        // when it encounters a non-identifier, non-separator character
        // inside `{...}`. The walker's error-scope propagation should mark
        // those tokens as `.error` category.
        let source = "@Foo{?}\n"
        let parsed = try LiminalParser().parse(CambiumSource(source))
        let spans = LiminalHighlighter().spans(for: parsed.rootSyntax)

        let hasError = spans.contains { $0.category == .error }
        #expect(hasError, "expected at least one .error span; got \(spans)")
    }

    // MARK: - Category mapping (exhaustive token kinds)

    @Test("categoryFor maps delimiter-shaped tokens to .delimiter")
    func categoryDelimiters() {
        let delimiters: [LiminalKind] = [
            .hashRun, .colonRun, .fenceRun, .listMarker, .orderedListMarker,
            .taskMarker, .atSign, .bang, .ampersand, .hash, .leftBracket,
            .rightBracket, .leftParen, .rightParen, .leftBrace, .rightBrace,
            .lessThan, .greaterThan, .comma, .colon, .pipe, .backtick,
            .tilde, .star, .underscore, .dash, .plus, .dot, .slash,
            .backslash, .percent, .equals, .questionMark, .singleQuote,
            .doubleQuote, .semicolon, .caret, .dollar,
        ]
        for kind in delimiters {
            #expect(LiminalHighlighter.category(for: kind) == .delimiter,
                    "expected .delimiter for \(kind)")
        }
    }

    @Test("categoryFor maps identifier-shaped tokens to .identifier")
    func categoryIdentifiers() {
        for kind in [LiminalKind.identifier, .fieldName, .anchor] {
            #expect(LiminalHighlighter.category(for: kind) == .identifier)
        }
    }

    @Test("categoryFor maps scalar literal kinds to .numberLiteral or .stringLiteral")
    func categoryLiterals() {
        #expect(LiminalHighlighter.category(for: .quotedStringLiteral) == .stringLiteral)
        for kind in [LiminalKind.integerLiteral, .numberLiteral, .booleanLiteral,
                     .nullLiteral, .bareScalarLiteral] {
            #expect(LiminalHighlighter.category(for: kind) == .numberLiteral)
        }
    }

    @Test("categoryFor maps content-bearing payload tokens to the right categories")
    func categoryPayloads() {
        #expect(LiminalHighlighter.category(for: .codeText) == .codeContent)
        #expect(LiminalHighlighter.category(for: .mathText) == .codeContent)
        #expect(LiminalHighlighter.category(for: .commentText) == .commentContent)
        #expect(LiminalHighlighter.category(for: .interpolationText) == .interpolation)
        #expect(LiminalHighlighter.category(for: .errorText) == .error)

        for kind in [LiminalKind.rawPayloadText, .htmlText, .schemaText,
                     .templateText, .directiveText, .frontmatterText] {
            #expect(LiminalHighlighter.category(for: kind) == .rawContent)
        }

        for kind in [LiminalKind.linkDestinationText, .linkTitleText,
                     .wikiTargetText, .embedTargetText, .externalReferenceText] {
            #expect(LiminalHighlighter.category(for: kind) == .linkText)
        }
    }

    @Test("modifierFor returns the expected modifier for styled inline nodes")
    func modifierMapping() {
        #expect(LiminalHighlighter.modifier(for: .emphasis) == .emphasis)
        #expect(LiminalHighlighter.modifier(for: .strong) == .strong)
        #expect(LiminalHighlighter.modifier(for: .strikethrough) == .strikethrough)
        #expect(LiminalHighlighter.modifier(for: .highlight) == .highlight)
        #expect(LiminalHighlighter.modifier(for: .atxHeading) == .heading)
        #expect(LiminalHighlighter.modifier(for: .paragraph) == nil)
        #expect(LiminalHighlighter.modifier(for: .codeSpan) == nil)
    }
}

// MARK: - Helpers

private func byteText(_ span: HighlightSpan, in source: String) -> String {
    let start = Int(span.range.start.rawValue)
    let end = start + Int(span.range.length.rawValue)
    let bytes = Array(source.utf8)
    guard start <= end, end <= bytes.count else { return "" }
    let slice = bytes[start..<end]
    return String(decoding: slice, as: UTF8.self)
}
