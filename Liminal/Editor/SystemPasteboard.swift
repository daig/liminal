import AppKit
import Foundation

/// Vim's "kind" of yank: characterwise / linewise / blockwise / cstForest.
/// Determines paste behavior — charwise inserts inline, linewise inserts
/// as new line(s), blockwise inserts as a column. `cstForest` marks a
/// yank that originated from visual CST mode; v1 serializes its bytes
/// just like `characterwise` but the discriminator lets a future
/// structural-paste branch recognize CST yanks without breaking
/// already-saved pasteboard data.
public enum YankKind: String, Sendable, Equatable, Hashable {
    case characterwise
    case linewise
    case blockwise
    case cstForest
}

/// Wrapper around `NSPasteboard.general` that round-trips a vim
/// `YankKind` alongside the text payload via a custom UTI. When
/// the pasteboard was last written by another app (no kind UTI
/// present), reads degrade to `.characterwise` — the safe default.
@MainActor
public enum SystemPasteboard {
    static let kindUTI = NSPasteboard.PasteboardType("dev.sub.liminal.vim.yankKind")

    /// Test/inject hook. Defaults to the system general pasteboard.
    /// Tests assign a fresh `NSPasteboard(name:)` so they don't
    /// stomp on the user's clipboard.
    static var pasteboard: NSPasteboard = .general

    public static func write(text: String, kind: YankKind) {
        let pb = pasteboard
        pb.declareTypes([.string, kindUTI], owner: nil)
        pb.setString(text, forType: .string)
        pb.setString(kind.rawValue, forType: kindUTI)
    }

    public static func read() -> (text: String, kind: YankKind)? {
        let pb = pasteboard
        guard let text = pb.string(forType: .string) else { return nil }
        let kind = pb.string(forType: kindUTI)
            .flatMap(YankKind.init(rawValue:)) ?? .characterwise
        return (text, kind)
    }
}
