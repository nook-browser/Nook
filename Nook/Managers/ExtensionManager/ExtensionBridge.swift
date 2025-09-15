//
//  ExtensionBridge.swift
//  Nook
//
//  Lightweight adapters exposing tabs/windows to WKWebExtension.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.4, *)
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    private unowned let browserManager: BrowserManager
    private var isProcessingTabsRequest = false

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        super.init()
    }
    
    // MARK: - Window Identity
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionWindowAdapter else { return false }
        return other.browserManager === self.browserManager
    }
    
    override var hash: Int {
        return ObjectIdentifier(browserManager).hashValue
    }

    private var lastActiveTabCall: Date = Date.distantPast
    
    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        let now = Date()
        if now.timeIntervalSince(lastActiveTabCall) > 2.0 {
            print("[ExtensionWindowAdapter] activeTab() called")
            lastActiveTabCall = now
        }
        
        if let t = browserManager.tabManager.currentTab,
           let a = ExtensionManager.shared.stableAdapter(for: t) {
            return a
        }
        
        if let first = browserManager.tabManager.pinnedTabs.first ?? browserManager.tabManager.tabs.first,
           let a = ExtensionManager.shared.stableAdapter(for: first) {
            return a
        }
        
        return nil
    }

    private var lastTabsCall: Date = Date.distantPast
    
    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        let now = Date()
        let shouldLog = now.timeIntervalSince(lastTabsCall) > 2.0
        if shouldLog {
            let currentTabName = browserManager.tabManager.currentTab?.name ?? "nil"
            print("[ExtensionWindowAdapter] tabs() called - Current tab: '\(currentTabName)'")
            lastTabsCall = now
        }
        
        let all = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
        let adapters = all.compactMap { ExtensionManager.shared.stableAdapter(for: $0) }
        
        return adapters
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        if let window = NSApp.mainWindow {
            return window.frame
        }
        return .zero
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        return NSScreen.main?.frame ?? .zero
    }

    func focus(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let window = NSApp.mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            completionHandler(nil)
        } else {
            completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No window to focus"]))
        }
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType {
        return .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        return .normal
    }

    func setWindowState(_ windowState: WKWebExtension.WindowState, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    func setFrame(_ frame: CGRect, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let window = NSApp.mainWindow {
            window.setFrame(frame, display: true)
            completionHandler(nil)
        } else {
            completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 2, userInfo: [NSLocalizedDescriptionKey: "No window to set frame on"]))
        }
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let window = NSApp.mainWindow {
            window.performClose(nil)
            completionHandler(nil)
        } else {
            completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 3, userInfo: [NSLocalizedDescriptionKey: "No window to close"]))
        }
    }
}

@available(macOS 15.4, *)
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    internal let tab: Tab
    private unowned let browserManager: BrowserManager

    init(tab: Tab, browserManager: BrowserManager) {
        self.tab = tab
        self.browserManager = browserManager
        super.init()
    }

    private var lastMethodCall: Date = Date.distantPast
    
    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        let now = Date()
        if now.timeIntervalSince(lastMethodCall) > 5.0 {
            print("[ExtensionTabAdapter] Methods called for tab: '\(tab.name)'")
            lastMethodCall = now
        }
        return tab.url
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        return tab.name
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        let isActive = browserManager.tabManager.currentTab?.id == tab.id
        return isActive
    }

    func indexInWindow(for extensionContext: WKWebExtensionContext) -> Int {
        if browserManager.tabManager.pinnedTabs.contains(where: { $0.id == tab.id }) {
            return 0
        }
        return tab.index
    }

    func isLoadingComplete(for extensionContext: WKWebExtensionContext) -> Bool {
        return !tab.isLoading
    }

    func isPinned(for extensionContext: WKWebExtensionContext) -> Bool {
        return browserManager.tabManager.pinnedTabs.contains(where: { $0.id == tab.id })
    }

    func isMuted(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func isPlayingAudio(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func isReaderModeActive(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        return tab.webView
    }

    func activate(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserManager.tabManager.setActiveTab(tab)
        completionHandler(nil)
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserManager.tabManager.removeTab(tab.id)
        completionHandler(nil)
    }
    
    // MARK: - Critical Missing Method
    
    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        let manager = ExtensionManager.shared
        if manager.windowAdapter == nil {
            manager.windowAdapter = ExtensionWindowAdapter(browserManager: browserManager)
        }
        return manager.windowAdapter!
    }
}
