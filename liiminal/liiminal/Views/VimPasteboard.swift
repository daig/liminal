import AppKit

enum VimPasteboard {
    private static let styleType = NSPasteboard.PasteboardType(
        "com.liminal.vim.paste-style"
    )

    static func write(_ payload: VimPastePayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload.text, forType: .string)
        pasteboard.setString(payload.style.rawValue, forType: styleType)
    }

    static func read() -> VimPastePayload? {
        let pasteboard = NSPasteboard.general

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }

        let style =
            pasteboard.string(forType: styleType)
            .flatMap(VimPasteStyle.init(rawValue:))
            ?? .characterwise

        return VimPastePayload(text: text, style: style)
    }
}
