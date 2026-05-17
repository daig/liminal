import Testing
@testable import Liminal

@Suite("CommandLineCompletion — fuzzy matcher")
struct CommandLineCompletionTests {

    // MARK: - Subsequence basics

    @Test("empty query matches everything with score 0 and empty indices")
    func emptyQueryReturnsAll() {
        let result = FuzzyMatcher.match(query: "", against: "AnythingHere")
        #expect(result?.score == 0)
        #expect(result?.matchedIndices == [])
    }

    @Test("query that isn't a subsequence returns nil")
    func nonSubsequenceReturnsNil() {
        #expect(FuzzyMatcher.match(query: "zzz", against: "CSTParent") == nil)
        #expect(FuzzyMatcher.match(query: "Find", against: "CSTParent") == nil)
    }

    @Test("subsequence match returns matched indices in order")
    func subsequenceReturnsIndices() {
        let result = FuzzyMatcher.match(query: "cst", against: "CSTParent")
        #expect(result?.matchedIndices == [0, 1, 2])
    }

    @Test("case-insensitive matching")
    func caseInsensitive() {
        let lower = FuzzyMatcher.match(query: "cst", against: "CSTParent")
        let upper = FuzzyMatcher.match(query: "CST", against: "CSTParent")
        #expect(lower?.matchedIndices == upper?.matchedIndices)
        #expect(lower?.score == upper?.score)
    }

    // MARK: - Scoring

    @Test("prefix match scores higher than mid-string match")
    func prefixBeatsMidString() {
        // Compare two candidates against the same query — prefix wins.
        let prefix = FuzzyMatcher.match(query: "c", against: "Code")
        let mid = FuzzyMatcher.match(query: "c", against: "BlockCode")
        let prefixScore = try! #require(prefix?.score)
        let midScore = try! #require(mid?.score)
        #expect(prefixScore > midScore)
    }

    @Test("CamelCase word-boundary match scores higher than mid-word")
    func camelCaseBoundaryBoost() {
        // `fc` against `firstChild`: f at 0 (prefix +10), C at 5 (CamelCase
        // boundary +6).
        // `fc` against `flacc`: f at 0 (prefix +10), c at 3 (mid-word, no
        // boundary bonus).
        let camel = FuzzyMatcher.match(query: "fc", against: "firstChild")
        let mid = FuzzyMatcher.match(query: "fc", against: "flacc")
        let camelScore = try! #require(camel?.score)
        let midScore = try! #require(mid?.score)
        #expect(camelScore > midScore,
                "CamelCase boundary should beat mid-word; camel=\(camelScore), mid=\(midScore)")
    }

    @Test("consecutive matches score higher than spread-out matches")
    func consecutiveBoost() {
        // `ab` against `abcdef`: a at 0, b at 1 — consecutive.
        // `ab` against `axxxxxb`: a at 0, b at 6 — spread out.
        let consecutive = FuzzyMatcher.match(query: "ab", against: "abcdef")
        let spread = FuzzyMatcher.match(query: "ab", against: "axxxxxb")
        let consecutiveScore = try! #require(consecutive?.score)
        let spreadScore = try! #require(spread?.score)
        #expect(consecutiveScore > spreadScore)
    }

    @Test("matched indices are returned in candidate-position order")
    func matchedIndicesOrdered() {
        let result = FuzzyMatcher.match(query: "stc", against: "StartCommand")
        // S at 0, t at 1, c at 5 (the capital C from "Command")
        #expect(result?.matchedIndices == [0, 1, 5])
    }

    // MARK: - Snowflakes

    @Test("query longer than candidate returns nil")
    func queryLongerThanCandidate() {
        #expect(FuzzyMatcher.match(query: "abcdef", against: "abc") == nil)
    }

    @Test("identical query and candidate gets all the bonuses")
    func identicalGetsBigScore() {
        let result = FuzzyMatcher.match(query: "abc", against: "abc")
        // a at 0 (prefix), b at 1 (consecutive), c at 2 (consecutive).
        let score = try! #require(result?.score)
        #expect(score >= 13, "expected ≥13 (1+10 + 1+2 + 1+2 = 17 baseline); got \(score)")
    }
}
