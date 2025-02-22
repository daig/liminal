import UIKit
import Down
import SwiftUI

struct MarkdownViewer: UIViewRepresentable {
    let markdown: String
    
    // Required by UIViewRepresentable if using a coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear // Matches dark theme
        textView.textColor = .white       // Default color
        textView.tintColor = .white       // Cursor/links
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.delegate = context.coordinator
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        do {
            // Define fonts
            let bodyFont = ObsidianTextEditor.font // Ensure this is accessible
            let codeFont = UIFont(name: "Menlo", size: 30) ?? bodyFont
            let headingFonts = [
                1: bodyFont.withSize(36),
                2: bodyFont.withSize(32),
                3: bodyFont.withSize(28),
                4: bodyFont.withSize(24),
                5: bodyFont.withSize(20),
                6: bodyFont.withSize(18)
            ]
            
            // Create FontCollection without 'listItem'
            let fonts = StaticFontCollection(
                heading1: headingFonts[1]!,
                heading2: headingFonts[2]!,
                heading3: headingFonts[3]!,
                heading4: headingFonts[4]!,
                heading5: headingFonts[5]!,
                heading6: headingFonts[6]!,
                body: bodyFont,
                code: codeFont
            )
            
            // Define heading colors
            var headingColors: [Int: UIColor] = [:]
            for i in 1...6 {
                headingColors[i] = UIColor.white
            }
            
            // Create ColorCollection without 'codeBlockBackground' or 'blockQuote'
            let colors = StaticColorCollection(
                body: UIColor.white,
                code: UIColor.white,
                link: UIColor.systemBlue,
                quote: UIColor.white,
                quoteStripe: UIColor.gray,
                thematicBreak: UIColor.gray,
                listItemPrefix: UIColor.white
            )
            
            // Configure and render markdown
            let configuration = DownStylerConfiguration(fonts: fonts, colors: colors)
            let styler = DownStyler(configuration: configuration)
            let down = Down(markdownString: markdown)
            let attributedString = try down.toAttributedString(styler: styler)
            uiView.attributedText = attributedString
        } catch {
            print("Error rendering markdown: \(error)")
            uiView.attributedText = NSAttributedString(
                string: markdown,
                attributes: [
                    .foregroundColor: UIColor.white,
                    .font: ObsidianTextEditor.font
                ]
            )
        }
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "liminal" {
                print("Navigating to \(URL.host ?? URL.path)")
                return false
            }
            return true
        }
    }
}
