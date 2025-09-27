import Foundation
import Testing
@testable import ZipIt

struct RARStoreIntegrationTests {
    @Test
    @MainActor
    func createAndExtractRARStoreArchive() async throws {
        // Prepare temp paths
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zipit_rar_integ_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let srcDir = tmpDir.appendingPathComponent("src", isDirectory: true)
        let outDir = tmpDir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Create sample files
        let helloPath = srcDir.appendingPathComponent("hello.txt")
        let helloData = Data("Hello RAR from ZipIt\n".utf8)
        try helloData.write(to: helloPath)

        let subDir = srcDir.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let binPath = subDir.appendingPathComponent("file.bin")
        let binData = Data((0..<256).map { UInt8($0) })
        try binData.write(to: binPath)

        // Build RAR archive with store-only writer
        let archiver = RARArchiver(solid: true, recoveryRecord: false)
        try archiver.addFile(name: "hello.txt", data: helloData)
        try archiver.addDirectory(name: "dir")
        try archiver.addFile(name: "dir/file.bin", data: binData)

        let rarData = try archiver.createArchive()
        let rarURL = tmpDir.appendingPathComponent("sample.rar")
        try rarData.write(to: rarURL)

        // Extract using app's extractor path (which uses Unrar internally)
        let extractor = ArchiveExtractor()
        try await extractor.extractArchive(from: rarURL, to: outDir, format: .rar)

        // Verify extracted contents
        let outHello = outDir.appendingPathComponent("hello.txt")
        let outBin = outDir.appendingPathComponent("dir/file.bin")

        #expect(FileManager.default.fileExists(atPath: outHello.path))
        #expect(FileManager.default.fileExists(atPath: outBin.path))
        let helloRead = try Data(contentsOf: outHello)
        let binRead = try Data(contentsOf: outBin)
        #expect(helloRead == helloData)
        #expect(binRead == binData)
    }
}