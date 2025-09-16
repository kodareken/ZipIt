import Foundation
import Combine
import Zip
import SWCompression
import Gzip
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

enum ExtractionError: LocalizedError {
    case unsupportedFormat
    case extractionFailed(String)
    case invalidDestination
    case corruptedArchive
    case passwordRequired
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported archive format"
        case .extractionFailed(let details): return "Extraction failed: \(details)"
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
    @Published var progress: Double = 0.0
    @Published var extractionError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    func extractArchive(from sourceURL: URL, to destinationURL: URL, format: ArchiveFormat) async throws {
        guard format != .unknown else {
            throw ExtractionError.unsupportedFormat
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
                throw ExtractionError.unsupportedFormat
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
            throw ExtractionError.extractionFailed("ZIP extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func extractTarOrGzip(from sourceURL: URL, to destinationURL: URL, format: ArchiveFormat) async throws {
        do {
            var data = try Data(contentsOf: sourceURL)
            
            // Handle GZIP compression if needed
            if format == .gzip {
                data = try data.gunzipped()
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
            throw ExtractionError.extractionFailed("\(format.rawValue.uppercased()) extraction failed: \(error.localizedDescription)")
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
            throw ExtractionError.extractionFailed("7-Zip extraction failed: \(error.localizedDescription)")
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
                throw ExtractionError.passwordRequired
            case .badArchive:
                throw ExtractionError.corruptedArchive
            case .badData:
                throw ExtractionError.corruptedArchive
            default:
                throw ExtractionError.extractionFailed("RAR extraction failed: \(error.localizedDescription)")
            }
        } catch {
            throw ExtractionError.extractionFailed("RAR extraction failed: \(error.localizedDescription)")
        }
    }
    
    private func updateProgress(_ value: Double) async {
        await MainActor.run {
            progress = value
        }
    }
}
