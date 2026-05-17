import CambiumCore
import CambiumSelection

/// Per-document store of CST forest marks (`:CSTMark <letter>` /
/// `:CSTJumpToMark <letter>`) backed by Cambium's `LiminalForestAnchor`.
///
/// Unlike `MarkRegistry` (which stores byte-offset `CSTAnchor`s and
/// reanchors eagerly after every edit), forest anchors are
/// path+fingerprint based and resolve lazily against any tree version.
/// No edit-time reanchor hook is needed — resolution walks the parent
/// path in whatever tree is provided and grades the result via
/// `LiminalForestResolution` (`.strong` / `.weak` / `.recovered` /
/// `.lost`).
///
/// Value-typed and `Sendable` — owned as a `@Published` property on
/// `VimController` so SwiftUI views observing the controller pick up
/// changes automatically.
public struct ForestMarkRegistry: Sendable, Equatable {
    public private(set) var marks: [Character: LiminalForestAnchor] = [:]

    public init() {}

    public mutating func set(_ name: Character, anchor: LiminalForestAnchor) {
        marks[name] = anchor
    }

    public func anchor(named name: Character) -> LiminalForestAnchor? {
        marks[name]
    }

    public mutating func unset(_ name: Character) {
        marks.removeValue(forKey: name)
    }

    /// Sorted slot letters with a live anchor. Used to drive dynamic
    /// completion options for `:CSTJumpToMark` / `:CSTUnmark`.
    public var allLetters: [Character] {
        marks.keys.sorted()
    }
}

public extension ForestMarkRegistry {
    /// True if `name` is one of the per-document mark slots we accept
    /// for v1 (`a`-`z` and `A`-`Z`). Vim convention is lowercase = local
    /// and uppercase = global; we don't distinguish for v1 — both are
    /// independent session-local slots.
    static func isValidMarkName(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1,
              let scalar = ch.unicodeScalars.first
        else { return false }
        let v = scalar.value
        return (0x61...0x7A).contains(v) || (0x41...0x5A).contains(v)
    }
}

/// Strength tier shown in the `:CSTJumpToMark` popup. Mirrors the live
/// (non-`.lost`) cases of `LiminalForestResolution` so the UI doesn't
/// pull in Cambium's policy-parameterised enum.
public enum ForestMarkStrength: Sendable, Equatable, Hashable {
    case strong
    case weak
    case recovered
}

/// One-line preview of a forest mark for popup display. Built by the
/// Coordinator (which has source-text + tree access) and consumed by
/// the controller when emitting dynamic `:CSTJumpToMark` / `:CSTUnmark`
/// completion entries.
public struct ForestMarkPreview: Sendable, Equatable {
    public let text: String
    public let strength: ForestMarkStrength

    public init(text: String, strength: ForestMarkStrength) {
        self.text = text
        self.strength = strength
    }
}
