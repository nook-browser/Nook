//
//  ExtensionBridge.swift
//  Nook
//
//  Lightweight adapters exposing tabs/windows to WKWebExtension.
//

import AppKit
import Foundation
import os
import WebKit

@available(macOS 15.4, *)
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionBridge")
    private unowned let browserManager: BrowserManager

    // MARK: - Tab query cache
    // Extensions poll chrome.tabs.query() frequently (e.g. SponsorBlock on YouTube).
    // Cache results and only rebuild when tabs actually change.
    private var cachedTabs: [any WKWebExtensionTab]?
    private var cachedActiveTab: (any WKWebExtensionTab)?
    private var cachedActiveTabValid = false
    private var cacheGeneration: UInt = 0

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

    private func refreshCacheIfNeeded() {
        let gen = ExtensionManager.shared.tabCacheGeneration
        if gen != cacheGeneration {
            cachedTabs = nil
            cachedActiveTab = nil
            cachedActiveTabValid = false
            cacheGeneration = gen
        }
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        refreshCacheIfNeeded()
        if cachedActiveTabValid { return cachedActiveTab }

        var result: (any WKWebExtensionTab)?
        if let t = browserManager.currentTabForActiveWindow(),
           let a = ExtensionManager.shared.stableAdapter(for: t) {
            result = a
        } else if let first = browserManager.tabManager.pinnedTabs.first ?? browserManager.tabManager.tabs.first,
                  let a = ExtensionManager.shared.stableAdapter(for: first) {
            result = a
        }

        cachedActiveTab = result
        cachedActiveTabValid = true
        return result
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        refreshCacheIfNeeded()
        if let cached = cachedTabs { return cached }

        let all = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
        let result = all.compactMap { ExtensionManager.shared.stableAdapter(for: $0) }
        cachedTabs = result
        return result
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
        if let currentTab = browserManager.currentTabForActiveWindow() {
            return currentTab.isEphemeral
        }
        return false
    }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType {
        return .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = NSApp.mainWindow else { return .normal }
        if window.isMiniaturized {
            return .minimized
        }
        if window.styleMask.contains(.fullScreen) {
            return .fullscreen
        }
        return .normal
    }

    func setWindowState(_ windowState: WKWebExtension.WindowState, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = NSApp.mainWindow else {
            completionHandler(NSError(domain: "ExtensionWindowAdapter", code: 4, userInfo: [NSLocalizedDescriptionKey: "No window available"]))
            return
        }

        switch windowState {
        case .minimized:
            window.miniaturize(nil)
        case .maximized:
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.zoom(nil)
        case .fullscreen:
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        case .normal:
            if window.isMiniaturized {
                window.deminiaturize(nil)
            } else if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        @unknown default:
            break
        }

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

    // MARK: - Identity (consistent across lookups)

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else { return false }
        return other.tab.id == self.tab.id
    }

    override var hash: Int {
        return tab.id.hashValue
    }

    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        return tab.url
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        return tab.name
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        return browserManager.currentTabForActiveWindow()?.id == tab.id
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
        return tab.isAudioMuted
    }

    func isPlayingAudio(for extensionContext: WKWebExtensionContext) -> Bool {
        return tab.hasPlayingAudio
    }

    func isReaderModeActive(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        // Use existingWebView to return the webview without triggering lazy init.
        // Must NOT use assignedWebView here — it requires primaryWindowId to be set,
        // but tabs are registered with the extension controller before the compositor
        // assigns a window. Using assignedWebView causes "Tab not found" errors
        // because WebKit can't match content script messages to tab adapters.
        return tab.existingWebView
    }

    func activate(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserManager.tabManager.setActiveTab(tab)
        completionHandler(nil)
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserManager.tabManager.removeTab(tab.id)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let webView = tab.webView else {
            completionHandler(NSError(domain: "ExtensionTabAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No webview"]))
            return
        }
        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab.loadURL(url.absoluteString)
        completionHandler(nil)
    }

    func setMuted(_ muted: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab.isAudioMuted = muted
        completionHandler(nil)
    }

    func setZoomFactor(_ zoomFactor: Double, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab.webView?.pageZoom = zoomFactor
        completionHandler(nil)
    }

    func zoomFactor(for extensionContext: WKWebExtensionContext) -> Double {
        return Double(tab.webView?.pageZoom ?? 1.0)
    }

    func shouldGrantPermissionsOnUserGesture(for extensionContext: WKWebExtensionContext) -> Bool {
        return true
    }

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        let manager = ExtensionManager.shared
        if manager.windowAdapter == nil {
            manager.windowAdapter = ExtensionWindowAdapter(browserManager: browserManager)
        }
        return manager.windowAdapter
    }
}
