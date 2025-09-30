//
//  CompressionIntegrationTests.swift
//  ZipItTests
//
//  Integration tests for compression features including:
//  - ZIP/TAR/RAR compression and extraction round-trips
//  - Atomic write operations and verification
//  - Error handling and cleanup
//  - Preflight checks and constraints
//

import Foundation
import Testing
import ZIPFoundation
@testable import ZipIt

@MainActor
struct CompressionIntegrationTests {
    
    // MARK: - Test Helpers
    
    /// Create a temporary directory for test operations
    private func createTempDirectory(suffix: String) throws -> URL {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zipit_test_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return tmpDir
    }
    
    /// Create test files with known content
    private func createTestFiles(in directory: URL) throws -> (files: [URL], content: [URL: Data]) {
        var files: [URL] = []
        var contentMap: [URL: Data] = [:]
        
        // Create a text file
        let textFile = directory.appendingPathComponent("test.txt")
        let textData = Data("Hello ZipIt Test\n".utf8)
        try textData.write(to: textFile)
        files.append(textFile)
        contentMap[textFile] = textData
        
        // Create a subdirectory with files
        let subDir = directory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let binFile = subDir.appendingPathComponent("data.bin")
        let binData = Data((0..<256).map { UInt8($0) })
        try binData.write(to: binFile)
        files.append(binFile)
        contentMap[binFile] = binData
        
        return (files, contentMap)
    }
    
    /// Verify extracted files match original content
    private func verifyExtractedContent(
        extractedDir: URL,
        originalContent: [URL: Data],
        originalBase: URL
    ) throws {
        for (originalURL, expectedData) in originalContent {
            let relativePath = originalURL.path.replacingOccurrences(
                of: originalBase.path + "/",
                with: ""
            )
            let extractedURL = extractedDir.appendingPathComponent(relativePath)
            
            guard FileManager.default.fileExists(atPath: extractedURL.path) else {
                throw TestError.fileNotFound(extractedURL.path)
            }
            
            let actualData = try Data(contentsOf: extractedURL)
            guard actualData == expectedData else {
                throw TestError.contentMismatch(extractedURL.path)
            }
        }
    }
    
    enum TestError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case contentMismatch(String)
        case partFileNotCleaned(String)
        case archiveNotVerified
        case expectedFailure(String)
        
