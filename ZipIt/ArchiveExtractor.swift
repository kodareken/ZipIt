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
    case rar
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
        
        await MainActor.run {
            isCompressing = true
            progress = 0.0
            compressionError = nil
        }
        
        do {
            switch format {
            case .zip:
                try await compressZip(from: sourceURLs, to: destinationURL)
            case .tar:
                try await compressTar(from: sourceURLs, to: destinationURL)
            case .gzip:
                try await compressGzip(from: sourceURLs, to: destinationURL)
            case .sevenZip:
                try await compressSevenZip(from: sourceURLs, to: destinationURL)
            case .rar:
                try await compressRAR(from: sourceURLs, to: destinationURL)
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
            }

            // If it's a standalone .gz file, save the decompressed data directly.
            if sourceURL.pathExtension == "gz" {
                let fileName = sourceURL.deletingPathExtension().lastPathComponent
                let fileURL = destinationURL.appendingPathComponent(fileName)
                try data.write(to: fileURL)
                await updateProgress(1.0)
                return
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
    
    // MARK: - Compression Methods
    
    private func compressZip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        do {
            var filePaths: [String] = []
            
            // Collect all file paths to compress
            for (index, sourceURL) in sourceURLs.enumerated() {
                if sourceURL.hasDirectoryPath {
                    // Add all files in directory recursively
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
                
                let currentProgress = Double(index + 1) / Double(sourceURLs.count) * 0.5
                await updateProgress(currentProgress)
            }
            
            // Create ZIP archive using URLs
            let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
            try Zip.zipFiles(paths: fileURLs, zipFilePath: destinationURL, password: nil) { progress in
                Task { @MainActor in
                    self.progress = 0.5 + (progress * 0.5)
                }
            }
            
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
                            let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.deletingLastPathComponent().path + "/", with: "")
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
                
                let currentProgress = Double(index + 1) / Double(sourceURLs.count) * 0.8
                await updateProgress(currentProgress)
            }
            
            // Create TAR archive
            let tarData = TarContainer.create(from: entries)
            try tarData.write(to: destinationURL)
            
            await updateProgress(1.0)
            
        } catch {
            throw ArchiveError.compressionFailed("TAR compression failed: \(error.localizedDescription)")
        }
    }
    
    private func compressGzip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        // For now, GZIP compression is not fully supported - throw an error
        throw ArchiveError.compressionFailed("GZIP compression is not currently supported")
    }
    
    private func compressRAR(from sourceURLs: [URL], to destinationURL: URL) async throws {
        // Use clean-room implementation instead of system rar binary
        let archiver = RARArchiver(solid: true, recoveryRecord: false)
        
        let totalFiles = sourceURLs.count
        
        do {
            // Process each file/directory
            for (index, sourceURL) in sourceURLs.enumerated() {
                await updateProgress(Double(index) / Double(totalFiles))
                
                if sourceURL.hasDirectoryPath {
                    // Add directory recursively
                    try await addDirectoryRecursively(at: sourceURL, to: archiver, name: sourceURL.lastPathComponent)
                } else {
                    // Add single file
                    let data = try Data(contentsOf: sourceURL)
                    try archiver.addFile(name: sourceURL.lastPathComponent, data: data)
                }
            }
            
            // Create the final archive
            let archiveData = try archiver.createArchive()
            
            // Write to destination
            try archiveData.write(to: destinationURL)
            
            await updateProgress(1.0)
            
        } catch {
            throw ArchiveError.compressionFailed("RAR compression failed: \(error.localizedDescription)")
        }
    }
    
    private func addDirectoryRecursively(at sourceURL: URL, to archiver: RARArchiver, name: String) async throws {
        // Add the directory entry itself
        try archiver.addDirectory(name: name)
        
        // Process contents recursively
        let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        
        for fileURL in contents {
            let relativeName = name + "/" + fileURL.lastPathComponent
            
            if fileURL.hasDirectoryPath {
                try await addDirectoryRecursively(at: fileURL, to: archiver, name: relativeName)
            } else {
                let data = try Data(contentsOf: fileURL)
                try archiver.addFile(name: relativeName, data: data)
            }
        }
    }
    
    private func compressSevenZip(from sourceURLs: [URL], to destinationURL: URL) async throws {
        // For now, 7Z compression is not fully supported - throw an error  
        throw ArchiveError.compressionFailed("7Z compression is not currently supported")
    }
}
