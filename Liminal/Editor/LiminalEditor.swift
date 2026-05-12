import CambiumBuilder
import CambiumCore
import CambiumIncremental

public struct LiminalEditResult: Sendable {
    public let tree: SharedSyntaxTree<LiminalLanguage>
    public let sourceText: String
    public let witness: ReplacementWitness<LiminalLanguage>

    public var rootSyntax: RootSyntax {
        RootSyntax(unchecked: tree.rootHandle())
    }

    public init(
        tree: SharedSyntaxTree<LiminalLanguage>,
        sourceText: String,
        witness: ReplacementWitness<LiminalLanguage>
    ) {
        self.tree = tree
        self.sourceText = sourceText
        self.witness = witness
    }
}

public final class LiminalEditorSession {
    public private(set) var source: String
    public private(set) var parseResult: LiminalParseResult?

    private let parseSession: LiminalParseSession

    public init(source: String = "", parseSession: LiminalParseSession = LiminalParseSession()) {
        self.source = source
        self.parseSession = parseSession
    }

    @discardableResult
    public func replaceSource(_ source: String, edits: [TextEdit] = []) throws -> LiminalParseResult {
        self.source = source
        let result = try parseSession.parse(source, edits: edits)
        self.parseResult = result
        return result
    }

    @discardableResult
    public func parse() throws -> LiminalParseResult {
        let result = try parseSession.parse(source)
        self.parseResult = result
        return result
    }

    public func lowerCurrentDocument() throws -> LiminalDocument {
        let result: LiminalParseResult
        if let parseResult {
            result = parseResult
        } else {
            result = try parse()
        }
        return LiminalLowerer().lower(result)
    }

    /// Apply textual edits to the current source and re-parse from scratch.
    ///
    /// Edits are expressed in **old-source** UTF-8 byte coordinates per
    /// Cambium's `TextEdit` contract. The implementation splices on a
    /// `[UInt8]` buffer (never `String.Index`) and applies edits in
    /// descending start order so each edit's range remains valid against
    /// the in-progress buffer. Throws `LiminalEditError.overlappingEdits`
    /// when any two edits intersect and `LiminalEditError.editOutOfRange`
    /// when a range exceeds the source's byte length.
    ///
    /// The `edits:` parameter on the underlying `LiminalParseSession.parse`
    /// remains inert today; this method drives a full re-parse on the new
    /// source. Phase 6 will wire incremental parsing.
    @discardableResult
    public func applyTextEdits(_ edits: [TextEdit]) throws -> LiminalParseResult {
        let newSource = try Self.applyingEdits(edits, to: source)
        self.source = newSource
        let result = try parseSession.parse(newSource, edits: edits)
        self.parseResult = result
        return result
    }

    /// Replace the subtree at `target` with `replacement`, returning the
    /// new tree, source, and replacement witness. The parser is NOT
    /// re-run, so `LiminalParseResult` is not the right return shape —
    /// any diagnostics from the previous parse are stale relative to the
    /// new tree. Callers that want fresh diagnostics should call `parse()`
    /// after.
    ///
    /// Side effects: updates `self.source` (via `tree.makeString()`) and
    /// clears `self.parseResult` (since its diagnostics are stale). Any
    /// `SyntaxNodeHandle` captured before this call is invalidated by the
    /// new `treeID`.
    @discardableResult
    public func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: ResolvedGreenNode<LiminalLanguage>
    ) throws -> LiminalEditResult {
        let output = try parseSession.replaceSubtree(target, with: replacement)
        return finalizeReplace(output)
    }

    @discardableResult
    public func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: GreenTreeSnapshot<LiminalLanguage>
    ) throws -> LiminalEditResult {
        let output = try parseSession.replaceSubtree(target, with: replacement)
        return finalizeReplace(output)
    }

    @discardableResult
    public func replaceSubtree(
        _ target: SyntaxNodeHandle<LiminalLanguage>,
        with replacement: borrowing GreenBuildResult<LiminalLanguage>
    ) throws -> LiminalEditResult {
        let output = try parseSession.replaceSubtree(target, with: replacement)
        return finalizeReplace(output)
    }

    private func finalizeReplace(_ output: StructuralReplaceOutput) -> LiminalEditResult {
        let newSource = output.tree.withRoot { $0.makeString() }
        self.source = newSource
        self.parseResult = nil
        return LiminalEditResult(
            tree: output.tree,
            sourceText: newSource,
            witness: output.witness
        )
    }

    static func applyingEdits(_ edits: [TextEdit], to source: String) throws -> String {
        if edits.isEmpty {
            return source
        }
        let sorted = edits.sorted { lhs, rhs in
            lhs.range.start.rawValue > rhs.range.start.rawValue
        }
        for i in 0..<(sorted.count - 1) {
            let later = sorted[i]
            let earlier = sorted[i + 1]
            if earlier.range.end.rawValue > later.range.start.rawValue {
                throw LiminalEditError.overlappingEdits
            }
        }
        var bytes = Array(source.utf8)
        let sourceLen = bytes.count
        for edit in sorted {
            let start = Int(edit.range.start.rawValue)
            let end = Int(edit.range.end.rawValue)
            if end > sourceLen || start > end {
                throw LiminalEditError.editOutOfRange(
                    start: edit.range.start.rawValue,
                    end: edit.range.end.rawValue,
                    sourceByteLength: sourceLen
                )
            }
            bytes.replaceSubrange(start..<end, with: edit.replacementUTF8)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
