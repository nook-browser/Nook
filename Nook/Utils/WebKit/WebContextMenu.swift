// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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

    case linkOpenInNewTab
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
            return [.pageBack, .pageForward, .pageReload, .separator, .pageCopyAddress, .separator, .systemInspect]
        case .textSelection:
            return [.systemLookUp, .systemTranslate, .textCopy, .separator, .systemShare, .separator, .systemInspect]
        case .link:
            return [.linkOpenInNewTab, .separator, .linkCopy, .separator, .systemShare, .separator, .systemInspect]
        case .image:
            return [
                .imageOpenInNewTab,
                .separator,
                .imageSaveToDownloads,
                .imageSaveAs,
                .separator,
                .imageCopyAddress,
                .systemImageCopy,
                .separator,
                .systemShare,
                .separator,
                .systemInspect
            ]
        case .multiple(let payloads):
            return payloads.flatMap { content(for: $0) }
        case .ignored:
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
            guard let title = title else { return nil }
            let item = HandlerMenuItem(title: title) { [weak webView] _ in
                guard let webView else { return }
                self.performAction(on: webView, payload: payload)
            }
            item.isEnabled = isEnabled(context: webView)
            return item
        }
    }

    private var title: String? {
        switch self {
        case .pageBack: return "Back"
        case .pageForward: return "Forward"
        case .pageReload: return "Reload Page"
        case .pageCopyAddress: return "Copy Page Address"
        case .linkOpenInNewTab: return "Open Link in New Tab"
        case .linkCopy: return "Copy Link"
        case .imageOpenInNewTab: return "Open Image in New Tab"
        case .imageSaveToDownloads: return "Save Image to Downloads"
        case .imageSaveAs: return "Save Image As..."
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
        case .pageBack: return context.canGoBack
        case .pageForward: return context.canGoForward
        default: return true
        }
    }

    @MainActor
    private func performAction(on webView: FocusableWKWebView, payload: WebContextMenuPayload) {
        switch self {
        case .pageBack:
            webView.goBack()
        case .pageForward:
            webView.goForward()
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
    /// Opens `url` in the background in the owning page's window and space. A private page's
    /// window is private, so the link stays in that window's in-memory tree.
    func openLinkInNewTab(_ url: URL) {
        guard let session = owningSession, let tabs = session.controller,
              let window = tabs.window(for: session) else { return }
        let parent = tabs.spaceID(of: session.itemID).map { Parent.tabs(spaceID: $0) }
        tabs.open(url: url, in: window, placement: .background, parent: parent)
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
