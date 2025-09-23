//
//  ContentView.swift
//  ZipIt
//
//  Created by Douglas Ek on 2025-09-16.
//
//  This file defines the main user interface of the ZipIt application using SwiftUI.
//  It allows users to select an archive file, choose a destination folder, and
//  initiate the extraction process.
//

import SwiftUI
import UniformTypeIdentifiers

/// A reusable view component for selecting an archive file.
/// This button opens the system's file picker and updates the selected URL.
struct ArchiveFilePicker: View {
    /// A binding to the URL of the selected archive file.
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
    
    /// Opens the `NSOpenPanel` to allow the user to select an archive file.
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

/// The main view of the application, containing all the UI elements for file extraction.
struct ContentView: View {
    /// The `ArchiveExtractor` instance responsible for the extraction logic.
    @StateObject private var extractor = ArchiveExtractor()
    /// The shared application state, used to receive the URL of a file opened with the app.
    @EnvironmentObject var appState: AppState

    /// Represents the state of the extraction process.
    enum ExtractionState: Identifiable {
        case idle
        case loading
        case success(String)
        case failure(String)

        var id: String {
            switch self {
            case .idle: return "idle"
            case .loading: return "loading"
            case .success(let message): return "success-\(message)"
            case .failure(let message): return "failure-\(message)"
            }
        }

        struct AlertItem: Identifiable {
            var id = UUID()
            var title: String
            var message: String
        }

        var alertItem: AlertItem? {
            switch self {
            case .success(let message):
                return AlertItem(title: "Success", message: message)
            case .failure(let message):
                return AlertItem(title: "Error", message: message)
            default:
                return nil
            }
        }
    }

    // MARK: - State Properties

    /// The URL of the archive file to be extracted.
    @State private var selectedArchiveURL: URL?
    /// The URL of the destination folder for the extracted files.
    @State private var selectedDestinationURL: URL?
    /// The current state of the extraction process.
    @State private var extractionState: ExtractionState = .idle
    /// A boolean to control the presentation of the destination folder picker.
    @State private var showDestinationPicker = false
    
    /// A list of supported archive file extensions.
    let supportedFormats = ["zip", "tar", "gz", "7z", "rar"]
    
    /// The main layout of the content view.
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
        // File importer for selecting the destination folder.
        .fileImporter(
            isPresented: $showDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleDestinationSelection
        )
        // Alert for showing extraction status and errors.
        .alert(item: $extractionState.alertItem) { alertItem in
            Alert(title: Text(alertItem.title), message: Text(alertItem.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            print("ContentView appeared")
        }
        // This receiver handles files that are opened with the app.
        .onReceive(appState.$selectedArchiveURL) { url in
            if let url = url {
                print("📁 Auto-loading file: \(url.lastPathComponent)")
                selectedArchiveURL = url
                extractionState = .idle
                
                // Automatically select a default destination when a file is opened.
                autoSelectDestination()
            }
        }
    }
    
    // MARK: - UI Sections

    /// The header section of the view, displaying the app icon and title.
    private var headerSection: some View {
        VStack {
            if let nsImage = NSImage(named: "AppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            } else {
                // Fallback icon if the AppIcon is not found.
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
    
    /// The section for selecting the archive file.
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
    
    /// The section for selecting the destination folder.
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
    
    /// The button that initiates the file extraction.
    private var extractionButton: some View {
        Button(action: extractArchive) {
            if case .loading = extractionState {
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
    
    /// The section that displays the progress of the extraction.
    private var progressSection: some View {
        VStack(spacing: 12) {
            if case .loading = extractionState {
                ProgressView(value: extractor.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Extracting...")
                    .font(.caption)
            }
            
            if case .success(let message) = extractionState {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }
            
            if case .failure(let message) = extractionState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Helper Functions

    /// Handles the result of the destination folder selection.
    private func handleDestinationSelection(result: Result<[URL], Error>) {
        print("Folder importer completed with result")
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedDestinationURL = url
                extractionState = .idle
                print("Selected destination: \(url.path)")
            }
        case .failure(let error):
            extractionState = .failure("Failed to select destination: \(error.localizedDescription)")
            print("Folder selection error: \(error.localizedDescription)")
        }
    }
    
    /// Initiates the archive extraction process.
    private func extractArchive() {
        guard let archiveURL = selectedArchiveURL,
              let destinationURL = selectedDestinationURL else {
            extractionState = .failure("Please select both an archive file and a destination folder.")
            return
        }
        
        let format = ArchiveFormat.detect(from: archiveURL)
        extractionState = .loading
        
        Task {
            await extractor.extractArchive(
                from: archiveURL,
                to: destinationURL,
                format: format
            )

            await MainActor.run {
                if let error = extractor.extractionError {
                    extractionState = .failure(error)
                } else {
                    extractionState = .success("Archive extracted successfully!")
                }
            }
        }
    }
    
    /// Automatically selects a default destination folder.
    /// This function will be updated to use the Downloads folder.
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
