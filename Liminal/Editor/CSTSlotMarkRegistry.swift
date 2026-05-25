/// Per-document store of CST slot marks (`:CSTSlotMark <letter>`) backed by
/// stable ``CSTSlotAnchor`` values.
///
/// Slot marks are session-local, like forest marks. They resolve lazily against
/// the current tree when a future consumer needs them; this slice only captures
/// and stores the anchors.
public struct CSTSlotMarkRegistry: Sendable, Equatable {
    public private(set) var marks: [Character: CSTSlotAnchor] = [:]

    public init() {}

    public mutating func set(_ name: Character, anchor: CSTSlotAnchor) {
        marks[name] = anchor
    }

    public func anchor(named name: Character) -> CSTSlotAnchor? {
        marks[name]
    }

    public mutating func unset(_ name: Character) {
        marks.removeValue(forKey: name)
    }

    public var allLetters: [Character] {
        marks.keys.sorted()
    }
}

public extension CSTSlotMarkRegistry {
    /// Same accepted namespace as CST forest marks: a-z and A-Z.
    static func isValidMarkName(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1,
              let scalar = ch.unicodeScalars.first
        else { return false }
        let v = scalar.value
        return (0x61...0x7A).contains(v) || (0x41...0x5A).contains(v)
    }
}
