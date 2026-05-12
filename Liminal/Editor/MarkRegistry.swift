import CambiumCore
import CambiumIncremental

/// Per-document store of vim-style marks (`m<a-z>` / `` `<a-z> ``)
/// backed by `CSTAnchor` values. Re-anchors all marks eagerly after
/// every tree-mutating edit so reads are O(1) (just a dict lookup +
/// path resolution against the current tree).
///
/// Value-typed and Sendable — owned as a `@Published` property on
/// `VimController` so SwiftUI views observing the controller pick up
/// mark changes automatically.
public struct MarkRegistry: Sendable, Equatable {
    public private(set) var marks: [Character: CSTAnchor] = [:]

    public init() {}

    public mutating func set(_ name: Character, anchor: CSTAnchor) {
        marks[name] = anchor
    }

    public func anchor(named name: Character) -> CSTAnchor? {
        marks[name]
    }

    public mutating func unset(_ name: Character) {
        marks.removeValue(forKey: name)
    }

    /// Re-anchor all marks after an edit. For each mark:
    /// 1. Resolve to a byte offset in the OLD tree.
    /// 2. Apply edit deltas (LSP-style position adjustment).
    /// 3. Build a fresh anchor at the new byte offset in the NEW tree.
    /// Marks whose path is fully lost in the old tree are dropped.
    public mutating func reanchor(
        oldRoot: RootSyntax,
        edits: [TextEdit],
        newRoot: RootSyntax
    ) {
        guard !marks.isEmpty else { return }
        var updated: [Character: CSTAnchor] = [:]
        for (name, anchor) in marks {
            if let newAnchor = Self.reanchorOne(
                anchor,
                oldRoot: oldRoot,
                edits: edits,
                newRoot: newRoot
            ) {
                updated[name] = newAnchor
            }
            // else: anchor.resolve returned .lost in old tree; drop.
        }
        marks = updated
    }

    // MARK: - Single-anchor re-resolution

    private static func reanchorOne(
        _ anchor: CSTAnchor,
        oldRoot: RootSyntax,
        edits: [TextEdit],
        newRoot: RootSyntax
    ) -> CSTAnchor? {
        let oldByteOffset: TextSize
        switch anchor.resolve(in: oldRoot) {
        case .strong(let off), .weak(let off), .recovered(let off):
            oldByteOffset = off
        case .lost:
            return nil
        }

        let newByteOffset = adjustOffset(oldByteOffset, for: edits)
        return CSTAnchor.atSourceOffset(newByteOffset, in: newRoot)
    }

    /// LSP-style position adjustment. Edits are old-source coordinates
    /// and (per `LiminalEditorSession.applyingEdits`) non-overlapping.
    /// Processing in ascending start order makes the cumulative shift
    /// trivial to compute.
    private static func adjustOffset(
        _ offset: TextSize,
        for edits: [TextEdit]
    ) -> TextSize {
        guard !edits.isEmpty else { return offset }
        let sorted = edits.sorted { $0.range.start.rawValue < $1.range.start.rawValue }
        var pos = Int(offset.rawValue)
        var accumulatedDelta = 0
        for edit in sorted {
            let editStart = Int(edit.range.start.rawValue)
            let editEnd = editStart + Int(edit.range.length.rawValue)
            let delta = edit.replacementUTF8.count - Int(edit.range.length.rawValue)

            if editEnd <= pos {
                accumulatedDelta += delta
            } else if editStart < pos {
                // Edit overlaps the position — snap to edit start in new
                // coordinates (using deltas from edits that came before).
                return TextSize(UInt32(max(0, editStart + accumulatedDelta)))
            } else {
                // Subsequent edits are entirely past the position.
                break
            }
        }
        return TextSize(UInt32(max(0, pos + accumulatedDelta)))
    }
}

public extension MarkRegistry {
    /// True if `name` is one of the per-document mark slots we accept
    /// for v1 (`a`-`z`). Used by the controller to validate the char
    /// argument that follows `m` or `` ` ``.
    static func isValidMarkName(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first,
              ch.unicodeScalars.count == 1
        else { return false }
        return (0x61...0x7A).contains(scalar.value) // a-z
    }
}
