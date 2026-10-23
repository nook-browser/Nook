// Licensed under GPL-3.0. See LICENSE.
//
//  WebContextMenu.swift
//  Nook
//
//  Created by Codex on 09/02/2025.
//

import AppKit
import WebKit
import NookTabsCore
import NookWeb

enum WebContextMenuItem {
    case pageBack
    case pageForward
    case pageReload
    case pageCopyAddress
    case pageTranslate
    case pagePrint
    case pageViewSource

    case linkOpenInNewTab
    case linkOpenInNewWindow
    case linkOpenInSplitView
    case linkSaveAs
    case linkCopy

    case imageOpenInNewTab
    case imageSaveToDownloads
    case imageSaveAs
    case imageCopyAddress

    case textCopy

    case separator

    case systemLookUp
    case systemTranslate
    case systemShare
    case systemInspect
    case systemImageCopy

    @MainActor
    static func buildMenuItems(
        for payload: WebContextMenuPayload,
        on webView: FocusableWKWebView,
        baseMenu: NSMenu
    ) -> [NSMenuItem] {
        let items = cleanedItems(content(for: payload))
        return items.compactMap { $0.makeMenuItem(on: webView, payload: payload, baseMenu: baseMenu) }
    }

    private static func content(for payload: WebContextMenuPayload) -> [WebContextMenuItem] {
        switch payload {
        case .page:
            return [.pageBack, .pageForward, .pageReload, .separator, .pageCopyAddress, .pagePrint, .pageTranslate, .separator, .pageViewSource, .systemInspect]
        case .ignored:
            return []
        default:
            // Link first, then image, then the selection; Share and Inspect once at the end,
            // since a system item added to the menu twice throws.
            let parts = payload.parts.sorted { $0.menuRank < $1.menuRank }
            return parts.flatMap { section(for: $0) + [.separator] } + [.systemShare, .separator, .systemInspect]
        }
    }

    private static func section(for payload: WebContextMenuPayload) -> [WebContextMenuItem] {
        switch payload {
        case .link:
            return [.linkOpenInNewTab, .linkOpenInNewWindow, .linkOpenInSplitView, .separator, .linkSaveAs, .linkCopy]
        case .image:
            return [.imageOpenInNewTab, .separator, .imageSaveToDownloads, .imageSaveAs, .separator, .imageCopyAddress, .systemImageCopy]
        case .textSelection:
            return [.systemLookUp, .systemTranslate, .textCopy]
        default:
            return []
        }
    }

    private static func cleanedItems(_ items: [WebContextMenuItem]) -> [WebContextMenuItem] {
        var result: [WebContextMenuItem] = []
        var previousSeparator = false

        for item in items {
            if item == .separator {
                if previousSeparator { continue }
                previousSeparator = true
            } else {
                previousSeparator = false
            }
            result.append(item)
        }

        while result.last == .separator {
            result.removeLast()
        }

        return result
    }

    @MainActor
    private func makeMenuItem(
        on webView: FocusableWKWebView,
        payload: WebContextMenuPayload,
        baseMenu: NSMenu
    ) -> NSMenuItem? {
        switch self {
        case .separator:
            return NSMenuItem.separator()
        case .systemLookUp, .systemTranslate, .systemShare, .systemInspect, .systemImageCopy:
            guard let identifier = systemIdentifier,
                  let existing = baseMenu.items.first(where: { $0.identifier == identifier })
            else { return nil }
            return existing
        default:
            guard let title = title(on: webView) else { return nil }
            let item = HandlerMenuItem(title: title) { [weak webView] _ in
                guard let webView else { return }
                self.performAction(on: webView, payload: payload)
            }
            item.isEnabled = isEnabled(context: webView)
            return item
        }
    }

    @MainActor
    private func title(on webView: FocusableWKWebView) -> String? {
        switch self {
        case .pageBack: return "Back"
        case .pageForward: return "Forward"
        case .pageReload: return "Reload Page"
        case .pageCopyAddress: return "Copy Page Address"
        case .pageTranslate: return webView.owningSession?.isTranslated == true ? "Show Original" : "Translate Page"
        case .pagePrint: return "Print…"
        case .pageViewSource: return "View Page Source"
        case .linkOpenInNewTab: return "Open Link in New Tab"
        // A new window is a regular one, so a private page leaves it out.
        case .linkOpenInNewWindow: return webView.owningSession?.isPrivate == true ? nil : "Open Link in New Window"
        case .linkOpenInSplitView: return "Open Link in Split View"
        case .linkSaveAs: return "Save Link As…"
        case .linkCopy: return "Copy Link"
        case .imageOpenInNewTab: return "Open Image in New Tab"
        case .imageSaveToDownloads: return "Save Image to Downloads"
        case .imageSaveAs: return "Save Image As…"
        case .imageCopyAddress: return "Copy Image Address"
        case .textCopy: return "Copy"
        case .separator, .systemLookUp, .systemTranslate, .systemShare, .systemInspect, .systemImageCopy:
            return nil
        }
    }

    private var systemIdentifier: NSUserInterfaceItemIdentifier? {
        switch self {
        case .systemLookUp: return .webKitTextLookUp
        case .systemTranslate: return .webKitTextTranslate
        case .systemShare: return .webKitSharing
        case .systemInspect: return .webKitInspectElement
        case .systemImageCopy: return .webKitCopyImage
        default: return nil
        }
    }

