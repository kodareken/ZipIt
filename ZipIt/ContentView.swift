//
//  ContentView.swift
//  ZipIt
//
//  Created by Douglas Ek on 2025-09-16.
//

import SwiftUI
import UniformTypeIdentifiers

struct ArchiveFilePicker: View {
    @Binding var selectedURL: URL?
    
    var body: some View {
        Button(action: selectFile) {
            HStack {
                Image(systemName: "doc.badge.plus")
                Text(selectedURL?.lastPathComponent ?? "Select Archive")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
    
    private func selectFile() {
        print("Opening file selection panel")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .zip,
            UTType(filenameExtension: "tar")!,
            UTType(filenameExtension: "gz")!,
            UTType(filenameExtension: "tgz")!,
            UTType(filenameExtension: "7z")!,
            UTType(filenameExtension: "rar")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            selectedURL = panel.url
            print("Selected file: \(panel.url?.path ?? "none")")
        } else {
            print("File selection cancelled")
        }
    }
}

struct ContentView: View {
    @StateObject private var extractor = ArchiveExtractor()
    @EnvironmentObject var appState: AppState
    @State private var selectedArchiveURL: URL?
    @State private var selectedDestinationURL: URL?
    @State private var showDestinationPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var extractionCompleted = false
    
    let supportedFormats = ["zip", "tar", "gz", "7z", "rar"]
    
    // Create explicit UTType instances
    private var archiveTypes: [UTType] {
        [
            .zip,
            UTType(filenameExtension: "tar")!,
            UTType(filenameExtension: "gz")!,
            UTType(filenameExtension: "tgz")!,
            UTType(filenameExtension: "7z")!,
            UTType(filenameExtension: "rar")!
        ]
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            archiveSelectionSection
            destinationSelectionSection
            extractionButton
            progressSection
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .fileImporter(
            isPresented: $showDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleDestinationSelection
        )
        .alert("Extraction Status", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            print("ContentView appeared")
        }
        .onReceive(appState.$selectedArchiveURL) { url in
            if let url = url {
                print("📁 Auto-loading file: \(url.lastPathComponent)")
                selectedArchiveURL = url
                extractionCompleted = false
                
                // Auto-select Downloads folder as destination if available
                autoSelectDestination()
            }
        }
    }
    
    private var headerSection: some View {
        VStack {
            if let nsImage = NSImage(named: "AppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            } else {
                // Fallback to system icon if AppIcon not found
                Image(systemName: "archivebox")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            Text("ZipIt")
                .font(.largeTitle.bold())
            Text("Simple Archive Extractor")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var archiveSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archive File")
                .font(.headline)
            
            ArchiveFilePicker(selectedURL: $selectedArchiveURL)
            .accessibilityLabel("Select archive file")
            
            Text("Supported formats: \(supportedFormats.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var destinationSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination Folder")
                .font(.headline)
            
            Button(action: { 
                print("Select Destination button tapped")
                showDestinationPicker = true 
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(selectedDestinationURL?.lastPathComponent ?? "Select Destination")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Select destination folder")
        }
    }
    
    private var extractionButton: some View {
        Button(action: extractArchive) {
            if extractor.isExtracting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Extract Archive")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedArchiveURL == nil || selectedDestinationURL == nil || extractor.isExtracting)
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            if extractor.isExtracting {
                ProgressView(value: extractor.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Extracting...")
                    .font(.caption)
            }
            
            if extractionCompleted {
                Label("Extraction completed successfully!", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }
            
            if let error = extractor.extractionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
    }
    
    private func handleDestinationSelection(result: Result<[URL], Error>) {
        print("Folder importer completed with result")
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedDestinationURL = url
                extractionCompleted = false
                print("Selected destination: \(url.path)")
            }
        case .failure(let error):
            alertMessage = "Failed to select destination: \(error.localizedDescription)"
            showAlert = true
            print("Folder selection error: \(error.localizedDescription)")
        }
    }
    
    private func extractArchive() {
        guard let archiveURL = selectedArchiveURL,
              let destinationURL = selectedDestinationURL else {
            alertMessage = "Please select both archive file and destination folder"
            showAlert = true
            return
        }
        
        let format = ArchiveFormat.detect(from: archiveURL)
        
        Task {
            do {
                try await extractor.extractArchive(
                    from: archiveURL,
                    to: destinationURL,
                    format: format
                )
                
                await MainActor.run {
                    extractionCompleted = true
                    alertMessage = "Archive extracted successfully!"
                    showAlert = true
                }
            } catch ExtractionError.unsupportedFormat {
                await MainActor.run {
                    alertMessage = "Unsupported archive format"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Extraction failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func autoSelectDestination() {
        // Auto-select the same directory as the archive for convenience
        if let archiveURL = selectedArchiveURL {
            selectedDestinationURL = archiveURL.deletingLastPathComponent()
            print("📂 Auto-selected destination: \(selectedDestinationURL?.path ?? "none")")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
