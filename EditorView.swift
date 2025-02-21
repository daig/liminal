import SwiftUI
import UIKit

struct ContentView: View {
    @State private var text: String = ""
    
    var body: some View {
        VStack {
            ObsidianTextEditor(text: $text)
                .frame(minWidth: 300, minHeight: 200)
                .padding()
        }
    }
}

struct ObsidianTextEditor: UIViewRepresentable {
    @Binding var text: String
    private let linkPattern = "\\[\\[([^\\]]+)\\]\\]"
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .systemGray6
        textView.layer.cornerRadius = 8
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let currentPosition = uiView.selectedRange
        let attributedText = formatText(text, cursorPosition: currentPosition)
        uiView.attributedText = attributedText
        
        // Preserve cursor position
        uiView.selectedRange = currentPosition
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func formatText(_ text: String, cursorPosition: NSRange) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else {
            return attributedString
        }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        
        for match in matches.reversed() {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            
            // Check if cursor is within the link
            let isCursorInLink = cursorPosition.location >= fullRange.lowerBound &&
                               cursorPosition.location <= fullRange.upperBound
            
            if !isCursorInLink {
                let linkText = (text as NSString).substring(with: innerRange)
                let linkRange = fullRange
                
                // Remove [[ and ]] and set link attributes
                attributedString.replaceCharacters(in: linkRange,
                    with: NSAttributedString(
                        string: linkText,
                        attributes: [
                            .foregroundColor: UIColor.blue,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .link: URL(string: "obsidian://\(linkText)")!
                        ]
                    )
                )
            }
        }
        
        return attributedString
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ObsidianTextEditor
        
        init(_ parent: ObsidianTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            print("Tapped link: \(URL.absoluteString)")
            // Handle link tap here
            return false // Return true if you want system to handle URL
        }
    }
}

