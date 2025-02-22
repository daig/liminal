//
//  File.swift
//  liminal
//
//  Created by David Girardo on 2/22/25.
//

import Foundation

struct NoteData: Codable, Hashable {
    var title: String
    var content: String
    private var originalTitle: String
    
    init(title: String, content: String) {
        self.title = title
        self.content = content
        self.originalTitle = title
    }
    
    mutating func save() throws {
        // Get the iCloud container URL
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
            throw NSError(domain: "iCloudError", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        // Create the Documents directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Create markdown content with front matter
        let markdownContent = """
        ---
        title: \(title)
        ---
        
        \(content)
        """
        
        // Create file URLs for both old and new titles
        let safeOriginalTitle = originalTitle.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        let safeNewTitle = title.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        
        let oldFileURL = documentsURL.appendingPathComponent("\(safeOriginalTitle).md")
        let newFileURL = documentsURL.appendingPathComponent("\(safeNewTitle).md")
        
        let fileManager = FileManager.default
        
        // Handle file operations based on what exists and what's changing
        if safeOriginalTitle != safeNewTitle {
            // Title has changed
            if fileManager.fileExists(atPath: oldFileURL.path) {
                // Original file exists, rename it
                if fileManager.fileExists(atPath: newFileURL.path) {
                    // If a file with the new name already exists, remove it first
                    try fileManager.removeItem(at: newFileURL)
                }
                try fileManager.moveItem(at: oldFileURL, to: newFileURL)
            }
        }
        
        // At this point, we either have:
        // 1. The original file in its original location (no title change)
        // 2. The original file moved to the new location (title change)
        // 3. No file yet (new file)
        
        // Write the content to the appropriate location
        let targetURL = safeOriginalTitle != safeNewTitle ? newFileURL : oldFileURL
        try markdownContent.write(to: targetURL, atomically: true, encoding: .utf8)
        
        // Update the original title to match the new title
        originalTitle = title
    }
}
