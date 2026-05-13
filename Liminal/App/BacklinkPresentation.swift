import CambiumCore
import Foundation

/// Pure helpers for presenting `[ResolvedReference]` backlinks in
/// the inspector — derives a stable sort order and a display label
/// per source. Kept outside the SwiftUI view so the rules are unit-
/// testable without hosting AppKit.
enum BacklinkPresentation {
    /// Sort backlinks by (source note relative path,
    /// source-range start). Both keys are stable: the relative path
    /// gives users alphabetical-by-folder ordering; ties within one
    /// note are broken by document order so multiple references in
    /// the same source appear top-to-bottom as they do in that note.
    static func sorted(
        _ refs: [ResolvedReference],
        notes: [URL: LiminalNote]
    ) -> [ResolvedReference] {
        refs.sorted { a, b in
            let aPath = sortKey(for: a, notes: notes)
            let bPath = sortKey(for: b, notes: notes)
            if aPath != bPath {
                return aPath.localizedCaseInsensitiveCompare(bPath) == .orderedAscending
            }
            return a.sourceRange.start.rawValue < b.sourceRange.start.rawValue
        }
    }

    /// Display label for a backlink's source note: vault-relative
    /// path with `.lim` stripped. Falls back to the URL's last path
    /// component if the note isn't in `notes` (e.g., deleted from
    /// disk while still backlinked from a stale entry — defensive).
    static func sourceDisplayLabel(
        for reference: ResolvedReference,
        notes: [URL: LiminalNote]
    ) -> String {
        if let path = notes[reference.sourceNoteID]?.relativePath {
            return (path as NSString).deletingPathExtension
        }
        return (reference.sourceNoteID.lastPathComponent as NSString)
            .deletingPathExtension
    }

    private static func sortKey(
        for reference: ResolvedReference,
        notes: [URL: LiminalNote]
    ) -> String {
        notes[reference.sourceNoteID]?.relativePath
            ?? reference.sourceNoteID.lastPathComponent
    }
}