    @MainActor
    private func isEnabled(context: FocusableWKWebView) -> Bool {
        switch self {
        case .pageBack: return context.canGoBack || context.owningSession?.canGoBackOrReturn == true
        case .pageForward: return context.canGoForward
        case .pageTranslate: return context.owningSession?.canTranslate == true
        default: return true
        }
    }

    @MainActor
    private func performAction(on webView: FocusableWKWebView, payload: WebContextMenuPayload) {
        switch self {
        case .pageBack:
            if let session = webView.owningSession { session.goBack(in: webView) } else { webView.goBack() }
        case .pageForward:
            webView.goForward()
        case .pageTranslate:
            webView.owningSession?.toggleTranslation()
        case .pageReload:
            webView.reload()
        case .pageCopyAddress:
            if let url = payload.pageURL ?? webView.owningSession?.url {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case .linkOpenInNewTab:
            if let url = payload.linkURL {
                webView.openLinkInNewTab(url)
            }
        case .pagePrint:
            webView.nookPrint()
        case .pageViewSource:
            webView.showPageSource()
        case .linkOpenInNewWindow:
            if let url = payload.linkURL {
                webView.openLinkInNewWindow(url)
            }
        case .linkOpenInSplitView:
            if let url = payload.linkURL {
                webView.openLinkInSplitView(url)
            }
        case .linkSaveAs:
            if let url = payload.linkURL {
                webView.saveLink(url)
            }
        case .linkCopy:
            if let url = payload.linkURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case .imageOpenInNewTab:
            if let url = payload.imageURL {
                webView.openLinkInNewTab(url)
            }
        case .imageSaveToDownloads:
            webView.downloadImage(identifier: payload.imageSourceString)
        case .imageSaveAs:
            webView.downloadImage(identifier: payload.imageSourceString, promptForLocation: true)
        case .imageCopyAddress:
            if let url = payload.imageURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case .textCopy:
            if let text = payload.textSelection {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        default:
            break
        }
    }
}

private extension WebContextMenuPayload {
    var parts: [WebContextMenuPayload] {
        if case .multiple(let payloads) = self { return payloads.flatMap(\.parts) }
        return [self]
    }

    var menuRank: Int {
        switch self {
        case .link: return 0
        case .image: return 1
        case .textSelection: return 2
        default: return 3
        }
    }
}

@MainActor
final class HandlerMenuItem: NSMenuItem {
    private let handler: (NSMenuItem) -> Void

    init(title: String, handler: @escaping (NSMenuItem) -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(handleAction(_:)), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleAction(_ sender: NSMenuItem) {
        handler(sender)
    }
}

extension FocusableWKWebView {
    /// Opens `url` in the background in the owning page's window and space. A middle click
    /// on a link takes the same path, so the placement and scheme rules live on the session.
    func openLinkInNewTab(_ url: URL) {
        owningSession?.openInNewTab(url)
    }

    private var browserManager: BrowserManager? {
        owningSession?.controller?.sessionDelegate as? BrowserManager
    }

    /// Opens `url` in a new regular window on the page's space.
    func openLinkInNewWindow(_ url: URL) {
        guard let browserManager, let spaceID = owningSession.flatMap({ browserManager.tabs.window(for: $0) })?.spaceID else { return }
        browserManager.createNewWindow { window in
            browserManager.tabs.setSpace(spaceID, in: window)
            _ = browserManager.tabs.open(url: url, in: window, placement: .newTab)
        }
    }

    /// Opens `url` as a trail child and pairs it with the window's selection.
    func openLinkInSplitView(_ url: URL) {
        guard let browserManager, let session = owningSession,
              let window = browserManager.tabs.window(for: session),
              let itemID = browserManager.tabs.open(url: url, in: window, placement: .background, from: session.itemID)
        else { return }
        browserManager.splitManager.enterSplit(with: itemID, in: window)
    }

    /// Downloads `url` with the page's cookies, asking where to save it.
    func saveLink(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        startDownload(using: URLRequest(url: url)) { download in
            _ = DownloadManager.shared.addDownload(
                download,
                originalURL: url,
                suggestedFilename: url.lastPathComponent,
                destinationPreference: .askUser
            )
        }
    }

    /// The Web Inspector's Sources tab, the way Safari shows source. `_inspector` is SPI.
    func showPageSource() {
        let selector = NSSelectorFromString("_inspector")
        guard responds(to: selector),
              let inspector = perform(selector)?.takeUnretainedValue() as? NSObject else { return }
        for name in ["show", "attach", "showResources"] where inspector.responds(to: NSSelectorFromString(name)) {
            inspector.perform(NSSelectorFromString(name))
        }
    }

    func downloadImage(from url: URL?, promptForLocation: Bool = false) {
        guard let identifier = url?.absoluteString else { return }
        handleImageDownload(identifier: identifier, promptForLocation: promptForLocation)
    }

    func downloadImage(identifier: String?, promptForLocation: Bool = false) {
        guard let identifier else { return }
        handleImageDownload(identifier: identifier, promptForLocation: promptForLocation)
    }
}
