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
        }
    }
}

struct MultiFilePicker: View {
    @Binding var selectedURLs: [URL]

    var body: some View {
        Button(action: selectFiles) {
            HStack {
                Image(systemName: "doc.badge.plus")
                if selectedURLs.isEmpty {
                    Text("Select Files or Folders to Compress")
                } else {
                    Text("\(selectedURLs.count) items selected")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            selectedURLs = panel.urls
        }
    }
}

struct ContentView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case extract = "Extract"
        case compress = "Compress"
        var id: Self { self }
    }

    @StateObject private var extractor = ArchiveExtractor()
    @StateObject private var compressor = ArchiveCompressor()
    @EnvironmentObject var appState: AppState

    @State private var currentMode: Mode = .extract

    // Extraction state
    @State private var selectedArchiveURL: URL?
    @State private var extractionCompleted = false

    // Compression state
    @State private var selectedFilesToCompress: [URL] = []
    @State private var compressionCompleted = false

    // Common state
    @State private var selectedDestinationURL: URL?
    @State private var showDestinationPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    let supportedFormats = ["zip", "tar", "gz", "7z", "rar"]
    
    private var archiveTypes: [UType] {
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

            Picker("Mode", selection: $currentMode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if currentMode == .extract {
                extractionView
            } else {
                compressionView
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 350)
        .fileImporter(
            isPresented: $showDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleDestinationSelection
        )
        .alert("Status", isPresented: $showAlert) {
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
                currentMode = .extract
                selectedArchiveURL = url
                extractionCompleted = false
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
                Image(systemName: "archivebox")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            Text("ZipIt")
                .font(.largeTitle.bold())
            Text(currentMode == .extract ? "Simple Archive Extractor" : "Simple Archive Compressor")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var extractionView: some View {
        VStack(spacing: 20) {
            archiveSelectionSection
            destinationSelectionSection
            extractionButton
            progressSection
        }
    }

    private var compressionView: some View {
        VStack(spacing: 20) {
            compressionSourceSection
            destinationSelectionSection
            compressionButton
            progressSection
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
    
    private var compressionSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files to Compress")
                .font(.headline)

            MultiFilePicker(selectedURLs: $selectedFilesToCompress)
                .accessibilityLabel("Select files and folders to compress")
        }
    }

    private var destinationSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination Folder")
                .font(.headline)
            
            Button(action: {
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
    
    private var compressionButton: some View {
        Button(action: compressFiles) {
            if compressor.isCompressing {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Compress Files")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedFilesToCompress.isEmpty || selectedDestinationURL == nil || compressor.isCompressing)
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            if extractor.isExtracting {
                ProgressView(value: extractor.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Extracting...")
                    .font(.caption)
            } else if compressor.isCompressing {
                ProgressView(value: compressor.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Compressing...")
                    .font(.caption)
            }
            
            if extractionCompleted {
                Label("Extraction completed successfully!", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            } else if compressionCompleted {
                Label("Compression completed successfully!", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }
            
            if let error = extractor.extractionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            } else if let error = compressor.compressionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
    }
    
    private func handleDestinationSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedDestinationURL = url
                extractionCompleted = false
                compressionCompleted = false
            }
        case .failure(let error):
            alertMessage = "Failed to select destination: \(error.localizedDescription)"
            showAlert = true
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
            } catch {
                await MainActor.run {
                    alertMessage = "Extraction failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func compressFiles() {
        guard !selectedFilesToCompress.isEmpty,
              let destinationURL = selectedDestinationURL else {
            alertMessage = "Please select files to compress and a destination folder"
            showAlert = true
            return
        }

        Task {
            do {
                try await compressor.compressFiles(
                    from: selectedFilesToCompress,
                    to: destinationURL,
                    fileName: "Archive"
                )

                await MainActor.run {
                    compressionCompleted = true
                    alertMessage = "Files compressed successfully!"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Compression failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func autoSelectDestination() {
        if let archiveURL = selectedArchiveURL {
            selectedDestinationURL = archiveURL.deletingLastPathComponent()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
