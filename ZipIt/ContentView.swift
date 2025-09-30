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
        
        var allowedTypes: [UTType] = [.zip]
        
        // Safely create UTTypes for file extensions
        if let tarType = UTType(filenameExtension: "tar") {
            allowedTypes.append(tarType)
        }
        if let gzType = UTType(filenameExtension: "gz") {
            allowedTypes.append(gzType)
        }
        if let tgzType = UTType(filenameExtension: "tgz") {
            allowedTypes.append(tgzType)
        }
        if let sevenZType = UTType(filenameExtension: "7z") {
            allowedTypes.append(sevenZType)
        }
        if let rarType = UTType(filenameExtension: "rar") {
            allowedTypes.append(rarType)
        }
        
        panel.allowedContentTypes = allowedTypes
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
    }
    
    /// Represents the state of the compression process.
    enum CompressionState: Identifiable {
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
        
        var isLoading: Bool {
            if case .loading = self {
                return true
            }
            return false
        }
    }

    // MARK: - State Properties

    /// The URL of the archive file to be extracted.
    @State private var selectedArchiveURL: URL?
    /// The URL of the destination folder for the extracted files.
    @State private var selectedDestinationURL: URL?
    /// The current state of the extraction process.
    @State private var extractionState: ExtractionState = .idle
    /// The current state of the compression process.
    @State private var compressionState: CompressionState = .idle
    /// Array of URLs for files/folders to compress
    @State private var selectedFilesToCompress: [URL] = []
    /// URL for the output archive file
    @State private var selectedOutputArchiveURL: URL?
    /// Selected format for compression
    @State private var selectedCompressionFormat: ArchiveFormat = .zip
    /// Controls which tab is currently selected (0 = Extract, 1 = Compress)
    @State private var selectedTab = 0
    /// Cached size of the selection (bytes) for UI gating
    @State private var selectionSizeBytes: Int64 = 0
    /// A boolean to control the presentation of the destination folder picker.
    @State private var showDestinationPicker = false
    /// A boolean to control the presentation of the files picker for compression.
    @State private var showFilesPicker = false
    /// A boolean to control the presentation of the output archive picker.
    @State private var showOutputPicker = false
    @State private var selectionMode: FileSelectionMode = .files
    
    enum FileSelectionMode {
        case files
        case folders
    }
    /// Controls the presentation of the alert.
    @State private var showAlert = false
    /// Controls the expansion of format info in Extract tab
    @State private var showExtractFormatInfo = false
    /// Controls the expansion of format info in Compress tab
    @State private var showCompressFormatInfo = false
    
    /// A list of supported archive file extensions.
    let supportedFormats = ["zip", "tar", "gz", "7z", "rar"]
    /// A list of supported compression formats for v1 (GZIP and 7Zip disabled, RAR extraction-only)
    let compressionFormats: [ArchiveFormat] = [.zip, .tar]
    
    /// Format guide information
    let formatInfo = """
    **ZIP** - Universal format for multiple files/folders. Best for email attachments and cross-platform compatibility.
    
    **TAR** - Unix/Linux standard for software distribution and large data transfers.
    
    **RAR** - Extraction only (Windows-based format). Can split large files into chunks.
    
    **7Z** - Maximum compression for storage. Extraction only.
    
    **GZIP** - Single file compression for large file transfers.
    """
    
    /// The main layout of the content view.
    var body: some View {
        TabView(selection: $selectedTab) {
            // Extract Tab
            extractionView
                .tabItem {
                    Image(systemName: "archivebox")
                    Text("Extract")
                }
                .tag(0)
            
            // Compress Tab
            compressionView
                .tabItem {
                    Image(systemName: "archivebox.fill")
                    Text("Compress")
                }
                .tag(1)
        }
        .onChange(of: selectedArchiveURL) {
            // Auto-select destination to same folder when a new archive is chosen
            autoSelectDestination()
        }
        // Keep output extension in sync with the selected format
        .onChange(of: selectedCompressionFormat) { _, newFormat in
            // Update output extension
            if let url = selectedOutputArchiveURL {
                let expected = extensionForFormat(newFormat)
                if url.pathExtension.lowercased() != expected {
                    let updated = url.deletingPathExtension().appendingPathExtension(expected)
                    selectedOutputArchiveURL = updated
                }
            }
        }
        // Reset/wipe state when switching between Extract and Compress
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 {
                // Arriving to Extract tab
                if extractor.isCompressing == false { resetCompressionUI() }
            } else if newTab == 1 {
                // Arriving to Compress tab
                if extractor.isExtracting == false { resetExtractionUI() }
            }
        }
        .onReceive(appState.$selectedArchiveURL) { url in
            if let url = url {
                selectedArchiveURL = url
                selectedTab = 0 // Switch to extraction tab
                // Automatically select a default destination when a file is opened.
                autoSelectDestination()
            }
        }
        .alert("ZipIt", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .fileImporter(isPresented: $showDestinationPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                selectedDestinationURL = url
                print("Destination folder selected: \(url)")
            case .failure(let error):
                print("Error selecting destination: \(error)")
            }
        }
        .fileImporter(isPresented: $showFilesPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                // Single-selection policy: take only the first item
                selectedFilesToCompress = Array(urls.prefix(1))
                
                Task {
                    await updateSelectionSizeAndDefaultOutput()
                    // Note: Save panel will be shown when user clicks "Create Archive"
                    // This allows them to select the format first
                }
                print("Item selected for compression: \(selectedFilesToCompress.first?.path ?? "none")")
            case .failure(let error):
                print("Error selecting item: \(error)")
            }
        }
        .task {
            _ = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("ZipIt.CompressFiles"),
                object: nil,
                queue: .main
            ) { notification in
                if let filePaths = notification.userInfo?["files"] as? [String] {
                    DispatchQueue.main.async {
                        selectedFilesToCompress = filePaths.map { URL(fileURLWithPath: $0) }
                        selectedTab = 1
                        Task { await updateSelectionSizeAndDefaultOutput() }
                    }
                }
            }
        }
    }
    
    // MARK: - Extraction View
    
    private var extractionView: some View {
        VStack(spacing: 20) {
            headerSection
            archiveSelectionSection
            destinationSelectionSection
            extractionButton
            extractionProgressSection
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Compression View
    
    private var compressionView: some View {
        VStack(spacing: 20) {
            compressionHeaderSection
            filesSelectionSection
            formatSelectionSection
            outputSelectionSection
            compressionButton
            compressionProgressSection
            
            Spacer()
        }
        .padding()
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
            HStack {
                Text("Archive File")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showExtractFormatInfo = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Format information")
            }
            
            ArchiveFilePicker(selectedURL: $selectedArchiveURL)
                .accessibilityLabel("Select archive file")
            
            Text("Supported formats: \(supportedFormats.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .alert("Archive Format Guide", isPresented: $showExtractFormatInfo) {
            Button("OK") { }
        } message: {
            Text(formatInfo)
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
            .disabled(selectedArchiveURL == nil || ArchiveFormat.detect(from: selectedArchiveURL!) == .unknown)
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
    private var extractionProgressSection: some View {
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
            showAlert = true
            print("Folder selection error: \(error.localizedDescription)")
        }
    }
    
    /// Initiates the archive extraction process.
    private func extractArchive() {
        guard let archiveURL = selectedArchiveURL,
              let destinationURL = selectedDestinationURL else {
            extractionState = .failure("Please select both an archive file and a destination folder.")
            showAlert = true
            return
        }
        
        let format = ArchiveFormat.detect(from: archiveURL)
        extractionState = .loading
        
        Task {
            do {
                try await extractor.extractArchive(
                    from: archiveURL,
                    to: destinationURL,
                    format: format
                )

                await MainActor.run {
                    extractionState = .success("Archive extracted successfully!")
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    extractionState = .failure(error.localizedDescription)
                    showAlert = true
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
    
    // MARK: - Compression UI Sections
    
    /// The header section for the compression view
    private var compressionHeaderSection: some View {
        VStack {
            if let nsImage = NSImage(named: "AppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            } else {
                // Fallback icon if the AppIcon is not found.
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            Text("Create Archive")
                .font(.largeTitle.bold())
            Text("Compress files and folders")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    
    /// The section for selecting a single file or folder to compress (single-selection policy)
    private var filesSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Item to Compress")
                .font(.headline)

            HStack {
                Button("Select File or Folder…") {
                    showFilesPicker = true
                }
                .buttonStyle(.bordered)
            }

            if let first = selectedFilesToCompress.first {
                Text("Selected: \(first.lastPathComponent) • \(formatBytes(selectionSizeBytes))")
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
    }
    
    /// The section for selecting compression format
    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Archive Format")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showCompressFormatInfo = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Format information")
            }
            
            Picker("Format", selection: $selectedCompressionFormat) {
                ForEach(compressionFormats, id: \.self) { format in
                    Text(displayName(for: format)).tag(format)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .alert("Compression Format Guide", isPresented: $showCompressFormatInfo) {
            Button("OK") { }
        } message: {
            Text("**ZIP** - Best for email and cross-platform sharing. Universal support.\n\n**TAR** - Unix/Linux standard for software distribution.")
        }
    }
    
    /// The section for selecting output location (disabled in v1: always same-folder)
    private var outputSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Location")
                .font(.headline)
            
            if let outputURL = selectedOutputArchiveURL {
                // Show the folder location
                HStack {
                    Image(systemName: "folder")
                    Text(outputURL.deletingLastPathComponent().lastPathComponent)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.secondary)
                
                // Show the archive filename separately
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                    Text(outputURL.lastPathComponent)
                }
                .frame(maxWidth: .infinity)
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
                HStack {
                    Image(systemName: "folder")
                    Text("Auto (same folder as selection)")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.secondary)
            }
            
            Text("Archive will be created in the same folder as the selected item.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    /// The compression button
    private var compressionButton: some View {
        Button(action: compressFiles) {
            HStack {
                if case .loading = compressionState {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Image(systemName: "archivebox.fill")
                Text("Create Archive")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
            .disabled(selectedFilesToCompress.isEmpty || selectedOutputArchiveURL == nil || extractor.isCompressing)
            .help("Archive will be created in the same folder as the selected item")
    }
    
    /// The section that displays the progress of the compression.
    private var compressionProgressSection: some View {
        VStack(spacing: 12) {
            if case .loading = compressionState {
                ProgressView(value: extractor.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Creating archive...")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Progress: \(Int(extractor.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minHeight: compressionState.isLoading ? 60 : 0)
    }
    
    // MARK: - Helper Methods
    
    /// Returns preferred file extension for the selected format
    private var overLimitForRAR: Bool { selectionSizeBytes > (1 << 30) }
    
    private func extensionForFormat(_ format: ArchiveFormat) -> String {
        switch format {
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gz"
        case .sevenZip: return "7z"
        case .rar, .unknown: return "rar"
        }
    }

    private func displayName(for format: ArchiveFormat) -> String {
        switch format {
        case .sevenZip: return "7Zip"
        case .gzip: return "GZIP"
        default: return format.rawValue.uppercased()
        }
    }
    
    /// Resets the extraction UI state
    private func resetExtractionUI() {
        selectedArchiveURL = nil
        selectedDestinationURL = nil
        extractionState = .idle
        extractor.progress = 0.0
        showAlert = false
    }
    
    /// Resets the compression UI state
    private func resetCompressionUI() {
        selectedFilesToCompress.removeAll()
        selectedOutputArchiveURL = nil
        compressionState = .idle
        extractor.progress = 0.0
        showAlert = false
    }
    
    /// Gets the alert message based on the current states
    private var alertMessage: String {
        switch extractionState {
        case .success(let message): return message
        case .failure(let message): return message
        default:
            switch compressionState {
            case .success(let message): return message
            case .failure(let message): return message
            default: return ""
            }
        }
    }
    
    /// Compute total size of selection and set/refresh a default output URL when needed
    private func updateSelectionSizeAndDefaultOutput() async {
        let size = await computeTotalSize(of: selectedFilesToCompress)
        await MainActor.run {
            self.selectionSizeBytes = size
            // Always compute default output next to the single selected item
            if let first = self.selectedFilesToCompress.first {
                let ext = self.extensionForFormat(self.selectedCompressionFormat)
                
                // Get the base name (without extension for files, or folder name)
                var baseName = first.lastPathComponent
                
                // If it's a file, remove its extension
                if !first.hasDirectoryPath && baseName.contains(".") {
                    baseName = first.deletingPathExtension().lastPathComponent
                }
                
                // Create archive in the same folder as the source
                let parentFolder = first.deletingLastPathComponent()
                let archiveName = "\(baseName).\(ext)"
                let url = parentFolder.appendingPathComponent(archiveName)
                
                print("📁 Source: \(first.path)")
                print("📦 Output will be: \(url.path)")
                
                self.selectedOutputArchiveURL = url
            } else {
                self.selectedOutputArchiveURL = nil
            }
        }
    }
    
    /// Chooses the output archive location without creating a file yet
    private func chooseOutputLocation() {
        let ext = extensionForFormat(selectedCompressionFormat)
        let defaultBaseName: String = {
            if let first = selectedFilesToCompress.first { return first.deletingPathExtension().lastPathComponent }
            return "Archive"
        }()
        let panel = NSSavePanel()
        if let t = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [t]
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(defaultBaseName).\(ext)"
        if let dir = selectedFilesToCompress.first?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        if panel.runModal() == .OK, let url = panel.url {
            selectedOutputArchiveURL = url
            NSLog("📦 Save panel selected URL: %@", url.path)
            NSLog("📦 Parent folder: %@", url.deletingLastPathComponent().path)
            NSLog("📦 Archive filename: %@", url.lastPathComponent)
        } else {
            NSLog("❌ Save panel cancelled")
        }
    }
    
    /// Compute total size of URLs (files and directories) off the main thread
    private func computeTotalSize(of urls: [URL]) async -> Int64 {
        return await withTaskGroup(of: Int64.self) { group -> Int64 in
            for url in urls {
                group.addTask { sizeOfURL(url) }
            }
            var total: Int64 = 0
            for await part in group { total += part }
            return total
        }
    }
    
    nonisolated private func sizeOfURL(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if url.hasDirectoryPath {
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        let s = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                        total += s
                    }
                }
            }
        } else {
            total = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        return total
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
    
    /// Performs the compression operation
    private func compressFiles() {
        guard !selectedFilesToCompress.isEmpty,
              let outputURL = selectedOutputArchiveURL else {
            compressionState = .failure("Please select a file or folder to compress.")
            showAlert = true
            return
        }
        
        compressionState = .loading
        
        Task {
            do {
                try await extractor.compressFiles(
                    from: selectedFilesToCompress,
                    to: outputURL,
                    format: selectedCompressionFormat
                )

                await MainActor.run {
                    compressionState = .success("Archive created successfully!")
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    compressionState = .failure(error.localizedDescription)
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Helper Document for FileSaver

struct EmptyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    
    var data = Data()
    
    init(data: Data = Data()) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
