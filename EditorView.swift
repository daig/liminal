import SwiftUI
import UIKit

struct ContentView: View {
    @State private var text: String = ""
    
    var body: some View {
        VStack {
            ObsidianTextEditor(text: $text)
                .frame(minWidth: 300, minHeight: 200)
                .padding()
                // Apply glass material background at the container level
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        
        // Typography updates for visionOS
        textView.font = .preferredFont(forTextStyle: .body) // Retains dynamic type support
        textView.textColor = .white // White text as per request
        
        // Transparent background to allow SwiftUI material to show through
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 8
        
        // Ensure text is readable over glass material
        textView.tintColor = .white // Cursor and selection color
        
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
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else {
            return attributedString
        }
        
        let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let matches = regex.matches(in: rawText, range: nsRange)
        
        // Default attributes for all text
        attributedString.addAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.preferredFont(forTextStyle: .body)
        ], range: NSRange(location: 0, length: attributedString.length))
        
        for match in matches {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            let linkText = (rawText as NSString).substring(with: innerRange)
            
            let isCursorInLink = cursorPosition.location >= fullRange.lowerBound &&
                               cursorPosition.location <= fullRange.upperBound
            
            if !isCursorInLink {
                attributedString.addAttributes([
                    .foregroundColor: UIColor.systemBlue, // Adjusted for visibility on glass
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: URL(string: "obsidian://\(linkText)")!
                ], range: fullRange)
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
