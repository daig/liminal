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

public struct VimPasteboardEntry: Sendable, Equatable {
    public let text: String
    public let kind: YankKind
    public let structuralFragmentData: Data?

    public init(
        text: String,
        kind: YankKind,
        structuralFragmentData: Data? = nil
    ) {
        self.text = text
        self.kind = kind
        self.structuralFragmentData = structuralFragmentData
    }
}

/// Wrapper around `NSPasteboard.general` that round-trips a vim
/// `YankKind` alongside the text payload via a custom UTI. When
/// the pasteboard was last written by another app (no kind UTI
/// present), reads degrade to `.characterwise` — the safe default.
@MainActor
public enum SystemPasteboard {
    static let kindUTI = NSPasteboard.PasteboardType("dev.sub.liminal.vim.yankKind")
    static let structuralFragmentUTI = NSPasteboard.PasteboardType("dev.sub.liminal.cst.fragment")

    /// Test/inject hook. Defaults to the system general pasteboard.
    /// Tests assign a fresh `NSPasteboard(name:)` so they don't
    /// stomp on the user's clipboard.
    static var pasteboard: NSPasteboard = .general

    public static func write(
        text: String,
        kind: YankKind,
        structuralFragmentData: Data? = nil
    ) {
        let pb = pasteboard
        var types: [NSPasteboard.PasteboardType] = [.string, kindUTI]
        if structuralFragmentData != nil {
            types.append(structuralFragmentUTI)
        }
        pb.declareTypes(types, owner: nil)
        pb.setString(text, forType: .string)
        pb.setString(kind.rawValue, forType: kindUTI)
        if let structuralFragmentData {
            pb.setData(structuralFragmentData, forType: structuralFragmentUTI)
        }
    }

    public static func read() -> VimPasteboardEntry? {
        let pb = pasteboard
        guard let text = pb.string(forType: .string) else { return nil }
        let kind = pb.string(forType: kindUTI)
            .flatMap(YankKind.init(rawValue:)) ?? .characterwise
        return VimPasteboardEntry(
            text: text,
            kind: kind,
            structuralFragmentData: pb.data(forType: structuralFragmentUTI)
        )
    }
}
