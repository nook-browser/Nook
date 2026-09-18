// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ExtensionManager+Diagnostics.swift
//  Nook
//
//  Debug-only diagnostics for extension background pages and content scripts
//

import AppKit
import Foundation
import os
import WebKit

// MARK: - Debugging Utilities

extension ExtensionManager {

    /// Show debugging console for popup troubleshooting
    func showPopupConsole() {
        PopupConsole.shared.show()
    }
}

// MARK: - Extension Diagnostics (Debug builds only)

#if DEBUG
extension ExtensionManager {

    /// The context's background webview via a private WebKit property. Checked with
    /// `responds(to:)` first: plain KVC on a renamed property raises and would crash.
    private func backgroundWebView(for context: WKWebExtensionContext) -> WKWebView? {
        let key = "_backgroundWebView"
        guard (context as NSObject).responds(to: NSSelectorFromString(key)) else { return nil }
        return (context as NSObject).value(forKey: key) as? WKWebView
    }

    /// Probe the background webview after load to check for JS-level errors.
    /// Output goes to Xcode debug console via NSLog for easy visibility.
    func probeBackgroundHealth(for context: WKWebExtensionContext, name: String) {
        // First probe at 3s, second at 8s (gives boot saga time to complete/fail)
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let bgWV = self.backgroundWebView(for: context) else {
                    NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s: No background webview found")
                    return
                }

                bgWV.evaluateJavaScript("""
                    (function() {
                        var b = typeof browser !== 'undefined' ? browser : (typeof chrome !== 'undefined' ? chrome : null);
                        if (!b) return JSON.stringify({error: 'No browser/chrome API available'});

                        var result = {
                            url: location.href,
                            apiNamespace: typeof browser !== 'undefined' ? 'browser' : 'chrome',
                            runtime: !!b.runtime,
                            runtimeId: b.runtime ? b.runtime.id : null,
                            alarms: !!b.alarms,
                            storage: !!b.storage,
                            storageLocal: !!(b.storage && b.storage.local),
                            storageSession: !!(b.storage && b.storage.session),
                            storageSync: !!(b.storage && b.storage.sync),
                            tabs: !!b.tabs,
                            scripting: !!b.scripting,
                            webNavigation: !!b.webNavigation,
                            permissions: !!b.permissions,
                            action: !!b.action,
                            notifications: !!b.notifications,
                            webRequest: !!b.webRequest,
                            declarativeNetRequest: !!b.declarativeNetRequest,
                            contextMenus: !!b.contextMenus,
                            commands: !!b.commands,
                            i18n: !!b.i18n,
                            windows: !!b.windows,
                        };

                        // Try to detect if there were uncaught errors
                        try {
                            if (b.runtime && b.runtime.lastError) {
                                result.lastError = b.runtime.lastError.message || String(b.runtime.lastError);
                            }
                        } catch(e) {}

                        return JSON.stringify(result, null, 2);
                    })()
                """) { result, error in
                    if let json = result as? String {
                        NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s background APIs:\\n\(json)")
                    } else if let error = error {
                        NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s probe FAILED: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Comprehensive diagnostic for extension content script + messaging state
    func diagnoseExtensionState(for webView: WKWebView, url: URL) {
        guard let controller = extensionController else {
            Self.logger.debug("No extension controller")
            return
        }

        let host = url.host ?? "?"
        let ctxCount = controller.extensionContexts.count
        let configCtrl = webView.configuration.webExtensionController
        let sameCtrl = configCtrl === controller

        Self.logger.debug("\(host): contexts=\(ctxCount), webviewHasCtrl=\(configCtrl != nil), sameCtrl=\(sameCtrl)")

        for (extId, ctx) in extensionContexts {
            let name = ctx.webExtension.displayName ?? extId
            let hasBackground = ctx.webExtension.hasBackgroundContent
            let hasInjected = ctx.webExtension.hasInjectedContent
            let baseURL = ctx.baseURL
            let perms = ctx.currentPermissions.map { String(describing: $0) }.joined(separator: ", ")
            let matchPatterns = ctx.grantedPermissionMatchPatterns.map { String(describing: $0) }.joined(separator: ", ")
            let urlAccess = ctx.permissionStatus(for: url)

            Self.logger.debug("'\(name)': hasBackground=\(hasBackground), hasInjected=\(hasInjected), baseURL=\(baseURL), urlAccess=\(urlAccess.rawValue)")
            Self.logger.debug("'\(name)' perms: \(perms)")
            Self.logger.debug("'\(name)' matchPatterns: \(matchPatterns)")

            // Try to reach background webview via KVC
            let bgWV = backgroundWebView(for: ctx)
            Self.logger.debug("'\(name)' bgWebView via KVC: \(bgWV != nil ? bgWV!.url?.absoluteString ?? "no-url" : "nil")")

            if let bgWV = bgWV {
                bgWV.evaluateJavaScript("""
                    (function() {
                        try {
                            var c = typeof chrome !== 'undefined' ? chrome : null;
                            return JSON.stringify({
                                url: location.href,
                                hasRuntime: !!(c && c.runtime),
                                runtimeId: (c && c.runtime) ? c.runtime.id : null,
                                hasOnConnect: !!(c && c.runtime && c.runtime.onConnect),
                                hasOnMessage: !!(c && c.runtime && c.runtime.onMessage)
                            });
                        } catch(e) {
                            return JSON.stringify({error: e.message});
                        }
                    })()
                """) { result, error in
                    let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
                    if let json = result as? String {
                        logger.debug("'\(name)' background: \(json)")
                    } else if let error = error {
                        logger.debug("'\(name)' background eval error: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Check page-side: Dark Reader styles
        webView.evaluateJavaScript("""
            JSON.stringify({
                drCount: document.querySelectorAll('style.darkreader, style[class*="darkreader"]').length,
                allStyles: document.querySelectorAll('style').length,
                scripts: document.querySelectorAll('script').length
            })
        """) { result, _ in
            let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
            if let json = result as? String {
                logger.debug("\(host) page: \(json)")
            }
        }

        // Check again after 3s to see if content scripts ran and then cleaned up
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            webView.evaluateJavaScript(
                "'drCount=' + document.querySelectorAll('style[class*=\"darkreader\"]').length"
            ) { result, _ in
                let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
                logger.debug("\(host) +3s: \(String(describing: result ?? "nil"))")
            }
        }
    }
}
#endif
