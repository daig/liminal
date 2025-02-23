//
//  PDFViewer.swift
//  liminal
//
//  Created by David Girardo on 2/22/25.
//

import SwiftUI
import PDFKit

struct PDFData {
    var title: String
    private(set) var url: URL
    private var originalTitle: String
    
    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.originalTitle = self.title
    }
    
    mutating func save() async throws {
        // Get the iCloud container URL
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.dai.liminal") else {
            throw NSError(domain: "iCloudError", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud container not available"])
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        // Create safe file names
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let safeOriginalTitle = originalTitle.components(separatedBy: invalidCharacters).joined()
        let safeNewTitle = title.components(separatedBy: invalidCharacters).joined()
        
        // Check if we're working with a file in the Documents directory
        let oldFileURL: URL
        if url.deletingLastPathComponent().path == documentsURL.path {
            // File is already in Documents directory
            oldFileURL = url
        } else {
            // File might be in Documents with a different name
            oldFileURL = documentsURL.appendingPathComponent("\(safeOriginalTitle).pdf")
        }
        
        let newFileURL = documentsURL.appendingPathComponent("\(safeNewTitle).pdf")
        
        let fileManager = FileManager.default
        
        if safeOriginalTitle != safeNewTitle {
            // Title has changed
            guard fileManager.fileExists(atPath: oldFileURL.path) else {
                throw NSError(domain: "FileError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot find the PDF file at \(oldFileURL.path)"])
            }
            
            if fileManager.fileExists(atPath: newFileURL.path) {
                // If a file with the new name already exists, remove it first
                try fileManager.removeItem(at: newFileURL)
            }
            
            try fileManager.moveItem(at: oldFileURL, to: newFileURL)
            
            // Update the URL to point to the new location
            self.url = newFileURL
            
            // Wait a moment to ensure file system operations are complete
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Update the original title to match the new title
        originalTitle = title
    }
}

struct PDFViewer: View {
    @State private var pdfData: PDFData
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = true
    var onSave: ((PDFData) -> Void)?
    
    init(url: URL, onSave: ((PDFData) -> Void)? = nil) {
        _pdfData = State(initialValue: PDFData(url: url))
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title editor
            TextField("Title", text: $pdfData.title)
                .font(.title)
                .padding()
                .background(.ultraThinMaterial)
            
            if isLoading {
                Spacer()
                ProgressView("Loading PDF...")
                    .task {
                        // Simulate a small delay to ensure UI is responsive
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        isLoading = false
                    }
                Spacer()
            } else {
                // PDF view
                PDFViewRepresentable(url: pdfData.url)
                    .id(pdfData.url) // Force view refresh when URL changes
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomOrnament) {
                Button("Save") {
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 100_000_000) // Wait 0.1 seconds before saving
                            var localData = pdfData // Create a local copy
                            try await localData.save()
                            pdfData = localData // Update the state with the saved data
                            onSave?(pdfData)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        }
        .alert("Error Saving", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

// Internal PDFView wrapper to maintain the existing PDFKit functionality
private struct PDFViewRepresentable: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        
        // Load the PDF document asynchronously
        Task {
            let document = PDFDocument(url: url)
            await MainActor.run {
                pdfView.document = document
            }
        }
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        // Load the PDF document asynchronously when URL changes
        Task {
            let document = PDFDocument(url: url)
            await MainActor.run {
                uiView.document = document
            }
        }
    }
}
