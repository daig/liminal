import SwiftUI
import UIKit
import Down

struct ContentView: View {
    @State private var noteData: NoteData
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isEditing: Bool = false // New state for edit/view mode
    @State private var showingSummary = false
    @State private var summary = ""
    @State private var isGeneratingSummary = false
    @State private var showingSettings = false
    @State private var isExtractingTerms = false
    @State private var showingTermMatches = false
    @State private var termMatches: [(term: String, match: String?, reason: String?)] = []
    @AppStorage("openAIKey") private var apiKey = ""
    let graphData: GraphData
    var onSave: ((NoteData) -> Void)?
    
    init(noteData: NoteData, graphData: GraphData, onSave: ((NoteData) -> Void)? = nil, isEditing: Bool = false) {
        _noteData = State(initialValue: noteData)
        self.graphData = graphData
        self.onSave = onSave
        _isEditing = State(initialValue: isEditing)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title editor: Editable in edit mode, read-only in view mode
            if isEditing {
                TextField("Title", text: $noteData.title)
                    .font(.title)
                    .padding()
                    .background(.ultraThinMaterial)
            } else {
                Text(noteData.title)
                    .font(.title)
                    .padding()
                    .background(.ultraThinMaterial)
            }
            
            // Content: Editor in edit mode, rendered markdown in view mode
            if isEditing {
                ObsidianTextEditor(text: $noteData.content)
            } else {
                MarkdownViewer(markdown: noteData.content)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                // Settings button
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                }
                
                // Extract Terms button
                Button(action: {
                    if apiKey.isEmpty {
                        errorMessage = "Please set your OpenAI API key in settings"
                        showError = true
                    } else {
                        Task {
                            await extractSignificantTerms()
                        }
                    }
                }) {
                    Label("Extract Terms", systemImage: "text.magnifyingglass")
                }
                .disabled(isExtractingTerms)
                
                // AI Summary button
                Button(action: {
                    if apiKey.isEmpty {
                        errorMessage = "Please set your OpenAI API key in settings"
                        showError = true
                    } else {
                        Task {
                            await generateSummary()
                        }
                    }
                }) {
                    Label("AI Summary", systemImage: "sparkles.rectangle.stack")
                }
                .disabled(isGeneratingSummary)
                
                // Toggle button between edit and view modes
                Button(action: {
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "View" : "Edit")
                }
                
                // Existing Save button
                Button("Save") {
                    do {
                        try noteData.save()
                        onSave?(noteData)
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingSummary) {
            NavigationView {
                ScrollView {
                    Text(summary)
                        .padding()
                }
                .navigationTitle("AI Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingSummary = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingTermMatches) {
            NavigationView {
                List {
                    ForEach(termMatches, id: \.term) { item in
                        VStack(alignment: .leading) {
                            Text(item.term)
                                .font(.headline)
                            if let match = item.match {
                                Text("→ \(match)")
                                    .foregroundColor(.secondary)
                                if let reason = item.reason {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            } else {
                                if let reason = item.reason {
                                    Text(reason)
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    Text("No definitional match found")
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Extracted Terms")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingTermMatches = false
                        }
                    }
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "liminal" {
                let fileName = url.host ?? url.path
                print("Navigating to file: \(fileName)")
                // Add navigation logic here if needed
            }
        }
    }
    
    private func generateSummary() async {
        isGeneratingSummary = true
        do {
            let client = OpenAIClient(apiKey: apiKey)
            summary = try await client.generateSummary(text: noteData.content)
            showingSummary = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isGeneratingSummary = false
    }
    
    private func extractSignificantTerms() async {
        isExtractingTerms = true
        termMatches = []
        do {
            let client = OpenAIClient(apiKey: apiKey)
            
            // First, extract the significant terms
            print("\n=== Extracting Significant Terms ===")
            let terms = try await client.extractSignificantTerms(text: noteData.content)
            print("Extracted terms:", terms)
            print("===========================\n")
            
            // Debug information about GraphData
            print("=== Debug GraphData ===")
            print("Total nodes in graph:", graphData.nodeCount)
            print("Names array count:", graphData.names.count)
            print("Contents array count:", graphData.contents.count)
            print("First few names in graph:")
            for (index, name) in graphData.names.prefix(5).enumerated() {
                print("[\(index)]: '\(name)'")
            }
            if graphData.names.count > 5 {
                print("... and \(graphData.names.count - 5) more")
            }
            print("===========================\n")
            
            // Wait a moment to prevent rate limits
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Then, find matches for all terms at once
            print("\n=== Finding Definitional Matches ===")
            termMatches = try await client.matchTermsToFiles(terms: terms, filenames: graphData.names)
            
            // Print matches
            for match in termMatches {
                print("Term: \(match.term)")
                if let filename = match.match {
                    print("  → Match: \(filename)")
                    if let reason = match.reason {
                        print("  → Reason: \(reason)")
                    }
                } else if let reason = match.reason {
                    print("  → No match: \(reason)")
                } else {
                    print("  → No match found")
                }
            }
            print("===========================\n")
            
            // Update the note content with wiki-style links
            var updatedContent = noteData.content
            for match in termMatches {
                guard let filename = match.match else { continue }
                
                // Create a regex pattern that matches the term with word boundaries
                // and is case-insensitive
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: match.term))\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                
                // Get all matches in the content
                let range = NSRange(updatedContent.startIndex..<updatedContent.endIndex, in: updatedContent)
                let matches = regex.matches(in: updatedContent, range: range)
                
                // Process matches from last to first to avoid invalidating ranges
                for match in matches.reversed() {
                    let matchRange = match.range
                    guard let textRange = Range(matchRange, in: updatedContent) else { continue }
                    let originalText = String(updatedContent[textRange])
                    
                    // If the filename is identical (ignoring case) to the matched text,
                    // use simple [[Term]] format, otherwise use [[Term|display text]]
                    let replacement: String
                    if filename.lowercased() == originalText.lowercased() {
                        replacement = "[[\(filename)]]"
                    } else {
                        replacement = "[[\(filename)|\(originalText)]]"
                    }
                    
                    updatedContent.replaceSubrange(textRange, with: replacement)
                }
            }
            
            // Update the note content
            noteData.content = updatedContent
            
            // Show the term matches sheet
            showingTermMatches = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isExtractingTerms = false
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
