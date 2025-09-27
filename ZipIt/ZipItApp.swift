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

@main
@available(macOS 13.0, *)
struct ZipItApp: App {
    /// The shared state of the application, including the URL of the selected archive.
    /// This is used to pass the file URL from the app's entry point to the main ContentView.
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL(perform: handleOpenURL)
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
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
            appState.selectedArchiveURL = url
        }
    }
    
    /// Determines whether a "quick extract" should be performed.
    /// A quick extract is triggered by command-line arguments or specific user actions.
    /// - Returns: `true` if a quick extract should be performed, `false` otherwise.
    private func shouldQuickExtract() -> Bool {
        let arguments = CommandLine.arguments
        
        // Only perform quick extract if explicitly requested via command-line flags
        // Remove the NSApp.currentEvent check as it's unreliable and prevents normal app launch
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
                
            } catch {
                print("❌ Quick extraction failed: \(error)")
                // If quick extraction fails, fall back to the main UI and show the error.
                await MainActor.run {
                    appState.selectedArchiveURL = url
                }
            }
        }
    }
}

/// A simple observable object to manage the application's state.
/// This class holds the URL of the archive file that needs to be processed.
class AppState: ObservableObject {
    /// The URL of the archive file selected by the user, either through the file picker or by opening a file with the app.
    @Published var selectedArchiveURL: URL?
}
