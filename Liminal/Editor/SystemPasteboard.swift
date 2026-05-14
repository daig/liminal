import AppKit
import Foundation

/// Vim's "kind" of yank: characterwise / linewise / blockwise / cstForest.
/// Determines paste behavior — charwise inserts inline, linewise inserts
/// as new line(s), blockwise inserts as a column. `cstForest` marks a
/// yank that originated from visual CST mode and may carry a serialized
/// structural payload for CST-aware paste.
public enum YankKind: String, Sendable, Equatable, Hashable {
    case characterwise
    case linewise
    case blockwise
    case cstForest
}

public struct VimPasteboardEntry: Sendable, Equatable {
    public let text: String
    public let kind: YankKind
    public let structuralPayloadData: Data?

    public init(
        text: String,
        kind: YankKind,
        structuralPayloadData: Data? = nil
    ) {
        self.text = text
        self.kind = kind
        self.structuralPayloadData = structuralPayloadData
    }
}

/// Wrapper around `NSPasteboard.general` that round-trips a vim
/// `YankKind` alongside the text payload via a custom UTI. When
/// the pasteboard was last written by another app (no kind UTI
/// present), reads degrade to `.characterwise` — the safe default.
@MainActor
public enum SystemPasteboard {
    static let didWriteNotification = Notification.Name("dev.sub.liminal.systemPasteboardDidWrite")
    static let kindUTI = NSPasteboard.PasteboardType("dev.sub.liminal.vim.yankKind")
    static let structuralPayloadUTI = NSPasteboard.PasteboardType("dev.sub.liminal.cst.payload")

    /// Test/inject hook. Defaults to the system general pasteboard.
    /// Tests assign a fresh `NSPasteboard(name:)` so they don't
    /// stomp on the user's clipboard.
    static var pasteboard: NSPasteboard = .general

    public static func write(
        text: String,
        kind: YankKind,
        structuralPayloadData: Data? = nil
    ) {
        let pb = pasteboard
        var types: [NSPasteboard.PasteboardType] = [.string, kindUTI]
        if structuralPayloadData != nil {
            types.append(structuralPayloadUTI)
        }
        pb.declareTypes(types, owner: nil)
        pb.setString(text, forType: .string)
        pb.setString(kind.rawValue, forType: kindUTI)
        if let structuralPayloadData {
            pb.setData(structuralPayloadData, forType: structuralPayloadUTI)
        }
        NotificationCenter.default.post(name: didWriteNotification, object: nil)
    }

    public static func read() -> VimPasteboardEntry? {
        let pb = pasteboard
        guard let text = pb.string(forType: .string) else { return nil }
        let kind = pb.string(forType: kindUTI)
            .flatMap(YankKind.init(rawValue:)) ?? .characterwise
        return VimPasteboardEntry(
            text: text,
            kind: kind,
            structuralPayloadData: pb.data(forType: structuralPayloadUTI)
        )
    }
}
