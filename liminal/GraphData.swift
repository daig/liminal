import Foundation

// Define GraphData structure (provided in the context)
struct GraphData {
    let nodeCount: Int
    let edges: [EdgeID]
    let names: [String]
    let bodies: [String]
    
    init(nodeCount: Int, edges: [EdgeID], names: [String]? = nil, bodies: [String]? = nil) {
        self.nodeCount = nodeCount
        self.edges = edges
        if let providedNames = names, providedNames.count == nodeCount {
            self.names = providedNames
        } else {
            self.names = (0..<nodeCount).map { "N\($0 + 1)" }
        }
        if let providedBodies = bodies, providedBodies.count == nodeCount {
            self.bodies = providedBodies
        } else {
            self.bodies = (0..<nodeCount).map { _ in "" }
        }
    }
}

// Main parser function
func parseGraphData(from directoryURL: URL) throws -> GraphData {
    let fileManager = FileManager.default
    
    // Get all .md files in the directory
    let mdFiles = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" }
    
    // Extract node names and create a mapping to indices
    let nodeCount = mdFiles.count
    let names = mdFiles.map { $0.deletingPathExtension().lastPathComponent }
    let nameToIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
    
    // Initialize arrays for bodies and edges
    var bodies: [String] = []
    var edges: [EdgeID] = []
    
    // Process each .md file
    for (index, mdFileURL) in mdFiles.enumerated() {
        let content = try String(contentsOf: mdFileURL)
        let body = parseBody(content) // Assume this function extracts the body content
        bodies.append(body)
        
        let links = extractLinks(from: body) // Assume this function extracts links
        for link in links {
            if let targetIndex = nameToIndex[link] {
                let source = NodeID(id: index)
                let target = NodeID(id: targetIndex)
                let edge = EdgeID(source: source, target: target)
                edges.append(edge)
            }
        }
    }
    
    return GraphData(nodeCount: nodeCount, edges: edges, names: names, bodies: bodies)
}
func parseGraphDataFromBundleRoot(mdFiles: [URL]) throws -> GraphData {
    let names = mdFiles.map { $0.deletingPathExtension().lastPathComponent }
    let nameToIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
    var bodies: [String] = []
    var edges: [EdgeID] = []
    
    for (index, url) in mdFiles.enumerated() {
        let content = try String(contentsOf: url)
        let body = parseBody(content)
        bodies.append(body)
        let links = extractLinks(from: body)
        for link in links {
            if let targetIndex = nameToIndex[link] {
                edges.append(EdgeID(source: NodeID(id: index), target: NodeID(id: targetIndex)))
            }
        }
    }
    return GraphData(nodeCount: mdFiles.count, edges: edges, names: names, bodies: bodies)
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
