//
//  ZipItApp.swift
//  ZipIt
//
//  Created by Douglas Ek on 2025-09-16.
//

import SwiftUI

@main
struct ZipItApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL(perform: handleOpenURL)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }
    
    private func handleOpenURL(_ url: URL) {
        print("🔗 App opened with URL: \(url.path)")
        
        // Check if this is a quick extract request (from Cmd+Down or double-click)
        if shouldQuickExtract() {
            performQuickExtract(url: url)
        } else {
            // Load into UI for user interaction
            appState.selectedArchiveURL = url
        }
    }
    
    private func shouldQuickExtract() -> Bool {
        // Check for command line arguments or environment variables
        let arguments = CommandLine.arguments
        
        // Quick extract if launched with --quick-extract or if it's the default app opening
        return arguments.contains("--quick-extract") || 
               arguments.contains("-q") ||
               NSApp.currentEvent?.type == .keyDown // Detect Cmd+Down press
    }
    
    private func performQuickExtract(url: URL) {
        Task {
            do {
                // Extract to the same directory as the archive
                let destinationURL = url.deletingLastPathComponent()
                let format = ArchiveFormat.detect(from: url)
                
                print("🚀 Quick extracting \(url.lastPathComponent) to \(destinationURL.path)")
                
                let extractor = ArchiveExtractor()
                try await extractor.extractArchive(from: url, to: destinationURL, format: format)
                
                print("✅ Quick extraction completed!")
                
                // Exit the app after successful extraction
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
                
            } catch {
                print("❌ Quick extraction failed: \(error)")
                // Fall back to UI mode on error
                await MainActor.run {
                    appState.selectedArchiveURL = url
                }
            }
        }
    }
}

// AppState to manage file passing between app launch and UI
class AppState: ObservableObject {
    @Published var selectedArchiveURL: URL?
}
