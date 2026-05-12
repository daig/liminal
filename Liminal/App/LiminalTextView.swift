import AppKit
import CambiumCore
import CambiumIncremental
import SwiftUI

struct LiminalTextView: NSViewRepresentable {
    @ObservedObject var document: LiminalSourceDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("NSTextView.scrollableTextView() did not return an NSTextView")
        }

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 12, height: 12)

        textView.string = document.session.source
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView

        // Make NSTextView the first responder once the view is in the
        // window. Without this, SwiftUI's hosting view often holds focus
        // and menu/keyboard actions (Cmd-S, Cmd-F, Cmd-Z, etc.) don't
        // reach the text view via the responder chain.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let target = document.session.source
        if textView.string != target {
            context.coordinator.isApplyingProgrammaticEdit = true
            textView.string = target
            context.coordinator.isApplyingProgrammaticEdit = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextStorageDelegate {
        let document: LiminalSourceDocument
        weak var textView: NSTextView?
        var isApplyingProgrammaticEdit = false

        init(document: LiminalSourceDocument) {
            self.document = document
        }

        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }

            // AppKit dispatches textStorage delegate callbacks on the layout
            // manager's thread, which is the main thread for typical NSTextView
            // setups. Extract the (Sendable) replacement string here before
            // hopping onto the MainActor closure so we don't capture the
            // non-Sendable NSTextStorage across the boundary.
            let replacement = textStorage.attributedSubstring(from: editedRange).string

            MainActor.assumeIsolated {
                guard !isApplyingProgrammaticEdit else { return }

                let preEditRange = NSRange(
                    location: editedRange.location,
                    length: editedRange.length - delta
                )
                let preEditSource = document.session.source
                guard let byteRange = LiminalTextView.utf16RangeToByteRange(
                    preEditRange,
                    in: preEditSource
                ) else {
                    NSLog("LiminalTextView: failed to convert NSRange \(preEditRange) to byte range")
                    return
                }

                let edit = TextEdit(
                    range: TextRange(
                        start: TextSize(UInt32(byteRange.lowerBound)),
                        length: TextSize(UInt32(byteRange.count))
                    ),
                    replacement: replacement
                )
                document.applyTextEdits([edit])
            }
        }
    }

    nonisolated static func utf16RangeToByteRange(
        _ nsRange: NSRange,
        in source: String
    ) -> Range<Int>? {
        let utf16 = source.utf16
        guard nsRange.location >= 0,
              nsRange.length >= 0,
              nsRange.location <= utf16.count,
              nsRange.location + nsRange.length <= utf16.count
        else { return nil }

        let startUTF16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location)
        let endUTF16 = utf16.index(startUTF16, offsetBy: nsRange.length)
        guard let startStr = String.Index(startUTF16, within: source),
              let endStr = String.Index(endUTF16, within: source)
        else { return nil }

        let startByte = source.utf8.distance(from: source.utf8.startIndex, to: startStr)
        let endByte = source.utf8.distance(from: source.utf8.startIndex, to: endStr)
        return startByte..<endByte
    }
}
