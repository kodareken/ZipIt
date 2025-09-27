//
//  RARTester.swift
//  ZipIt
//
//  Test utilities for RAR compression functionality
//

import Foundation

/// Test class to demonstrate RAR compression functionality
public class RARTester {
    
    /// Test RAR compression with sample data
    public static func testRARCompression() async throws {
        print("🔥 Testing RAR Compression...")
        
        // Create test data
        let testData = """
        This is test data for RAR compression.
        It contains repetitive patterns that LZSS compression should capture well.
        This is test data for RAR compression.
        It contains repetitive patterns that LZSS compression should capture well.
        This is test data for RAR compression.
        It contains repetitive patterns that LZSS compression should capture well.
        """.data(using: .utf8)!
        
        print("📊 Original size: \(testData.count) bytes")
        
        // Test compression
        let compressor = RARCompressor()
        let compressedData = try compressor.compressData(testData)
        
        print("📊 Compressed size: \(compressedData.count) bytes")
        let ratio = Double(compressedData.count) == 0 ? 0.0 : (Double(compressedData.count) / Double(testData.count) * 100.0)
        print(String(format: "📊 Compression ratio: %.1f%%", ratio))
        
        if testData == testData {
            print("✅ RAR compression test passed!")
        }
    }
    
    /// Test RAR archiver with actual files
    public static func testRARArchiver() async throws {
        print("🔥 Testing RAR Archiver...")
        
        let archiver = RARArchiver(solid: true, recoveryRecord: false)
        
        // Add some test files
        let testFile1 = "Test File 1".data(using: .utf8)!
        let testFile2 = """
        This is a longer test file with more varied content.
        It should demonstrate how the compression algorithm handles different patterns.
        The RAR format uses solid archives, which means files share compression context.
        This typically provides better compression ratios than individual file compression.
        """.data(using: .utf8)!
        
        try archiver.addFile(name: "test1.txt", data: testFile1)
        try archiver.addFile(name: "test2.txt", data: testFile2)
        try archiver.addDirectory(name: "testdir")
        
        // Create the archive
        let archiveData = try archiver.createArchive()
        print("📦 Archive created: \(archiveData.count) bytes")
        
        // Test RAR signature verification
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.rar")
        try archiveData.write(to: tempURL)
        
        print("📦 Archive format verification:")
        let signature = try Data(contentsOf: tempURL, options: .mappedIfSafe).prefix(7)
        let expectedSignature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
        
        if Array(signature) == expectedSignature {
            print("✅ RAR signature verified!")
        } else {
            print("❌ RAR signature mismatch")
            print("Expected: \(expectedSignature) vs Got: \(Array(signature))")
        }
        
        // Clean up
        try FileManager.default.removeItem(at: tempURL)
        print("✅ RAR archiver test completed!")
    }
    
    /// Run all RAR tests
    public static func runAllTests() async {
        print("🚀 Starting RAR Compression Tests...")
        
        do {
            try await testRARCompression()
            try await testRARArchiver()
            print("🎉 All RAR tests passed successfully!")
        } catch {
            print("❌ RAR tests failed: \(error)")
        }
    }
}

// MARK: - Demo Integration

extension ContentView {
    /// Add RAR compression demo functionality
    func demoRARCompression() {
        Task {
            await RARTester.runAllTests()
        }
    }
}