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
        print("Starting save operation for note: \(title)")
        
        // Get the iCloud container URL
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
            print("Error: iCloud container not available")
            throw NSError(domain: "iCloudError", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available. Please ensure iCloud is enabled and you are signed in."])
        }
        print("iCloud container URL: \(containerURL.path)")
        
        let documentsURL = containerURL.appendingPathComponent("Documents")
        print("Documents URL: \(documentsURL.path)")
        
        // Create the Documents directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            print("Documents directory does not exist, creating it...")
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
            print("Documents directory created successfully")
        }
        
        // Create markdown content with front matter
        let markdownContent = """
        ---
        title: \(title)
        ---
        
        \(content)
        """
        
        // Create file URLs for both old and new titles
        // Filter out any characters that are not allowed in filenames, but preserve spaces
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let safeOriginalTitle = originalTitle.components(separatedBy: invalidCharacters).joined()
        let safeNewTitle = title.components(separatedBy: invalidCharacters).joined()
        
        print("Safe original title: \(safeOriginalTitle)")
        print("Safe new title: \(safeNewTitle)")
        
        // Use appendingPathComponent which will handle spaces correctly
        let oldFileURL = documentsURL.appendingPathComponent("\(safeOriginalTitle).md")
        let newFileURL = documentsURL.appendingPathComponent("\(safeNewTitle).md")
        
        print("Old file URL: \(oldFileURL.path)")
        print("New file URL: \(newFileURL.path)")
        
        let fileManager = FileManager.default
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var saveError: NSError?
        
        fileCoordinator.coordinate(writingItemAt: safeOriginalTitle != safeNewTitle ? newFileURL : oldFileURL, options: .forReplacing, error: &coordinatorError) { url in
            autoreleasepool {
                do {
                    // Handle file operations based on what exists and what's changing
                    if safeOriginalTitle != safeNewTitle {
                        print("Title has changed, handling file rename...")
                        if fileManager.fileExists(atPath: oldFileURL.path) {
                            print("Original file exists at: \(oldFileURL.path)")
                            if fileManager.fileExists(atPath: newFileURL.path) {
                                print("New file already exists, removing it...")
                                try? fileManager.removeItem(at: newFileURL)
                                print("Existing file removed successfully")
                            }
                            print("Moving file from \(oldFileURL.path) to \(newFileURL.path)")
                            try? fileManager.moveItem(at: oldFileURL, to: newFileURL)
                            print("File moved successfully")
                        } else {
                            print("Original file does not exist at: \(oldFileURL.path)")
                        }
                    }
                    
                    // Write the content to the appropriate location
                    let targetURL = safeOriginalTitle != safeNewTitle ? newFileURL : oldFileURL
                    print("Writing content to: \(targetURL.path)")
                    
                    // Create a temporary file and move it into place
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
                    try markdownContent.write(to: tempURL, atomically: true, encoding: .utf8)
                    
                    if fileManager.fileExists(atPath: targetURL.path) {
                        try? fileManager.removeItem(at: targetURL)
                    }
                    try fileManager.moveItem(at: tempURL, to: targetURL)
                    
                    print("Content written successfully")
                    
                    // Update the original title to match the new title
                    originalTitle = title
                    print("Save operation completed successfully")
                } catch {
                    print("Error during save operation: \(error.localizedDescription)")
                    saveError = error as NSError
                }
            }
        }
        
        if let error = coordinatorError ?? saveError {
            print("File operation error: \(error.localizedDescription)")
            throw error
        }
    }
}
