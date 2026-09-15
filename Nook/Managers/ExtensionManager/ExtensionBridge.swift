//
//  ExtensionBridge.swift
//  Nook
//
//  Lightweight adapters exposing tabs/windows to WKWebExtension.
//

import AppKit
import Foundation
import NookTabsCore
import os
import WebKit

/// One regular browser window. Private windows never get an adapter.
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let windowID: UUID
    weak var state: BrowserWindowState?
    private unowned let browserManager: BrowserManager

    init(window: BrowserWindowState, browserManager: BrowserManager) {
        self.windowID = window.id
        self.state = window
        self.browserManager = browserManager
        super.init()
    }

    // MARK: - Window Identity

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ExtensionWindowAdapter)?.windowID == windowID
    }

    override var hash: Int { windowID.hashValue }

    private var nsWindow: NSWindow? { state?.window }

    // ponytail: no query cache; displayOrder is cheap and a generation cache missed tree moves.
    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let state else { return nil }
        let tabs = browserManager.tabs
        guard let itemID = tabs.selectedItemID(in: state) ?? tabs.displayOrder(in: state).first else { return nil }
        return ExtensionManager.shared.adapter(for: itemID)
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let state else { return [] }
        return browserManager.tabs.displayOrder(in: state).compactMap { ExtensionManager.shared.adapter(for: $0) }
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        nsWindow?.frame ?? .zero
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        (nsWindow?.screen ?? NSScreen.main)?.frame ?? .zero
    }

    func focus(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = nsWindow else {
            completionHandler(Self.error(1, "No window to focus"))
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        completionHandler(nil)
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        // Private windows have no extension controller and are never exposed through this adapter.
        return false
    }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType {
        return .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = nsWindow else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func setWindowState(_ windowState: WKWebExtension.WindowState, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = nsWindow else {
            completionHandler(Self.error(4, "No window available"))
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
        guard let window = nsWindow else {
            completionHandler(Self.error(2, "No window to set frame on"))
            return
        }
        window.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = nsWindow else {
            completionHandler(Self.error(3, "No window to close"))
            return
        }
        window.performClose(nil)
        completionHandler(nil)
    }

    private static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "ExtensionWindowAdapter", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// One tab item, keyed by item id. The page session is resolved on each call, so an unloaded
/// tab keeps the same adapter, and a reopened tab (same id) compares equal to its old adapter.
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let itemID: UUID
    private unowned let browserManager: BrowserManager

    init(itemID: UUID, browserManager: BrowserManager) {
        self.itemID = itemID
        self.browserManager = browserManager
        super.init()
    }

    // MARK: - Identity (consistent across lookups)

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ExtensionTabAdapter)?.itemID == itemID
    }

    override var hash: Int { itemID.hashValue }

    private var tabs: TabsController { browserManager.tabs }
    private var session: PageSession? { tabs.session(for: itemID) }

    /// The window this tab belongs to: the focused window when it shows the tab, else any
    /// regular window that shows it, else the focused regular window.
    var hostWindow: BrowserWindowState? {
        let registry = browserManager.windowRegistry
        let regular = (registry?.allWindows ?? []).filter { $0.privateTree == nil }
        let active = registry?.activeWindow.flatMap { $0.privateTree == nil ? $0 : nil }
        let candidates = (active.map { [$0] } ?? []) + regular.filter { $0 !== active }
        return candidates.first { tabs.displayOrder(in: $0).contains(itemID) } ?? active ?? regular.first
    }

    private func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "ExtensionTabAdapter", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        if let session { return session.url }
        if case .tab(let url, _)? = tabs.item(itemID)?.kind { return url }
        return nil
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        if let session { return session.title }
        if case .tab(_, let title)? = tabs.item(itemID)?.kind { return title }
        return nil
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        tabs.activeWindowSession?.itemID == itemID
    }

    func indexInWindow(for extensionContext: WKWebExtensionContext) -> Int {
        guard let window = hostWindow else { return 0 }
        return tabs.displayOrder(in: window).firstIndex(of: itemID) ?? 0
    }

    func isLoadingComplete(for extensionContext: WKWebExtensionContext) -> Bool {
        !(session?.isLoading ?? false)
    }

    func isPinned(for extensionContext: WKWebExtensionContext) -> Bool {
        switch tabs.section(of: itemID) {
        case .pinned?, .favorites?: return true
        default: return false
        }
    }

    func isMuted(for extensionContext: WKWebExtensionContext) -> Bool {
        session?.isAudioMuted ?? false
    }

    func isPlayingAudio(for extensionContext: WKWebExtensionContext) -> Bool {
        session?.hasPlayingAudio ?? false
    }

    func isReaderModeActive(for extensionContext: WKWebExtensionContext) -> Bool {
        return false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        // The existing view only, never lazy creation. Tabs are registered with the controller
        // before the compositor assigns a window, so `assignedWebView` would be nil here and
        // WebKit could not match content script messages to this adapter.
        session?.webView
    }

    func activate(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = hostWindow else {
            completionHandler(error(2, "No window"))
            return
        }
        tabs.select(itemID, in: window)
        completionHandler(nil)
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tabs.close(itemID)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let webView = session?.webView else {
            completionHandler(error(1, "No webview"))
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
        // An item without a live page has nothing to navigate; the contract has no way to
        // start a session without selecting the tab.
        guard let session else {
            completionHandler(error(3, "Tab is not loaded"))
            return
        }
        session.load(url)
        completionHandler(nil)
    }

    func setMuted(_ muted: Bool, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        session?.setMuted(muted)
        completionHandler(nil)
    }

    func setZoomFactor(_ zoomFactor: Double, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        session?.webView?.pageZoom = zoomFactor
        completionHandler(nil)
    }

    func zoomFactor(for extensionContext: WKWebExtensionContext) -> Double {
        Double(session?.webView?.pageZoom ?? 1.0)
    }

    func shouldGrantPermissionsOnUserGesture(for extensionContext: WKWebExtensionContext) -> Bool {
        return true
    }

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        hostWindow.flatMap { ExtensionManager.shared.windowAdapter(for: $0) }
    }
}
