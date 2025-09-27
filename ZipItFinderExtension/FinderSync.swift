import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    
    override init() {
        super.init()
        
        // Set up the directory we are syncing - all directories
        if let folderURL = URL(string: "file:///") {
            FIFinderSyncController.default().directoryURLs = [folderURL]
        }
        
        // Set up images for our toolbar items
        let toolbarItem = FIFinderSyncToolbarItem(identifier: "com.ZipIt.compress")
        toolbarItem.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Compress")
        toolbarItem.label = "Compress with ZipIt"
        FIFinderSyncController.default().toolbarItems = [toolbarItem]
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Create menu for context menu
        let menu = NSMenu(title: "")
        
        // Get selected items
        guard let selectedItems = FIFinderSyncController.default().selectedItemURLs(), !selectedItems.isEmpty else {
            return nil
        }
        
        // Add compression menu item
        let compressItem = NSMenuItem(
            title: "Compress with ZipIt ",
            action: #selector(compressItems(_:)),
            keyEquivalent: ""
        )
        
        // Set icon
        compressItem.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Compress")
        menu.addItem(compressItem)
        
        return menu
    }
    
    @objc func compressItems(_ sender: NSMenuItem) {
        // Get selected files/folders
        guard let selectedItems = FIFinderSyncController.default().selectedItemURLs() else {
            return
        }
        
        // Send notification to main app
        let userInfo: [String: Any] = [
            "files": selectedItems.map { $0.path },
            "timestamp": Date().timeIntervalSince1970
        ]
        
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("ZipIt.CompressFiles"),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        
        // Also post a system notification to make sure the app receives it
        let notification = NSUserNotification()
        notification.title = "Compressing with ZipIt"
        notification.informativeText = "Compressing \(selectedItems.count) item(s)"
        notification.soundName = nil
        NSUserNotificationCenter.default().deliver(notification)
        
        // Try to activate the app
        NSWorkspace.shared.launchApplication("ZipIt")
    }
}