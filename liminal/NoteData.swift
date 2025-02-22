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
    
    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
    
    func save() throws {
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
        
        // Create file URL with the title as filename
        let safeTitle = title.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        let fileURL = documentsURL.appendingPathComponent("\(safeTitle).md")
        
        // Write the content to the file
        try markdownContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
