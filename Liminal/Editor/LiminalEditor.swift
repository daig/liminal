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
    public private(set) var source: CambiumSource
    public private(set) var parseResult: LiminalParseResult?

    private let parseSession: LiminalParseSession

    public init(source: CambiumSource = CambiumSource(), parseSession: LiminalParseSession = LiminalParseSession()) {
        self.source = source
        self.parseSession = parseSession
    }

    @discardableResult
    public func replaceSource(_ source: CambiumSource, edits: [TextEdit] = []) throws -> LiminalParseResult {
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

    public var lastReuseSummary: ReuseSummary {
        parseSession.lastReuseSummary
    }

    /// The tree currently held by the parse session. Populated after the
    /// first parse and updated by every textual or structural edit. Use
    /// this when `parseResult` is nil (e.g., after a structural replace,
    /// which doesn't re-run the parser) but you still need the current
    /// CST root.
    public var currentTree: SharedSyntaxTree<LiminalLanguage>? {
        parseSession.currentTree
    }

    /// Apply textual edits to the current source and re-parse from scratch.
    ///
    /// Edits are expressed in **old-source** UTF-8 byte coordinates per
    /// Cambium's `TextEdit` contract and must be in descending start order
    /// and non-overlapping. Splicing runs through `CambiumSource`'s
    /// persistent rope (`applying(_:)`), so the per-edit cost is
    /// O(log N + edit_size) rather than the O(N) full-buffer rewrite the
    /// previous String-backed implementation performed. Throws
    /// `CambiumSourceEditError.unorderedOrOverlapping` on bad ordering /
    /// overlap and `CambiumSourceEditError.editOutOfRange` when a range
    /// exceeds the source's byte length.
    ///
    /// The `edits:` parameter on the underlying `LiminalParseSession.parse`
    /// remains inert today; this method drives a full re-parse on the new
    /// source. Phase 6 will wire incremental parsing.
    @discardableResult
    public func applyTextEdits(_ edits: [TextEdit]) throws -> LiminalParseResult {
        let newSource = try source.applying(edits)
        self.source = newSource
        let result = try parseSession.parse(newSource, edits: edits)
        self.parseResult = result
        return result
    }

    /// Apply textual edits to the live source without reparsing.
    /// Used by undo / redo, where the target tree was captured at the
    /// transaction boundary and will be installed directly.
    public func applySourceEditsWithoutParsing(_ edits: [TextEdit]) throws {
        source = try source.applying(edits)
        parseResult = nil
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

    /// Install a snapshot tree wholesale, bypassing the parser. Used
    /// by undo / redo: the caller already has the target tree (a
    /// `SharedSyntaxTree` captured at a prior transaction boundary),
    /// so a reparse is wasteful and would also break anchor identity
    /// (we'd produce a structurally-equivalent but pointer-distinct
    /// tree).
    ///
    /// Side effects mirror `replaceSubtree`'s tree install path: the
    /// parse session points at the target tree and `parseResult` is
    /// cleared since its diagnostics describe a different tree.
    public func installSnapshot(tree: SharedSyntaxTree<LiminalLanguage>) {
        parseSession.installTree(tree)
        self.parseResult = nil
    }

    private func finalizeReplace(_ output: StructuralReplaceOutput) -> LiminalEditResult {
        let newSourceString = output.tree.withRoot { $0.makeString() }
        self.source = CambiumSource(newSourceString)
        self.parseResult = nil
        return LiminalEditResult(
            tree: output.tree,
            sourceText: newSourceString,
            witness: output.witness
        )
    }
}
