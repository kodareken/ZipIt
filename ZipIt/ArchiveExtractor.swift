import Foundation
import Combine
import Zip
import SWCompression
import Unrar

enum ArchiveFormat: String {
    case zip
    case tar
    case gzip
    case sevenZip
    case rar  // Extraction only - compression requires RARLAB license
    case unknown
    
    static func detect(from url: URL) -> ArchiveFormat {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "zip": return .zip
        case "tar": return .tar
        case "gz", "tgz": return .gzip
        case "7z": return .sevenZip
        case "rar": return .rar
        default: return .unknown
        }
    }
}

enum ArchiveError: LocalizedError {
    case unsupportedFormat
    case extractionFailed(String)
    case compressionFailed(String)
    case invalidDestination
    case corruptedArchive
    case passwordRequired
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported archive format"
        case .extractionFailed(let details): return "Extraction failed: \(details)"
        case .compressionFailed(let details): return "Compression failed: \(details)"
        case .invalidDestination: return "Invalid destination folder"
        case .corruptedArchive: return "Archive appears to be corrupted"
        case .passwordRequired: return "This archive requires a password"
        case .unknownError: return "An unknown error occurred"
        }
    }
}

@MainActor
class ArchiveExtractor: ObservableObject {
    @Published var isExtracting = false
    @Published var isCompressing = false
    @Published var progress: Double = 0.0
    @Published var extractionError: String?
    @Published var compressionError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    func extractArchive(from sourceURL: URL, to destinationURL: URL, format: ArchiveFormat) async throws {
        guard format != .unknown else {
            throw ArchiveError.unsupportedFormat
        }
        
        await MainActor.run {
            isExtracting = true
            progress = 0.0
            extractionError = nil
        }
        
        do {
            switch format {
            case .zip:
                try await extractZip(from: sourceURL, to: destinationURL)
            case .tar, .gzip:
                try await extractTarOrGzip(from: sourceURL, to: destinationURL, format: format)
            case .sevenZip:
                try await extractSevenZip(from: sourceURL, to: destinationURL)
            case .rar:
                try await extractRAR(from: sourceURL, to: destinationURL)
            case .unknown:
                throw ArchiveError.unsupportedFormat
            }
            
            await updateProgress(1.0)
            
            // Reset extraction state after completion
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isExtracting = false
                    self.progress = 0.0
                }
            }
            
        } catch {
            await MainActor.run {
                extractionError = error.localizedDescription
                isExtracting = false
                progress = 0.0
            }
            throw error
        }
    }
    
    func compressFiles(from sourceURLs: [URL], to destinationURL: URL, format: ArchiveFormat) async throws {
        guard format != .unknown else {
            throw ArchiveError.unsupportedFormat
        }
        // Enforce single-selection policy
        guard sourceURLs.count == 1, let sourceURL = sourceURLs.first else {
            throw ArchiveError.compressionFailed("Select exactly one file or one folder. To compress multiple items, put them into a folder first.")
        }
        
        await MainActor.run {
            isCompressing = true
            progress = 0.0
            compressionError = nil
        }
        
        do {
            // Preflight checks before we begin (space, permissions, same volume)
            let totalBytes = try await self.computeTotalBytes(of: [sourceURL])
            try preflightCompression(singleSource: sourceURL, destinationURL: destinationURL, format: format, totalBytes: totalBytes)
            
            NSLog("✅ Preflight passed - starting \(format.rawValue.uppercased()) compression")
            NSLog("   Total bytes to compress: %lld", totalBytes)
            
            switch format {
            case .zip:
                try await compressZip(from: [sourceURL], to: destinationURL)
            case .tar:
                try await compressTar(from: [sourceURL], to: destinationURL)
            case .gzip:
                try await compressGzip(from: [sourceURL], to: destinationURL)
            case .sevenZip:
                try await compressSevenZip(from: [sourceURL], to: destinationURL)
            case .rar:
                throw ArchiveError.compressionFailed("RAR compression is not supported (requires RARLAB license). Use ZIP, TAR, or 7Z instead.")
            case .unknown:
                throw ArchiveError.unsupportedFormat
            }
            
            await updateProgress(1.0)
            
            // Reset compression state after completion
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isCompressing = false
                    self.progress = 0.0
                }
            }
            
        } catch {
            NSLog("❌ Compression ERROR caught: %@", error.localizedDescription)
            NSLog("❌ Error type: %@", String(describing: type(of: error)))
            if let archiveError = error as? ArchiveError {
                NSLog("❌ ArchiveError details: %@", String(describing: archiveError))
            }
            
            await MainActor.run {
                compressionError = error.localizedDescription
                isCompressing = false
                progress = 0.0
            }
            throw error
        }
    }
    
    private func extractZip(from sourceURL: URL, to destinationURL: URL) async throws {
        do {
            try Zip.unzipFile(
                sourceURL,
                destination: destinationURL,
                overwrite: true,
                password: nil,
                progress: { progress in
                    Task { @MainActor in
                        self.progress = progress
                    }
                }
            )
            // Cleanup common macOS metadata folders/files after extraction
            try cleanupAppleMetadata(in: destinationURL)
        } catch {
            throw ArchiveError.extractionFailed("ZIP extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func extractTarOrGzip(from sourceURL: URL, to destinationURL: URL, format: ArchiveFormat) async throws {
        do {
            var data = try Data(contentsOf: sourceURL)
            
            // Handle GZIP compression if needed
            if format == .gzip {
                data = try GzipArchive.unarchive(archive: data)
                
                // Check if decompressed data is a TAR archive
                if let _ = try? TarContainer.open(container: data) {
                    // It's a .tar.gz - extract all TAR entries
                    try await extractTarEntries(from: data, to: destinationURL)
                    return
                } else {
                    // Standalone .gz file - write single decompressed file
                    try await extractStandaloneGzipFile(data: data, sourceURL: sourceURL, to: destinationURL)
                    return
                }
            }
            
            // Extract TAR archive using SWCompression
            let entries = try TarContainer.open(container: data)
            
            for (index, entry) in entries.enumerated() {
                guard let fileData = entry.data else {
                    continue // Skip directories or empty entries
                }
                
                let fileURL = destinationURL.appendingPathComponent(entry.info.name)
                
                // Create directory structure if needed
                let directoryURL = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                
                try fileData.write(to: fileURL)
                
                let currentProgress = Double(index + 1) / Double(entries.count)
                await updateProgress(currentProgress)
            }
            // Cleanup metadata noise (__MACOSX, ._ files)
            try cleanupAppleMetadata(in: destinationURL)
        } catch {
            throw ArchiveError.extractionFailed("\(format.rawValue.uppercased()) extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func extractSevenZip(from sourceURL: URL, to destinationURL: URL) async throws {
        do {
            let data = try Data(contentsOf: sourceURL)
            let entries = try SevenZipContainer.open(container: data)
            
            for (index, entry) in entries.enumerated() {
                guard let fileData = entry.data else {
                    continue // Skip directories or empty entries
                }
                
                let fileURL = destinationURL.appendingPathComponent(entry.info.name)
                
                // Create directory structure if needed
                let directoryURL = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                
                try fileData.write(to: fileURL)
                
                let currentProgress = Double(index + 1) / Double(entries.count)
                await updateProgress(currentProgress)
            }
            // Cleanup metadata noise
            try cleanupAppleMetadata(in: destinationURL)
        } catch {
            throw ArchiveError.extractionFailed("7-Zip extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func extractRAR(from sourceURL: URL, to destinationURL: URL) async throws {
        do {
            let archive = try Archive(path: sourceURL.path)
            let entries = try archive.entries()
            
            for (index, entry) in entries.enumerated() {
                // Skip directories
                guard !entry.directory else {
                    continue
                }
                
                // Extract file data to memory
                let fileData = try archive.extract(entry)
                
                // Create the full file path
                let fileURL = destinationURL.appendingPathComponent(entry.fileName)
                
                // Create directory structure if needed
                let directoryURL = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                
                // Write the extracted data to file
                try fileData.write(to: fileURL)
                
                // Update progress
                let currentProgress = Double(index + 1) / Double(entries.count)
                await updateProgress(currentProgress)
            }
            // Cleanup metadata noise
            try cleanupAppleMetadata(in: destinationURL)
        } catch let error as UnrarError {
            switch error {
            case .missingPassword:
                throw ArchiveError.passwordRequired
            case .badArchive:
                throw ArchiveError.corruptedArchive
            case .badData:
                throw ArchiveError.corruptedArchive
            default:
                throw ArchiveError.extractionFailed("RAR extraction failed: \(error.localizedDescription)")
            }
        } catch {
            throw ArchiveError.extractionFailed("RAR extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func updateProgress(_ value: Double) async {
        await MainActor.run {
            progress = value
        }
    }
    
    /// Extract TAR entries from decompressed data
    private func extractTarEntries(from data: Data, to destinationURL: URL) async throws {
        let entries = try TarContainer.open(container: data)
        
        for (index, entry) in entries.enumerated() {
            guard let fileData = entry.data else { continue }
            
            let fileURL = destinationURL.appendingPathComponent(entry.info.name)
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileData.write(to: fileURL)
            
            let currentProgress = Double(index + 1) / Double(entries.count)
            await updateProgress(currentProgress)
        }
        
        try cleanupAppleMetadata(in: destinationURL)
    }
    
    /// Extract standalone GZIP file (not a .tar.gz)
    private func extractStandaloneGzipFile(data: Data, sourceURL: URL, to destinationURL: URL) async throws {
        // GZIP doesn't store original filename - derive from .gz filename
        var fileName = sourceURL.deletingPathExtension().lastPathComponent
        
        // If filename has no extension after removing .gz, detect from content
        if !fileName.contains(".") {
            let detectedExt = detectFileType(from: data) ?? "txt"
            fileName = "\(fileName).\(detectedExt)"
        }
        
        let fileURL = destinationURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        await updateProgress(1.0)
    }
    
    // MARK: - Compression Methods
    
    private func compressZip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        do {
            var filePaths: [String] = []
            // Expand the single source into file paths
            for (index, sourceURL) in sourceURLs.enumerated() {
                if sourceURL.hasDirectoryPath {
                    let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey])
                    while let fileURL = enumerator?.nextObject() as? URL {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            filePaths.append(fileURL.path)
                        }
                    }
                } else {
                    filePaths.append(sourceURL.path)
                }
                let currentProgress = Double(index + 1) / Double(sourceURLs.count) * 0.4
                await updateProgress(currentProgress)
            }

            // Write to temp file in same directory (atomic finalize)
            // Keep .zip extension last so the verifier recognizes it
            let baseName = destinationURL.deletingPathExtension().lastPathComponent
            let tempURL = destinationURL.deletingLastPathComponent().appendingPathComponent("\(baseName).tmp.zip")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }

            let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
            try Zip.zipFiles(paths: fileURLs, zipFilePath: tempURL, password: nil) { progress in
                Task { @MainActor in
                    // Map 40%..90% to ZIP progress; leave last 10% for verify and finalize
                    self.progress = 0.4 + (progress * 0.5)
                }
            }

            // Light verification: try to parse by unzipping to a throwaway temp dir, then delete
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("zipit_zip_verify_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            do {
                try Zip.unzipFile(tempURL, destination: tmpDir, overwrite: true, password: nil)
            } catch {
                // Cleanup and fail
                try? FileManager.default.removeItem(at: tmpDir)
                try? FileManager.default.removeItem(at: tempURL)
                throw ArchiveError.compressionFailed("ZIP verification failed: \(error.localizedDescription)")
            }
            // Cleanup extracted verification data
            try? FileManager.default.removeItem(at: tmpDir)

            // Finalize atomically
            try finalizeTempArchive(tempURL: tempURL, finalURL: destinationURL)
            await updateProgress(1.0)
        } catch {
            throw ArchiveError.compressionFailed("ZIP compression failed: \(error.localizedDescription)")
        }
    }
    
    private func compressTar(from sourceURLs: [URL], to destinationURL: URL) async throws {
        do {
            var entries: [TarEntry] = []
            // Collect all files to compress
            for (index, sourceURL) in sourceURLs.enumerated() {
                if sourceURL.hasDirectoryPath {
                    // Add all files in directory recursively
                    let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey])
                    while let fileURL = enumerator?.nextObject() as? URL {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            // Relative path inside tar should be rooted at the selected folder name
                            let relativeRoot = sourceURL.deletingLastPathComponent().path + "/"
                            let relativePath = fileURL.path.replacingOccurrences(of: relativeRoot, with: "")
                            let fileData = try Data(contentsOf: fileURL)
                            let entry = TarEntry(info: TarEntryInfo(name: relativePath, type: .regular), data: fileData)
                            entries.append(entry)
                        }
                    }
                } else {
                    let fileData = try Data(contentsOf: sourceURL)
                    let entry = TarEntry(info: TarEntryInfo(name: sourceURL.lastPathComponent, type: .regular), data: fileData)
                    entries.append(entry)
                }
                let currentProgress = Double(index + 1) / Double(sourceURLs.count) * 0.7
                await updateProgress(currentProgress)
            }
            // Create TAR archive to temp and verify before finalizing
            let tarData = TarContainer.create(from: entries)
            let baseName = destinationURL.deletingPathExtension().lastPathComponent
            let tempURL = destinationURL.deletingLastPathComponent().appendingPathComponent("\(baseName).tmp.tar")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            try tarData.write(to: tempURL)

            // Light verification: try to parse TAR entries from the written file
            do {
                let written = try Data(contentsOf: tempURL)
                let _ = try TarContainer.open(container: written)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw ArchiveError.compressionFailed("TAR verification failed: \(error.localizedDescription)")
            }

            try finalizeTempArchive(tempURL: tempURL, finalURL: destinationURL)
            await updateProgress(1.0)
        } catch {
            throw ArchiveError.compressionFailed("TAR compression failed: \(error.localizedDescription)")
        }
    }
    
    private func compressGzip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        // For now, GZIP compression is not fully supported - throw an error
        throw ArchiveError.compressionFailed("GZIP compression is not currently supported")
    }
    
    
    private nonisolated func computeTotalBytes(of urls: [URL]) async throws -> Int64 {
        return try await withThrowingTaskGroup(of: Int64.self) { group in
            for url in urls {
                group.addTask { try self.sizeOfURL(url) }
            }
            var total: Int64 = 0
            for try await part in group { total += part }
            return total
        }
    }
    
    private nonisolated func sizeOfURL(_ url: URL) throws -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if url.hasDirectoryPath {
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    let rv = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if rv.isRegularFile == true {
                        total += Int64(rv.fileSize ?? 0)
                    }
                }
            }
        } else {
            let rv = try url.resourceValues(forKeys: [.fileSizeKey])
            total = Int64(rv.fileSize ?? 0)
        }
        return total
    }
    
    
    private func compressSevenZip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        // For now, 7Z compression is not fully supported - throw an error  
        throw ArchiveError.compressionFailed("7Z compression is not currently supported")
    }
    // Atomically finalize temp file into final location
    private func finalizeTempArchive(tempURL: URL, finalURL: URL) throws {
        let fm = FileManager.default
        // If final exists, remove it to avoid moveItem failing; collision policy handled earlier in naming
        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: tempURL, to: finalURL)
    }

    // Remove __MACOSX folders and AppleDouble files (._*) recursively after extraction
    private func cleanupAppleMetadata(in directory: URL) throws {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == "__MACOSX" {
                    try? fm.removeItem(at: url)
                    enumerator.skipDescendants()
                    continue
                }
                if name.hasPrefix("._") {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    
    // Detect file type from magic bytes and content patterns (for GZIP extracted files)
    private func detectFileType(from data: Data) -> String? {
        guard data.count >= 4 else { return "txt" } // Very small files default to text
        
        let bytes = data.prefix(12) // Check first 12 bytes for better detection
        
        // Check binary file signatures first (magic bytes)
        // Images
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        } else if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        } else if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        } else if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && bytes.count >= 12 && 
                  Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { // RIFF...WEBP
            return "webp"
        } else if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "tiff"
        } else if bytes.starts(with: [0x42, 0x4D]) {
            return "bmp"
        } else if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) {
            return "ico"
        }
        // Documents & Archives
        else if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return "pdf"
        } else if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return "zip"
        } else if bytes.starts(with: [0x1F, 0x8B]) {
            return "gz"
        } else if bytes.starts(with: [0x42, 0x5A, 0x68]) {
            return "bz2"
        } else if bytes.starts(with: [0x52, 0x61, 0x72, 0x21]) {
            return "rar"
        } else if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF]) {
            return "7z"
        } else if bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            return "xz"
        }
        
        // Check text-based formats by content (XML, HTML, SVG, JSON, etc.)
        if let textContent = String(data: data.prefix(min(1024, data.count)), encoding: .utf8) {
            let trimmed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for XML-based formats
            if trimmed.hasPrefix("<?xml") {
                // Could be generic XML or SVG
                if textContent.lowercased().contains("<svg") {
                    return "svg"
                }
                return "xml"
            }
            
            // Check for SVG without XML declaration
            if trimmed.hasPrefix("<svg") || trimmed.hasPrefix("<!DOCTYPE svg") {
                return "svg"
            }
            
            // Check for HTML
            if trimmed.hasPrefix("<!DOCTYPE html") || trimmed.hasPrefix("<html") {
                return "html"
            }
            
            // Check for JSON
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && 
               (textContent.contains("\":") || textContent.contains("\",")) {
                return "json"
            }
            
            // Check for CSS
            if textContent.contains("{") && textContent.contains("}") && 
               (textContent.contains(":") && textContent.contains(";")) {
                // Simple heuristic: looks like CSS
                let hasSelectors = textContent.range(of: #"[.#a-zA-Z][a-zA-Z0-9-_]*\s*\{"#, options: .regularExpression) != nil
                if hasSelectors {
                    return "css"
                }
            }
            
            // Check for Markdown
            if trimmed.hasPrefix("#") || textContent.contains("##") || textContent.contains("```") {
                return "md"
            }
            
            // Check for shell scripts
            if trimmed.hasPrefix("#!/") {
                if textContent.contains("/bash") || textContent.contains("/sh") {
                    return "sh"
                } else if textContent.contains("/python") {
                    return "py"
                } else if textContent.contains("/ruby") {
                    return "rb"
                }
            }
            
            // Valid UTF-8 text but no specific format detected
            return "txt"
        }
        
        // Last resort: check if data looks like printable text
        // Count printable ASCII characters (32-126) and common whitespace
        let printableCount = data.prefix(512).filter { byte in
            (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13
        }.count
        
        let printableRatio = Double(printableCount) / Double(min(512, data.count))
        
        // If >70% printable, treat as text; otherwise binary
        if printableRatio > 0.7 {
            return "txt"
        }
        
        // Unknown binary data - default to generic .bin
        // User can rename if they know the actual type
        return "bin"
    }

    // Basic preflight checks for compression
    private func preflightCompression(singleSource sourceURL: URL, destinationURL: URL, format: ArchiveFormat, totalBytes: Int64) throws {
        // Debug logging with NSLog so it appears in Console.app
        NSLog("🔍 ZipIt Preflight check:")
        NSLog("   Source: %@", sourceURL.path)
        NSLog("   Source is directory: %@", sourceURL.hasDirectoryPath ? "YES" : "NO")
        NSLog("   Destination: %@", destinationURL.path)
        
        // Destination parent must exist and be a directory
        let destDir = destinationURL.deletingLastPathComponent()
        NSLog("   Destination parent: %@", destDir.path)
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destDir.path, isDirectory: &isDir)
        NSLog("   Parent exists: %@, isDirectory: %@", exists ? "YES" : "NO", isDir.boolValue ? "YES" : "NO")
        
        guard exists, isDir.boolValue else {
            NSLog("   ❌ FAILED: Destination folder does not exist or is not a directory")
            throw ArchiveError.compressionFailed("Destination folder does not exist or is not a directory")
        }
        
        // Note: We skip writable checks here because:
        // 1. If the user selected this location via NSSavePanel, macOS grants permission to write the file
        // 2. The sandbox prevents us from testing writability with temporary files
        // 3. If we don't have permission, the actual write will fail with a clear error
        NSLog("   ✅ Parent directory exists - trusting sandbox permissions from save panel")
        // Same-volume check (compare volume identifiers)
        let srcDir = sourceURL.hasDirectoryPath ? sourceURL : sourceURL.deletingLastPathComponent()
        let srcVol = try? srcDir.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let dstVol = try? destDir.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        // Only enforce if both volumes are identifiable and different
        if let src = srcVol as? NSObject, let dst = dstVol as? NSObject, !src.isEqual(dst) {
            throw ArchiveError.compressionFailed("Destination must be on the same volume for atomic save")
        }
        // Space estimation
        let multiplier: Double
        switch format {
        case .zip, .tar: multiplier = 1.10
        case .rar: multiplier = 1.02
        default: multiplier = 1.15
        }
        let estimate = Int64(Double(max(1, totalBytes)) * multiplier)
        let cap = try destDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available: Int64 = cap.volumeAvailableCapacityForImportantUsage ?? (cap.volumeAvailableCapacity.map { Int64($0) }) ?? 0
        if available < estimate {
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            throw ArchiveError.compressionFailed("Not enough free space. Need ~\(fmt.string(fromByteCount: estimate))")
        }
    }
}