        var description: String {
            switch self {
            case .fileNotFound(let path): return "File not found: \(path)"
            case .contentMismatch(let path): return "Content mismatch: \(path)"
            case .partFileNotCleaned(let path): return "Temp file not cleaned: \(path)"
            case .archiveNotVerified: return "Archive verification failed"
            case .expectedFailure(let msg): return "Expected failure but got: \(msg)"
            }
        }
    }
    
    // MARK: - Test 1: ZIP Extraction and Round-Trip
    
    @Test("ZIP extraction and round-trip compression")
    func zipExtractionAndRoundTrip() async throws {
        let tmpDir = try createTempDirectory(suffix: "zip_roundtrip")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Use a sample ZIP from test files - use relative path from this source file
        let testFilesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Test files for supported formats")
            .appendingPathComponent("Samples .zip files ")
        let testZipURL = testFilesDir.appendingPathComponent("sample-1.zip")
        
        guard FileManager.default.fileExists(atPath: testZipURL.path) else {
            print("⚠️  Test ZIP file not found at \(testZipURL.path), skipping test")
            return
        }
        
        let extractDir = tmpDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // Extract the ZIP
        let extractor = ArchiveExtractor()
        try await extractor.extractArchive(from: testZipURL, to: extractDir, format: .zip)
        
        // Verify extraction succeeded and files exist
        let extractedFiles = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        #expect(!extractedFiles.isEmpty, "ZIP extraction should produce files")
        
        // Now compress the extracted content back to ZIP
        let recompressedZip = tmpDir.appendingPathComponent("recompressed.zip")
        try await extractor.compressFiles(from: [extractDir], to: recompressedZip, format: .zip)
        
        // Verify the recompressed archive exists and is valid
        #expect(FileManager.default.fileExists(atPath: recompressedZip.path))
        
        // Verify no .zipit.part temp file left behind
        let partFile = URL(fileURLWithPath: recompressedZip.path + ".zipit.part")
        #expect(!FileManager.default.fileExists(atPath: partFile.path), "Temp file should be cleaned up")
    }
    
    // MARK: - Test 2: TAR Extraction and Round-Trip
    
    @Test("TAR extraction and round-trip compression")
    func tarExtractionAndRoundTrip() async throws {
        let tmpDir = try createTempDirectory(suffix: "tar_roundtrip")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create test files
        let srcDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let (_, originalContent) = try createTestFiles(in: srcDir)
        
        // Compress to TAR
        let tarArchive = tmpDir.appendingPathComponent("test.tar")
        let extractor = ArchiveExtractor()
        try await extractor.compressFiles(from: [srcDir], to: tarArchive, format: .tar)
        
        // Verify archive exists
        #expect(FileManager.default.fileExists(atPath: tarArchive.path))
        
        // Extract the TAR
        let extractDir = tmpDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await extractor.extractArchive(from: tarArchive, to: extractDir, format: .tar)
        
        // Verify extracted content matches original
        let extractedSrcDir = extractDir.appendingPathComponent("source")
        try verifyExtractedContent(
            extractedDir: extractedSrcDir,
            originalContent: originalContent,
            originalBase: srcDir
        )
        
        // Verify no .zipit.part temp file
        let partFile = URL(fileURLWithPath: tarArchive.path + ".zipit.part")
        #expect(!FileManager.default.fileExists(atPath: partFile.path))
    }
    
    // MARK: - Test 3: RAR Streaming Store Write and Verify
    
    @Test("RAR streaming store-only compression with verification")
    func rarStreamingStoreWrite() async throws {
        let tmpDir = try createTempDirectory(suffix: "rar_streaming")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create test files
        let srcDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let (files, originalContent) = try createTestFiles(in: srcDir)
        
        // Create RAR archive using streaming writer (store-only)
        let rarArchive = tmpDir.appendingPathComponent("test.rar")
        let extractor = ArchiveExtractor()
        
        // This should use streaming write without loading whole files to memory
        try await extractor.compressFiles(from: [srcDir], to: rarArchive, format: .rar)
        
        // Verify archive was created
        #expect(FileManager.default.fileExists(atPath: rarArchive.path))
        
        // Verify the archive can be extracted
        let extractDir = tmpDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await extractor.extractArchive(from: rarArchive, to: extractDir, format: .rar)
        
        // Verify extracted content byte-for-byte
        let extractedSrcDir = extractDir.appendingPathComponent("source")
        try verifyExtractedContent(
            extractedDir: extractedSrcDir,
            originalContent: originalContent,
            originalBase: srcDir
        )
        
        print("✅ RAR streaming write test passed - files compressed and extracted correctly")
    }
    
    // MARK: - Test 4: RAR ASCII Filename Guard
    
    @Test("RAR rejects non-ASCII filenames with clear error")
    func rarASCIIFilenameGuard() async throws {
        let tmpDir = try createTempDirectory(suffix: "rar_ascii_guard")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create a file with non-ASCII name
        let srcDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        
        let nonASCIIFile = srcDir.appendingPathComponent("tëst_émoji_🎉.txt")
        try Data("test".utf8).write(to: nonASCIIFile)
        
        let rarArchive = tmpDir.appendingPathComponent("test.rar")
        let extractor = ArchiveExtractor()
        
        // This should fail with a clear error about ASCII-only names
        do {
            try await extractor.compressFiles(from: [srcDir], to: rarArchive, format: .rar)
            Issue.record("Expected RAR compression to fail for non-ASCII filename")
        } catch {
            // Expected error - verify it's the right kind
            let errorMsg = error.localizedDescription.lowercased()
            #expect(
                errorMsg.contains("ascii") || errorMsg.contains("character") || errorMsg.contains("name"),
                "Error should mention ASCII/character/name restriction: \(error)"
            )
            print("✅ RAR ASCII guard correctly rejected non-ASCII filename: \(error)")
        }
    }
    
    // MARK: - Test 5: ZIP Atomic Write and Verification
    
    @Test("ZIP atomic write with verification")
    func zipAtomicWriteAndVerify() async throws {
        let tmpDir = try createTempDirectory(suffix: "zip_atomic")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create test files
        let srcDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try createTestFiles(in: srcDir)
        
        let zipArchive = tmpDir.appendingPathComponent("test.zip")
        let partFile = URL(fileURLWithPath: zipArchive.path + ".zipit.part")
        
        let extractor = ArchiveExtractor()
        try await extractor.compressFiles(from: [srcDir], to: zipArchive, format: .zip)
        
        // Verify final archive exists
        #expect(FileManager.default.fileExists(atPath: zipArchive.path))
        
        // Verify temp .zipit.part file was cleaned up
        #expect(!FileManager.default.fileExists(atPath: partFile.path), "Temp .zipit.part should be removed after atomic rename")
        
        // Verify archive integrity by attempting to open with ZIPFoundation
        do {
            let archive = try ZIPFoundation.Archive(url: zipArchive, accessMode: .read)
            let entries = archive.makeIterator().map { $0 }
            #expect(!entries.isEmpty, "ZIP should contain entries")
            print("✅ ZIP atomic write passed - archive verified with \(entries.count) entries")
        } catch {
            throw TestError.archiveNotVerified
        }
    }
    
    // MARK: - Test 6: TAR Atomic Write and Verification
    
    @Test("TAR atomic write with verification")
    func tarAtomicWriteAndVerify() async throws {
        let tmpDir = try createTempDirectory(suffix: "tar_atomic")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create test files
        let srcDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try createTestFiles(in: srcDir)
        
        let tarArchive = tmpDir.appendingPathComponent("test.tar")
        let partFile = URL(fileURLWithPath: tarArchive.path + ".zipit.part")
        
        let extractor = ArchiveExtractor()
        try await extractor.compressFiles(from: [srcDir], to: tarArchive, format: .tar)
        
        // Verify final archive exists
        #expect(FileManager.default.fileExists(atPath: tarArchive.path))
        
        // Verify temp .zipit.part file was cleaned up
        #expect(!FileManager.default.fileExists(atPath: partFile.path), "Temp .zipit.part should be removed")
        
        // Verify TAR integrity using tar command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tf", tarArchive.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        #expect(process.terminationStatus == 0, "TAR verification should succeed")
        
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let listing = String(data: output, encoding: .utf8) ?? ""
        #expect(!listing.isEmpty, "TAR should contain files")
        print("✅ TAR atomic write passed - archive verified")
    }
    
    // MARK: - Test 7: Single-Selection Enforcement
    
    @Test("Compression enforces single-selection policy")
    func singleSelectionEnforcement() async throws {
        let tmpDir = try createTempDirectory(suffix: "single_selection")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create multiple files
        let file1 = tmpDir.appendingPathComponent("file1.txt")
        let file2 = tmpDir.appendingPathComponent("file2.txt")
        try Data("test1".utf8).write(to: file1)
        try Data("test2".utf8).write(to: file2)
        
        let zipArchive = tmpDir.appendingPathComponent("test.zip")
        let extractor = ArchiveExtractor()
        
        // Try to compress multiple files - should fail
        do {
            try await extractor.compressFiles(from: [file1, file2], to: zipArchive, format: .zip)
            Issue.record("Expected compression to fail with multiple files")
        } catch {
            // Expected - verify error message mentions single selection
            print("✅ Single-selection enforcement works: \(error)")
        }
    }
    
    // MARK: - Test 8: Preflight Checks
    
    @Test("Preflight checks catch invalid operations")
    func preflightChecks() async throws {
        let tmpDir = try createTempDirectory(suffix: "preflight")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        let extractor = ArchiveExtractor()
        
        // Test 1: Non-existent source
        let nonExistent = tmpDir.appendingPathComponent("does_not_exist.txt")
        let outputArchive = tmpDir.appendingPathComponent("test.zip")
        
        do {
            try await extractor.compressFiles(from: [nonExistent], to: outputArchive, format: .zip)
            Issue.record("Expected compression to fail for non-existent file")
        } catch {
            print("✅ Preflight caught non-existent file: \(error)")
        }
        
        // Test 2: Invalid destination (read-only location)
        let readOnlyDest = URL(fileURLWithPath: "/System/test.zip")
        let validFile = tmpDir.appendingPathComponent("valid.txt")
        try Data("test".utf8).write(to: validFile)
        
        do {
            try await extractor.compressFiles(from: [validFile], to: readOnlyDest, format: .zip)
            Issue.record("Expected compression to fail for read-only destination")
        } catch {
            print("✅ Preflight caught unwritable destination: \(error)")
        }
    }
    
    // MARK: - Test 9: Failure Path Cleanup
    
    @Test("Temp files cleaned up on compression failure")
    func failureCleanup() async throws {
        let tmpDir = try createTempDirectory(suffix: "failure_cleanup")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create a source that will cause failure during compression
        let srcFile = tmpDir.appendingPathComponent("test.txt")
        try Data("test".utf8).write(to: srcFile)
        
        // Try to write to an invalid destination format
        let invalidDest = tmpDir.appendingPathComponent("test.invalid")
        let extractor = ArchiveExtractor()
        
        do {
            try await extractor.compressFiles(from: [srcFile], to: invalidDest, format: .unknown)
            Issue.record("Expected compression to fail for unknown format")
        } catch {
            // Verify no .zipit.part files left behind
            let contents = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            let partFiles = contents.filter { $0.lastPathComponent.hasSuffix(".zipit.part") }
            #expect(partFiles.isEmpty, "No temp files should remain after failure")
            print("✅ Failure cleanup verified: \(error)")
        }
    }
    
    // MARK: - Test 10: GZIP Single File Extraction
    
    @Test("GZIP single file extraction produces correct output")
    func gzipSingleFileExtraction() async throws {
        let tmpDir = try createTempDirectory(suffix: "gzip_single")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        
        // Create a test file and compress it with gzip
        let originalFile = tmpDir.appendingPathComponent("test.txt")
        let originalData = Data("Hello GZIP\n".utf8)
        try originalData.write(to: originalFile)
        
        // Compress with gzip command
        let gzFile = tmpDir.appendingPathComponent("test.txt.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", originalFile.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        
        let compressedData = pipe.fileHandleForReading.readDataToEndOfFile()
        try compressedData.write(to: gzFile)
        
        // Extract using ZipIt
        let extractDir = tmpDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractor = ArchiveExtractor()
        try await extractor.extractArchive(from: gzFile, to: extractDir, format: .gzip)
        
        // Verify extracted file has correct name (without .gz) and content
        let extractedFile = extractDir.appendingPathComponent("test.txt")
        #expect(FileManager.default.fileExists(atPath: extractedFile.path), "Extracted file should exist with correct name")
        
        let extractedData = try Data(contentsOf: extractedFile)
        #expect(extractedData == originalData, "Extracted content should match original")
        
        print("✅ GZIP single file extraction passed")
    }
}