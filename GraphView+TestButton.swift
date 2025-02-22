//
//  GraphView+TestButton.swift
//  liminal
//
//  Created by David Girardo on 2/22/25.
//

import Foundation

extension GraphView {
    static func copyMdFilesToICloud(mdFiles: [URL]) throws {
        // Get the iCloud container URL
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw NSError(domain: "iCloudError", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        // Create the Documents directory if it doesn’t exist
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Copy each .md file
        for mdFileURL in mdFiles {
            let fileName = mdFileURL.lastPathComponent
            let destinationURL = documentsURL.appendingPathComponent(fileName)
            
            // Remove existing file if it exists to allow overwriting
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Perform the copy operation
            try FileManager.default.copyItem(at: mdFileURL, to: destinationURL)
            print("Copied \(fileName) to iCloud Documents")
        }
    }
}
