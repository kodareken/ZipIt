//
//  AppDelegate.swift
//  ZipIt
//
//  Ensures the app becomes active and a main window is visible on launch.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared application state used across the app
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure the app appears in the Dock and becomes frontmost
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // If no window was created automatically by SwiftUI, create one
        DispatchQueue.main.async {
            if NSApp.windows.isEmpty {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.center()
                window.title = "ZipIt"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: ContentView().environmentObject(self.appState))
                window.makeKeyAndOrderFront(nil)
            } else {
                for w in NSApp.windows { w.makeKeyAndOrderFront(nil) }
            }
        }
    }
}
