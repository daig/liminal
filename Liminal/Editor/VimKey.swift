/// A keypress reduced to a vim-binding-relevant value. The `character`
/// case carries `event.charactersIgnoringModifiers`-style data (so `J`
/// and `j` differ by modifiers, not by character), and `special` carries
/// non-printable keys we bind by name.
///
/// Constructed from `NSEvent` via the AppKit-side adapter in
/// `VimTextView.swift`; the type itself stays AppKit-free so tests can
/// build `VimKey` values directly without spinning up AppKit.
public struct VimKey: Hashable, Sendable {
    public let payload: Payload
    public let modifiers: Modifiers

    public enum Payload: Hashable, Sendable {
        case character(Character)
        case special(SpecialKey)
    }

    public enum SpecialKey: Hashable, Sendable {
        case escape
        case returnKey
        case tab
        case backspace
        case delete
        case left
        case right
        case up
        case down
        case space
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let shift   = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option  = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public init(payload: Payload, modifiers: Modifiers = []) {
        self.payload = payload
        self.modifiers = modifiers
    }

    public static func char(_ c: Character, modifiers: Modifiers = []) -> VimKey {
        VimKey(payload: .character(c), modifiers: modifiers)
    }

    public static func special(_ key: SpecialKey, modifiers: Modifiers = []) -> VimKey {
        VimKey(payload: .special(key), modifiers: modifiers)
    }

    /// True when this key represents a numeric digit `0`-`9` with no
    /// modifiers — used by the controller to accumulate `pendingCount`
    /// before consulting the binding tree.
    public var asCountDigit: Int? {
        guard modifiers.isEmpty,
              case let .character(c) = payload,
              let digit = c.wholeNumberValue,
              (0...9).contains(digit)
        else { return nil }
        return digit
    }

    /// Display string for hint surfaces. Matches the vim convention:
    /// `<Space>`, `<Esc>`, `<Tab>`, etc. for special keys; bare character
    /// for printables; `<C-x>` / `<S-x>` for modifier combinations.
    public var displayString: String {
        let base: String
        switch payload {
        case .character(let c):
            base = String(c)
        case .special(.escape):    base = "<Esc>"
        case .special(.returnKey): base = "<Return>"
        case .special(.tab):       base = "<Tab>"
        case .special(.backspace): base = "<BS>"
        case .special(.delete):    base = "<Del>"
        case .special(.left):      base = "<Left>"
        case .special(.right):     base = "<Right>"
        case .special(.up):        base = "<Up>"
        case .special(.down):      base = "<Down>"
        case .special(.space):     base = "<Space>"
        }
        if modifiers.isEmpty { return base }
        var prefix = ""
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option)  { prefix += "A-" }
        if modifiers.contains(.shift)   { prefix += "S-" }
        if modifiers.contains(.command) { prefix += "D-" }
        return "<\(prefix)\(base)>"
    }
}
