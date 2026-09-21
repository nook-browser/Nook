// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionPopupWindow.swift
//  Nook
//
//  A real window for chrome.windows.create({ type: "popup" }).
//

import AppKit
import Foundation
import WebKit

/// One extension page in its own small window, the shape `chrome.windows.create({type: "popup"})`
/// asks for. Bitwarden's locked-vault autofill opens its unlock UI this way; mapping it onto a tab
/// left the page in a window whose id the extension then passed to `chrome.windows.remove`.
/// Only the extension's own pages get one: an http popup keeps going to a tab, where it has the
/// space's data store and a visible URL.
final class ExtensionPopupWindow: NSObject, WKWebExtensionWindow, NSWindowDelegate {
    let webView: WKWebView
    let window: NSWindow
    private(set) lazy var tab = ExtensionPopupTab(popup: self)

    private weak var controller: WKWebExtensionController?
    private let onClose: (ExtensionPopupWindow) -> Void
    private var uiDelegate: PopupUIDelegate?

    private static let defaultSize = CGSize(width: 380, height: 630)

    init(
        url: URL,
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        title: String,
        controller: WKWebExtensionController,
        onClose: @escaping (ExtensionPopupWindow) -> Void
    ) {
        let rect = Self.windowRect(from: frame)
        webView = WKWebView(frame: CGRect(origin: .zero, size: rect.size), configuration: configuration)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.controller = controller
        self.onClose = onClose
        super.init()

        webView.isInspectable = true
        let delegate = PopupUIDelegate(webView: webView)
        uiDelegate = delegate
        webView.uiDelegate = delegate
        PopupClipboardHandler.install(on: webView, retainedBy: .shared)

        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.setFrame(rect, display: false)

        webView.load(URLRequest(url: url))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// WebKit hands over a frame on the main screen with NaN for anything the extension left out.
    private static func windowRect(from frame: CGRect) -> CGRect {
        let width = frame.width.isNaN ? defaultSize.width : frame.width
        let height = frame.height.isNaN ? defaultSize.height : frame.height
        let screen = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: defaultSize)
        let x = frame.origin.x.isNaN ? screen.midX - width / 2 : frame.origin.x
        let y = frame.origin.y.isNaN ? screen.midY - height / 2 : frame.origin.y
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - WKWebExtensionWindow

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] { [tab] }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tab }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType { .popup }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        window.isMiniaturized ? .minimized : .normal
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool { false }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect { window.frame }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        (window.screen ?? NSScreen.main)?.frame ?? .zero
    }

    func setFrame(_ frame: CGRect, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        window.setFrame(Self.windowRect(from: frame), display: true)
        completionHandler(nil)
    }

    func focus(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        show()
        completionHandler(nil)
    }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        window.performClose(nil)
        completionHandler(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window.delegate = nil
        webView.uiDelegate = nil
        controller?.didCloseTab(tab, windowIsClosing: true)
        controller?.didCloseWindow(self)
        onClose(self)
    }
}

/// The single tab of an `ExtensionPopupWindow`. `tabs.query` matches the popout by URL, so
/// `url(for:)` has to answer from the moment the load starts.
final class ExtensionPopupTab: NSObject, WKWebExtensionTab {
    private unowned let popup: ExtensionPopupWindow

    init(popup: ExtensionPopupWindow) {
        self.popup = popup
        super.init()
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? { popup.webView }

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { popup }

    func url(for extensionContext: WKWebExtensionContext) -> URL? { popup.webView.url }

    func title(for extensionContext: WKWebExtensionContext) -> String? { popup.webView.title }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool { false }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool { true }

    func close(for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        popup.window.performClose(nil)
        completionHandler(nil)
    }
}
