import Foundation
import Combine
import Zip

enum CompressionError: LocalizedError {
    case compressionFailed(String)
    case invalidSource
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .compressionFailed(let details): return "Compression failed: \(details)"
        case .invalidSource: return "Invalid source files or folders"
        case .invalidDestination: return "Invalid destination folder"
        }
    }
}

@MainActor
class ArchiveCompressor: ObservableObject {
    @Published var isCompressing = false
    @Published var progress: Double = 0.0
    @Published var compressionError: String?

    func compressFiles(from sourceURLs: [URL], to destinationURL: URL, fileName: String) async throws {
        await MainActor.run {
            isCompressing = true
            progress = 0.0
            compressionError = nil
        }

        do {
            let zipFilePath = destinationURL.appendingPathComponent("\(fileName).zip")

            try Zip.zipFiles(sourceURLs, zipFilePath: zipFilePath, password: nil, progress: { progress in
                Task { @MainActor in
                    self.progress = progress
                }
            })

            await MainActor.run {
                isCompressing = false
            }
        } catch {
            await MainActor.run {
                compressionError = error.localizedDescription
                isCompressing = false
            }
            throw CompressionError.compressionFailed(error.localizedDescription)
        }
    }
}
