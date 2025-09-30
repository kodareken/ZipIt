//
//  ZipItApp.swift
//  ZipIt
//
//  Created by Douglas Ek on 2025-09-16.
//
//  This is the main entry point of the ZipIt application. It sets up the main window
//  and handles app-level events, such as opening files from Finder.
//

import SwiftUI
import AppKit

@main
@available(macOS 13.0, *)
struct ZipItApp: App {
    /// Application delegate provides activation and a shared AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
.environmentObject(appDelegate.appState)
                .onOpenURL(perform: handleOpenURL)
                .task { await handleCLIIfNeeded() }
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    // Set fixed window size
                    if let w = NSApp.windows.first {
                        let fixedSize = NSSize(width: 500, height: 470)
                        w.setContentSize(fixedSize)
                        w.styleMask.remove(.resizable)
                        w.center()
                    }
                }
        }
        .windowResizability(.contentSize)
    }
    
    /// Handles the event when a file is opened with the app (e.g., by double-clicking).
    /// - Parameter url: The URL of the file that was opened.
    private func handleOpenURL(_ url: URL) {
print("🔗 App opened with URL: \(url.path)")
        
        // Check if the app should perform a "quick extract" without showing the main UI.
        if shouldQuickExtract() {
            performQuickExtract(url: url)
        } else {
            // If not a quick extract, load the file into the UI for user interaction.
appDelegate.appState.selectedArchiveURL = url
        }
    }
    
    /// Determines whether a "quick extract" should be performed.
    /// A quick extract is triggered by command-line arguments or specific user actions.
    /// - Returns: `true` if a quick extract should be performed, `false` otherwise.
    private func shouldQuickExtract() -> Bool {
        let arguments = CommandLine.arguments
        
        // Only perform quick extract if explicitly requested via command-line flags
        return arguments.contains("--quick-extract") || arguments.contains("-q")
    }
    
    /// Performs the extraction in the background without showing the main UI.
    /// - Parameter url: The URL of the archive file to extract.
    private func performQuickExtract(url: URL) {
        Task {
            do {
                // By default, extract to the same directory where the archive is located.
                let destinationURL = url.deletingLastPathComponent()
                let format = ArchiveFormat.detect(from: url)
                
print("🚀 Quick extracting \(url.lastPathComponent) to \(destinationURL.path)")
                
                let extractor = ArchiveExtractor()
                try await extractor.extractArchive(from: url, to: destinationURL, format: format)
                
                print("✅ Quick extraction completed!")
                
                // Terminate the app after a short delay to ensure all operations are finished.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    NSApp.terminate(nil)
                }
                
            } catch {
print("❌ Quick extraction failed: \(error)")
                // If quick extraction fails, fall back to the main UI and show the error.
                await MainActor.run {
appDelegate.appState.selectedArchiveURL = url
                }
            }
        }
    }
    
    /// Handle CLI-based compression requests (used by Finder Quick Actions / Automator).
    private func handleCLIIfNeeded() async {
        let args = CommandLine.arguments
        guard args.contains("--compress") || args.contains("-c") else { return }
        
        // Parse format
        let format: ArchiveFormat = {
            if let idx = args.firstIndex(where: { $0 == "--format" || $0 == "-f" }), idx+1 < args.count {
                let f = args[idx+1].lowercased()
                switch f {
                case "zip": return .zip
                case "tar": return .tar
                case "gz", "gzip": return .gzip
                case "7z", "sevenzip": return .sevenZip
                case "rar": fallthrough
                default: return .rar
                }
            }
            return .rar
        }()
        
        // Parse output
        var outputPath: String? = nil
        if let idx = args.firstIndex(where: { $0 == "--output" || $0 == "-o" }), idx+1 < args.count {
            outputPath = args[idx+1]
        }
        
        // Collect source file arguments (all non-flag tokens after --compress)
        var sources: [String] = []
        if let cIdx = (args.firstIndex(of: "--compress") ?? args.firstIndex(of: "-c")) {
            let tail = args.dropFirst(cIdx+1)
            for token in tail {
                if token.hasPrefix("-") { continue }
                sources.append(token)
            }
        }
        
        // Fallback: if no explicit sources in tail, use all non-flag args excluding the first (exec path)
        if sources.isEmpty {
            sources = args.dropFirst().filter { !$0.hasPrefix("-") }
        }
        
        guard sources.isEmpty == false else {
            print("ZipIt: --compress requires at least one file or folder path")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        
        // Build destination URL
        let srcURLs = sources.map { URL(fileURLWithPath: $0) }
        let ext: String = {
            switch format { case .zip: return "zip"; case .tar: return "tar"; case .gzip: return "gz"; case .sevenZip: return "7z"; case .rar, .unknown: return "rar" }
        }()
        let defaultBaseName = (srcURLs.first?.deletingPathExtension().lastPathComponent ?? "Archive")
        let destURL: URL = {
            if let out = outputPath {
                let outURL = URL(fileURLWithPath: out)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: outURL.path, isDirectory: &isDir), isDir.boolValue {
                    return outURL.appendingPathComponent("\(defaultBaseName).\(ext)")
                } else {
                    // If no extension, append
                    if outURL.pathExtension.isEmpty { return outURL.appendingPathExtension(ext) }
                    return outURL
                }
            } else {
                let dir = srcURLs.first!.deletingLastPathComponent()
                return dir.appendingPathComponent("\(defaultBaseName).\(ext)")
            }
        }()
        
        print("ZipIt: compressing (format=\(format.rawValue)) → \(destURL.path)")
        do {
            let extractor = ArchiveExtractor()
            try await extractor.compressFiles(from: srcURLs, to: destURL, format: format)
            print("ZipIt: ✅ compression completed")
        } catch {
            print("ZipIt: ❌ compression failed: \(error)")
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

/// A simple observable object to manage the application's state.
/// This class holds the URL of the archive file that needs to be processed.
class AppState: ObservableObject {
    /// The URL of the archive file selected by the user, either through the file picker or by opening a file with the app.
    @Published var selectedArchiveURL: URL?
}
