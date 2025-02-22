import SwiftUI
import UIKit

struct ContentView: View {
    @State private var text: String = ""
    
    init(text: String) {
        _text = State(initialValue: text)
    }
    
    var body: some View {
        ObsidianTextEditor(text: $text)
            .onOpenURL { url in
                if url.scheme == "liminal" {
                    let fileName = url.host ?? url.path // Extract the file name
                    print("Navigating to file: \(fileName)")
                    // Add logic to open the file in your graph, e.g.:
                    // navigateToFile(fileName)
                }
            }
    }
}

struct ObsidianTextEditor: UIViewRepresentable {
    @Binding var text: String
    private let linkPattern = "\\[\\[([^\\]]+)\\]\\]"
    static let font: UIFont = .preferredFont(forTextStyle: .body).withSize(30)
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        
        // Typography for visionOS
        textView.font = ObsidianTextEditor.font
        textView.textColor = .white
        textView.backgroundColor = .clear // Ensure no background color
        textView.tintColor = .white
        
        // Padding inside the text view
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        
        // Explicitly remove all borders and shadows
        textView.layer.borderWidth = 0
        
        // Disable any default appearance quirks
        textView.layer.backgroundColor = nil // Ensure layer has no color
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let attributedText = formatText(rawText: text, cursorPosition: uiView.selectedRange)
        uiView.attributedText = attributedText
        let currentPosition = uiView.selectedRange
        uiView.selectedRange = currentPosition
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func formatText(rawText: String, cursorPosition: NSRange) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: rawText)
        
        // Define your link pattern (e.g., for markdown links like [text](link))
        guard let regex = try? NSRegularExpression(pattern: "\\[.*?\\]\\((.*?)\\)") else {
            return attributedString
        }
        
        let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let matches = regex.matches(in: rawText, range: nsRange)
        
        // Default text styling
        attributedString.addAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 16) // Adjust font as needed
        ], range: NSRange(location: 0, length: attributedString.length))
        
        for match in matches {
            let fullRange = match.range
            let innerRange = match.range(at: 1) // Capture group for link target
            let linkText = (rawText as NSString).substring(with: innerRange)
            
            // Check if cursor is within the link (optional, adjust logic as needed)
            let isCursorInLink = cursorPosition.location >= fullRange.lowerBound &&
                                cursorPosition.location <= fullRange.upperBound
            
            if !isCursorInLink {
                // Encode special characters in linkText for URL safety
                if let encodedLinkText = linkText.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    // Use a custom scheme like "liminal://" to link to files in your graph
                    let urlString = "liminal://\(encodedLinkText)"
                    if let url = URL(string: urlString) {
                        attributedString.addAttributes([
                            .foregroundColor: UIColor.systemBlue,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .link: url
                        ], range: fullRange)
                    } else {
                        print("Warning: Could not create URL from \(urlString)")
                    }
                } else {
                    print("Warning: Could not encode link text: \(linkText)")
                }
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
            return false
        }
    }
}
