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

        if let t = browserManager.currentTabForActiveWindow() {
            let a = MainActor.assumeIsolated {
                ExtensionManager.shared.stableAdapter(for: t)
            }
            if let a = a {
                return a
            }
        }

        if let first = browserManager.tabManager.pinnedTabs.first ?? browserManager.tabManager.tabs.first {
            let a = MainActor.assumeIsolated {
                ExtensionManager.shared.stableAdapter(for: first)
            }
            if let a = a {
                return a
            }
        }

        return nil
    }

    private var lastTabsCall: Date = Date.distantPast
    
    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        let now = Date()
        let shouldLog = now.timeIntervalSince(lastTabsCall) > 2.0
        if shouldLog {
            let currentTabName = browserManager.currentTabForActiveWindow()?.name ?? "nil"
            print("[ExtensionWindowAdapter] tabs() called - Current tab: '\(currentTabName)'")
            lastTabsCall = now
        }
        
        let all = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
        let adapters = all.compactMap { tab in
            MainActor.assumeIsolated {
                ExtensionManager.shared.stableAdapter(for: tab)
            }
        }

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

    // MARK: - Additional Window Methods

    func isAlwaysOnTop(for extensionContext: WKWebExtensionContext) -> Bool {
        if let window = NSApp.mainWindow {
            return window.level == .floating
        }
        return false
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow {
                window.level = alwaysOnTop ? .floating : .normal
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 4, userInfo: [NSLocalizedDescriptionKey: "No window to set always on top"]))
            }
        }
    }

    func isFullscreen(for extensionContext: WKWebExtensionContext) -> Bool {
        if let window = NSApp.mainWindow {
            return window.styleMask.contains(.fullScreen)
        }
        return false
    }

    func setFullscreen(_ fullscreen: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow {
                if fullscreen && !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                } else if !fullscreen && window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 5, userInfo: [NSLocalizedDescriptionKey: "No window to set fullscreen"]))
            }
        }
    }

    func minimize(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow {
                window.miniaturize(nil)
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 6, userInfo: [NSLocalizedDescriptionKey: "No window to minimize"]))
            }
        }
    }

    func unminimize(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow {
                window.deminiaturize(nil)
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 7, userInfo: [NSLocalizedDescriptionKey: "No window to unminimize"]))
            }
        }
    }

    func maximize(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow, let screen = window.screen {
                let screenFrame = screen.visibleFrame
                window.setFrame(screenFrame, display: true)
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 8, userInfo: [NSLocalizedDescriptionKey: "No window to maximize"]))
            }
        }
    }

    func unmaximize(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            if let window = NSApp.mainWindow {
                // Store previous frame before maximizing - this is a simplified approach
                // In a real implementation, you'd want to store the pre-maximized frame
                let defaultFrame = NSRect(x: 100, y: 100, width: 1200, height: 800)
                window.setFrame(defaultFrame, display: true)
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 9, userInfo: [NSLocalizedDescriptionKey: "No window to unmaximize"]))
            }
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

    // MARK: - Object Identity

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else { return false }
        return other.tab.id == self.tab.id
    }

    override var hash: Int {
        return tab.id.hashValue
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
        let isActive = browserManager.currentTabForActiveWindow()?.id == tab.id
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
    
      // MARK: - Tab Navigation Methods

    func goBack(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            tab.webView?.goBack()
            completionHandler(nil)
        }
    }

    func goForward(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            tab.webView?.goForward()
            completionHandler(nil)
        }
    }

    func reload(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            tab.webView?.reload()
            completionHandler(nil)
        }
    }

    func stopLoading(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            tab.webView?.stopLoading()
            completionHandler(nil)
        }
    }

    func loadURL(_ url: URL, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            let request = URLRequest(url: url)
            tab.webView?.load(request)
            completionHandler(nil)
        }
    }

    // MARK: - Tab Management Methods

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        Task { @MainActor in
            let urlString = tab.url.absoluteString
            let newTab = browserManager.tabManager.createNewTab(url: urlString, in: browserManager.tabManager.currentSpace)
            let adapter = ExtensionManager.shared.stableAdapter(for: newTab)
            completionHandler(adapter, nil)
        }
    }

    func detectWebpageLocale(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Locale?, Error?) -> Void) {
        tab.webView?.evaluateJavaScript("navigator.language || navigator.userLanguage || 'en'") { result, error in
            if let localeString = result as? String {
                let locale = Locale(identifier: localeString)
                completionHandler(locale, nil)
            } else {
                completionHandler(nil, error)
            }
        }
    }

    func screenshot(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Data?, Error?) -> Void) {
        Task { @MainActor in
            guard let webView = tab.webView else {
                completionHandler(nil, NSError(domain: "ExtensionTabAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
                return
            }

            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds

            webView.takeSnapshot(with: config) { image, error in
                if let image = image, let tiffData = image.tiffRepresentation {
                    completionHandler(tiffData, nil)
                } else {
                    completionHandler(nil, error)
                }
            }
        }
    }

    // MARK: - Tab Properties

    func getZoomFactor(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Double, Error?) -> Void) {
        Task { @MainActor in
            let zoomFactor = Double(tab.webView?.pageZoom ?? 1.0)
            completionHandler(zoomFactor, nil)
        }
    }

    func setZoomFactor(_ zoomFactor: Double, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab.webView?.pageZoom = CGFloat(zoomFactor)
        completionHandler(nil)
    }

    // MARK: - Tab Content Methods

    func executeJavaScript(_ javaScriptString: String, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Result<Any, Error>) -> Void) {
        tab.webView?.evaluateJavaScript(javaScriptString) { result, error in
            if let error = error {
                completionHandler(.failure(error))
            } else if let result = result {
                completionHandler(.success(result))
            } else {
                completionHandler(.success(()))
            }
        }
    }

    func captureVisibleTab(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Data?, Error?) -> Void) {
        // For now, delegate to screenshot method
        screenshot(for: extensionContext, completionHandler: completionHandler)
    }

    // MARK: - Tab History Methods

    func getNavigationHistory(for extensionContext: WKWebExtensionContext, completionHandler: @escaping ([WKBackForwardListItem]?, Error?) -> Void) {
        let history = tab.webView?.backForwardList
        let backItems = history?.backList ?? []
        let currentItem = history?.currentItem
        let forwardItems = history?.forwardList ?? []
        let items = backItems + [currentItem].compactMap { $0 } + forwardItems
        completionHandler(items, nil)
    }

    // MARK: - Window Association

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        let manager = MainActor.assumeIsolated {
            ExtensionManager.shared
        }
        if manager.windowAdapter == nil {
            manager.windowAdapter = ExtensionWindowAdapter(browserManager: browserManager)
        }
        return manager.windowAdapter
    }

    // MARK: - Tab Info Properties

    func getHeight(for extensionContext: WKWebExtensionContext) -> CGFloat {
        return tab.webView?.bounds.height ?? 0
    }

    func getWidth(for extensionContext: WKWebExtensionContext) -> CGFloat {
        return tab.webView?.bounds.width ?? 0
    }

    func getCookieStore(for extensionContext: WKWebExtensionContext) -> WKHTTPCookieStore? {
        return tab.webView?.configuration.websiteDataStore.httpCookieStore
    }

    // MARK: - Advanced Tab Methods (if available in current SDK)

    func setPinned(_ pinned: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        // Note: Pinned state would need to be handled by the tab manager
        // This is a placeholder implementation
        completionHandler(nil)
    }

    func hideFindUI(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab.webView?.evaluateJavaScript("document.getSelection().removeAllRanges()") { _, _ in
            completionHandler(nil)
        }
    }
}
