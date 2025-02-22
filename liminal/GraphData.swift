import Foundation

// Define NodeContent enum to represent different types of content
public enum NodeContent {
    case markdown(String)
    case pdf(URL)
}

// Define GraphData structure (provided in the context)
struct GraphData {
    let nodeCount: Int
    let edges: [EdgeID]
    let names: [String]
    let contents: [NodeContent]
    
    init(nodeCount: Int, edges: [EdgeID], names: [String]? = nil, contents: [NodeContent]? = nil) {
        self.nodeCount = nodeCount
        self.edges = edges
        if let providedNames = names, providedNames.count == nodeCount {
            self.names = providedNames
        } else {
            self.names = (0..<nodeCount).map { "N\($0 + 1)" }
        }
        if let providedContents = contents, providedContents.count == nodeCount {
            self.contents = providedContents
        } else {
            // Default to empty markdown content
            self.contents = (0..<nodeCount).map { _ in .markdown("") }
        }
    }
}

// Main parser function
func parseGraphData(from directoryURL: URL) throws -> GraphData {
    let fileManager = FileManager.default
    
    // Get all .md and .pdf files in the directory
    let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" || $0.pathExtension == "pdf" }
    
    // Extract node names and create a mapping to indices
    let nodeCount = files.count
    let names = files.map { $0.deletingPathExtension().lastPathComponent }
    let nameToIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
    
    // Initialize arrays for contents and edges
    var contents: [NodeContent] = []
    var edges: [EdgeID] = []
    
    // Process each file
    for (index, fileURL) in files.enumerated() {
        if fileURL.pathExtension == "md" {
            // Process markdown file
            let content = try String(contentsOf: fileURL)
            let body = parseBody(content)
            contents.append(.markdown(body))
            
            // Extract links from markdown content
            let links = extractLinks(from: body)
            for link in links {
                if let targetIndex = nameToIndex[link] {
                    let source = NodeID(id: index)
                    let target = NodeID(id: targetIndex)
                    let edge = EdgeID(source: source, target: target)
                    edges.append(edge)
                }
            }
        } else {
            // Process PDF file - store the URL
            contents.append(.pdf(fileURL))
            // Note: PDF files don't contain links, so we don't add any edges
        }
    }
    
    return GraphData(nodeCount: nodeCount, edges: edges, names: names, contents: contents)
}

func parseGraphDataFromBundleRoot(files: [URL]) throws -> GraphData {
    let names = files.map { $0.deletingPathExtension().lastPathComponent }
    let nameToIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
    var contents: [NodeContent] = []
    var edges: [EdgeID] = []
    
    for (index, url) in files.enumerated() {
        if url.pathExtension == "md" {
            let content = try String(contentsOf: url)
            let body = parseBody(content)
            contents.append(.markdown(body))
            let links = extractLinks(from: body)
            for link in links {
                if let targetIndex = nameToIndex[link] {
                    edges.append(EdgeID(source: NodeID(id: index), target: NodeID(id: targetIndex)))
                }
            }
        } else if url.pathExtension == "pdf" {
            contents.append(.pdf(url))
            // PDFs don't contain links, so we don't add any edges
        }
    }
    return GraphData(nodeCount: files.count, edges: edges, names: names, contents: contents)
}

// Helper function to parse body, excluding front matter
func parseBody(_ content: String) -> String {
    // Use regex to match front matter (starts with "---\n" and ends with "\n---\n")
    let pattern = "^---\n([\\s\\S]*?)\\n---\n"
    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
       let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) {
        let frontMatterRange = match.range
        let bodyStart = content.index(content.startIndex, offsetBy: frontMatterRange.location + frontMatterRange.length)
        return String(content[bodyStart...])
    } else {
        // No front matter found, return entire content
        return content
    }
}

// Helper function to extract link targets from body
func extractLinks(from body: String) -> [String] {
    // Regex to match [[Target|Alias]] or [[Target]]
    // - First capture group is the Target
    // - |Alias part is optional
    let pattern = "\\[\\[([^\\]\\|]+)(\\|([^\\]]+))?\\]\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    
    let nsRange = NSRange(location: 0, length: body.utf16.count)
    let matches = regex.matches(in: body, options: [], range: nsRange)
    
    return matches.compactMap { match in
        if match.numberOfRanges >= 2 {
            let targetRange = match.range(at: 1)
            if let swiftRange = Range(targetRange, in: body) {
                // Trim whitespace from target name for consistency
                return String(body[swiftRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
