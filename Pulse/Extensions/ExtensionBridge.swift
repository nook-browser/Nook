//
//  ExtensionBridge.swift
//  Pulse
//
//  Created for WKWebExtension support
//

import Foundation
import WebKit
import AppKit
import SwiftUI

#if canImport(WebKit)
import WebKit
#endif

@available(macOS 15.4, *)
extension Tab: WKWebExtensionTab {
    
    // MARK: - WKWebExtensionTab Required Properties
    
    var webExtensionTabIdentifier: Double {
        // Convert UUID to a stable double identifier
        return Double(id.hashValue)
    }
    
    var isActive: Bool {
        return isCurrentTab
    }
    
    var title: String? {
        return name
    }
    
    
    var isPinned: Bool {
        return browserManager?.tabManager.pinnedTabs.contains(where: { $0.id == self.id }) ?? false
    }
    
    var isReaderModeAvailable: Bool {
        // Check if reader mode is available for the current page
        return false // You can implement reader mode detection if needed
    }
    
    var isShowingReaderMode: Bool {
        return false // You can track reader mode state if needed
    }
    
    var size: CGSize {
        return webView.frame.size
    }
    
    var zoomFactor: Double {
        return webView.magnification
    }
    
    var window: (any WKWebExtensionWindow)? {
        // Return the browser window that contains this tab
        return BrowserWindow.shared
    }
    
    // MARK: - WKWebExtensionTab Optional Methods
    
    func activate(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.activate()
            completionHandler()
        }
    }
    
    func reload(bypassingCache: Bool, completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            if bypassingCache {
                // Force reload from server
                self.webView.reloadFromOrigin()
            } else {
                self.refresh()
            }
            completionHandler()
        }
    }
    
    func goBack(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.goBack()
            completionHandler()
        }
    }
    
    func goForward(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.goForward()
            completionHandler()
        }
    }
    
    func close(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.closeTab()
            completionHandler()
        }
    }
    
    func loadURL(_ url: URL, completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.loadURL(url)
            completionHandler()
        }
    }
}

@available(macOS 15.4, *)
final class BrowserWindow: NSObject, WKWebExtensionWindow {
    static let shared = BrowserWindow()
    
    private override init() {
        super.init()
    }
    
    // MARK: - WKWebExtensionWindow Required Properties
    
    var webExtensionWindowIdentifier: Double {
        return 1.0 // Single window browser for now
    }
    
    var windowType: WKWebExtension.WindowType {
        return .normal
    }
    
    var isActive: Bool {
        // Check if the main window is key
        return NSApp.mainWindow?.isKeyWindow ?? false
    }
    
    var isFocused: Bool {
        return isActive
    }
    
    var isPrivate: Bool {
        return false // Pulse doesn't have private browsing mode yet
    }
    
    var frame: CGRect {
        return NSApp.mainWindow?.frame ?? .zero
    }
    
    var state: WKWebExtension.WindowState {
        guard let window = NSApp.mainWindow else { return .normal }
        
        if window.isMiniaturized {
            return .minimized
        } else if window.styleMask.contains(.fullScreen) {
            return .fullscreen
        } else {
            return .normal
        }
    }
    
    // MARK: - WKWebExtensionWindow Tab Management
    
    func tabs(for webExtensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browserManager = getBrowserManager() else { return [] }
        
        // Return all tabs (pinned + current space)
        let pinnedTabs = browserManager.tabManager.pinnedTabs
        let spaceTabs = browserManager.tabManager.tabs
        let allTabs = pinnedTabs + spaceTabs
        
        return allTabs.compactMap { tab in
            if #available(macOS 15.4, *) {
                return tab as WKWebExtensionTab
            } else {
                return nil
            }
        }
    }
    
    func activeTab(for webExtensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let browserManager = getBrowserManager(),
              let currentTab = browserManager.tabManager.currentTab else { return nil }
        
        if #available(macOS 15.4, *) {
            return currentTab as WKWebExtensionTab
        } else {
            return nil
        }
    }
    
    // MARK: - WKWebExtensionWindow Optional Methods
    
    func focus(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            completionHandler()
        }
    }
    
    func close(completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.mainWindow?.close()
            completionHandler()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getBrowserManager() -> BrowserManager? {
        // Get the BrowserManager from the app's environment
        // This is a bit hacky but necessary for the singleton pattern
        if let windowController = NSApp.mainWindow?.windowController,
           let contentViewController = windowController.contentViewController as? NSHostingController<ContentView> {
            // Extract BrowserManager from SwiftUI environment if possible
            // For now, we'll need to find another way to access it
        }
        
        // Alternative: store a weak reference to BrowserManager
        return BrowserWindowManager.shared.browserManager
    }
}

// Helper singleton to maintain reference to BrowserManager
@MainActor
final class BrowserWindowManager {
    static let shared = BrowserWindowManager()
    weak var browserManager: BrowserManager?
    
    private init() {}
    
    func setBrowserManager(_ manager: BrowserManager) {
        self.browserManager = manager
    }
}
