import Foundation

/// Which level of `:`-mode input the completion popup is currently
/// targeting. The controller flips between stages based on how many
/// tokens have been typed and whether the command at the front takes
/// arguments.
public enum CompletionStage: Sendable, Equatable {
    /// Matching candidates against the registered command names.
    case commandName
    /// Matching candidates against an argument-option list. `label`
    /// describes what the user is filling in (e.g. `"kind"`).
    case arg(label: String)
}

/// One row in the command-line completion popup. Pure value type —
/// the popup view consumes a `[CompletionEntry]` and renders.
public struct CompletionEntry: Sendable, Equatable, Identifiable {
    /// What gets shown as the row's primary label (e.g. `":CSTParent"`
    /// or `"heading"`). Includes the leading `:` for command-name
    /// rows so the popup reads as a typed command line.
    public let display: String

    /// What gets inserted into the input buffer when the user accepts
    /// this entry. Excludes the leading `:` (e.g. `"CSTParent"`).
    public let acceptValue: String

    /// Short human-readable description, rendered next to the name.
    public let description: String

    /// Optional chord shortcut to surface (e.g. `"h"` for `:CSTParent`).
    /// `nil` when no chord is bound to the command.
    public let chordHint: String?

    /// Indices into `display` of the matched characters, for inline
    /// highlighting in the popup.
    public let matchedIndices: [Int]

    /// `true` if accepting this entry dispatches immediately. `false`
    /// for command-name entries whose command takes arguments —
    /// accepting them advances the input to the argument stage instead.
    public let isExecutable: Bool

    public var id: String { display }

    public init(
        display: String,
        acceptValue: String,
        description: String,
        chordHint: String?,
        matchedIndices: [Int],
        isExecutable: Bool
    ) {
        self.display = display
        self.acceptValue = acceptValue
        self.description = description
        self.chordHint = chordHint
        self.matchedIndices = matchedIndices
        self.isExecutable = isExecutable
    }
}

/// Output of a fuzzy match attempt. `score` orders candidates;
/// `matchedIndices` is a list of character positions in the candidate
/// where each query char was matched (used to drive UI highlighting).
public struct MatchResult: Sendable, Equatable {
    public let score: Int
    public let matchedIndices: [Int]

    public init(score: Int, matchedIndices: [Int]) {
        self.score = score
        self.matchedIndices = matchedIndices
    }
}

/// Greedy subsequence-based fuzzy matcher with positional bonuses.
/// Tuned for short query strings against CamelCase command names.
///
/// Scoring atoms (all positive favor stronger matches; negative penalty
/// is mild and only for non-consecutive matches):
///
/// - `+10` per char matched at position 0 of the candidate
/// - `+6`  per char matched immediately after a "word boundary"
///         (an uppercase letter when prev is lowercase, or any char
///         when prev is non-alphanumeric — `_`, `-`, etc.)
/// - `+2`  per consecutive match (i.e. previous matched char is one
///         position back in the candidate)
/// - `+1`  baseline per matched char
/// - `-1`  per char skipped between this match and the previous one
public enum FuzzyMatcher {
    /// Returns a `MatchResult` if `query` is a case-insensitive
    /// subsequence of `candidate`; `nil` otherwise. An empty `query`
    /// always matches with score 0 and empty `matchedIndices` (the
    /// caller is responsible for sorting equally-scored candidates).
    public static func match(query: String, against candidate: String) -> MatchResult? {
        guard !query.isEmpty else {
            return MatchResult(score: 0, matchedIndices: [])
        }

        let candidateChars = Array(candidate)
        let queryChars = Array(query.lowercased())
        let candidateLowerChars = Array(candidate.lowercased())

        var matchedIndices: [Int] = []
        var queryIdx = 0
        var candidateIdx = 0

        while queryIdx < queryChars.count && candidateIdx < candidateChars.count {
            if candidateLowerChars[candidateIdx] == queryChars[queryIdx] {
                matchedIndices.append(candidateIdx)
                queryIdx += 1
            }
            candidateIdx += 1
        }

        guard queryIdx == queryChars.count else { return nil }

        var score = 0
        var prevMatchIdx: Int? = nil
        for matchIdx in matchedIndices {
            score += 1
            if matchIdx == 0 {
                score += 10
            } else {
                let prevChar = candidateChars[matchIdx - 1]
                let thisChar = candidateChars[matchIdx]
                let prevIsAlphanumeric = prevChar.isLetter || prevChar.isNumber
                if !prevIsAlphanumeric {
                    score += 6
                } else if thisChar.isUppercase && !prevChar.isUppercase {
                    // CamelCase boundary: prev is a lowercase letter,
                    // this is uppercase. The classic `firstChild` → `fC`
                    // boost.
                    score += 6
                }
            }
            if let prev = prevMatchIdx {
                if matchIdx == prev + 1 {
                    score += 2
                } else {
                    score -= (matchIdx - prev - 1)
                }
            } else if matchIdx > 0 {
                // Penalize unmatched leading characters so a query
                // that matches earlier in the candidate ranks higher.
                // Without this, e.g. "find" against `CSTGlobalFind`
                // (where the F gets a CamelCase boundary bonus) can
                // outscore `CSTFind`. Penalizing skipped prefix balances
                // the CamelCase win and lets length tiebreaks favor
                // the shorter, more-direct candidate.
                score -= matchIdx
            }
            prevMatchIdx = matchIdx
        }

        return MatchResult(score: score, matchedIndices: matchedIndices)
    }
}
