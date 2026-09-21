// Licensed under GPL-3.0. See LICENSE.
//
//  WebStoreScriptHandler.swift
//  Nook
//
//  Message handler for Chrome Web Store integration
//

import Foundation
import WebKit
import AppKit

@MainActor
final class WebStoreScriptHandler: NSObject, WKScriptMessageHandler {
    static let handlerName = "nookWebStore"

    /// The injector script and this handler live in their own content world, so scripts
    /// on a web page cannot reach `webkit.messageHandlers.nookWebStore`.
    static let contentWorld = WKContentWorld.world(name: "NookWebStore")

    private static let storeHosts: [String: ExtensionStore] = [
        "chromewebstore.google.com": .chrome,
        "chrome.google.com": .chrome,
        "microsoftedge.microsoft.com": .edge,
    ]

    /// The store for a URL whose host is exactly a known store host, or nil.
    static func store(for url: URL) -> ExtensionStore? {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        return storeHosts[host]
    }

    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Trust boundary: only the main frame of a real store page, in our isolated world.
        let origin = message.frameInfo.securityOrigin
        guard message.name == Self.handlerName,
              message.world == Self.contentWorld,
              message.frameInfo.isMainFrame,
              origin.protocol == "https",
              let store = Self.storeHosts[origin.host.lowercased()],
              let body = message.body as? [String: Any],
              body["action"] as? String == "installExtension",
              let extensionId = body["extensionId"] as? String,
              ExtensionStore.isValidExtensionID(extensionId)
        else { return }

        guard let extensionManager = browserManager?.extensionManager else {
            showErrorNotification(error: ExtensionError.unsupportedOS)
            return
        }

        // Installation shows its own permission confirmation before anything is loaded.
        extensionManager.installFromWebStore(extensionId: extensionId, store: store) { [weak self] result in
            Task { @MainActor in
                let success = if case .success = result { true } else { false }
                _ = try? await message.webView?.callAsyncJavaScript(
                    "window.dispatchEvent(new CustomEvent('nookInstallComplete', { detail: { success: success, extensionId: extensionId } }));",
                    arguments: ["success": success, "extensionId": extensionId],
                    in: nil,
                    contentWorld: Self.contentWorld
                )
                if case .failure(let error) = result, case .cancelled = error { return }
                if case .failure(let error) = result {
                    self?.showErrorNotification(error: error)
                }
            }
        }
    }

    private func showErrorNotification(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
