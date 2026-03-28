//
//  ExtensionManager+Diagnostics.swift
//  Nook
//
//  Diagnostics, debugging utilities, and popup navigation/script message handling
//

import AppKit
import Foundation
import os
import WebKit

// MARK: - Debugging Utilities

@available(macOS 15.4, *)
extension ExtensionManager {

    /// Show debugging console for popup troubleshooting
    func showPopupConsole() {
        PopupConsole.shared.show()
    }
}

// MARK: - WKScriptMessageHandler (popup bridge)

@available(macOS 15.4, *)
extension ExtensionManager: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // No custom message handling
    }
}

// MARK: - WKNavigationDelegate (popup diagnostics)

@available(macOS 15.4, *)
extension ExtensionManager: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didStartProvisionalNavigation: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Started loading: \(urlString)")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didCommit: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Committed: \(urlString)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didFinish: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Finished: \(urlString)")

        // Get document title
        webView.evaluateJavaScript("document.title") { value, _ in
            let title = (value as? String) ?? "(unknown)"
            Self.logger.debug("[Popup] document.title: \"\(title)\"")
            PopupConsole.shared.log("[Document] Title: \(title)")
        }

        // Comprehensive capability probe for extension APIs
        let comprehensiveProbe = """
            (() => {
                const result = {
                    location: {
                        href: location.href,
                        protocol: location.protocol,
                        host: location.host
                    },
                    document: {
                        title: document.title,
                        readyState: document.readyState,
                        hasBody: !!document.body,
                        bodyText: document.body ? document.body.innerText.slice(0, 100) : null
                    },
                    apis: {
                        browser: typeof browser !== 'undefined',
                        chrome: typeof chrome !== 'undefined',
                        runtime: typeof (browser?.runtime || chrome?.runtime) !== 'undefined',
                        storage: {
                            available: typeof (browser?.storage || chrome?.storage) !== 'undefined',
                            local: typeof (browser?.storage?.local || chrome?.storage?.local) !== 'undefined',
                            sync: typeof (browser?.storage?.sync || chrome?.storage?.sync) !== 'undefined'
                        },
                        tabs: typeof (browser?.tabs || chrome?.tabs) !== 'undefined',
                        action: typeof (browser?.action || chrome?.action) !== 'undefined'
                    },
                    errors: []
                };

                // Check for common popup errors
                try {
                    if (typeof browser !== 'undefined' && browser.runtime) {
                        result.runtime = {
                            id: browser.runtime.id,
                            url: browser.runtime.getURL ? browser.runtime.getURL('') : 'getURL not available'
                        };
                    }
                } catch (e) {
                    result.errors.push('Runtime error: ' + e.message);
                }

                return result;
            })()
            """

        webView.evaluateJavaScript(comprehensiveProbe) { value, error in
            if let error = error {
                Self.logger.error("[Popup] comprehensive probe error: \(error.localizedDescription)")
                PopupConsole.shared.log(
                    "[Error] Probe failed: \(error.localizedDescription)"
                )
            } else if let dict = value as? [String: Any] {
                Self.logger.debug("[Popup] comprehensive probe: \(dict)")
                PopupConsole.shared.log("[Probe] APIs: \(dict)")
            } else {
                Self.logger.debug("[Popup] comprehensive probe: unexpected result type")
                PopupConsole.shared.log(
                    "[Warning] Probe returned unexpected result"
                )
            }
        }

        // Patch scripting.executeScript in popup context to avoid hard failures on unsupported targets
        let safeScriptingPatch = """
            (function(){
              try {
                if (typeof chrome !== 'undefined' && chrome.scripting && typeof chrome.scripting.executeScript === 'function') {
                  const originalExec = chrome.scripting.executeScript.bind(chrome.scripting);
                  chrome.scripting.executeScript = async function(opts){
                    try { return await originalExec(opts); }
                    catch (e) { console.warn('shim: executeScript failed', e); return []; }
                  };
                }
                if (typeof chrome !== 'undefined' && (!chrome.tabs || typeof chrome.tabs.executeScript !== 'function') && chrome.scripting && typeof chrome.scripting.executeScript === 'function') {
                  chrome.tabs = chrome.tabs || {};
                  chrome.tabs.executeScript = function(tabIdOrDetails, detailsOrCb, maybeCb){
                    function normalize(a,b,c){ let tabId, details, cb; if (typeof a==='number'){ tabId=a; details=b; cb=c; } else { details=a; cb=b; } return {tabId, details: details||{}, cb: (typeof cb==='function')?cb:null}; }
                    const { tabId, details, cb } = normalize(tabIdOrDetails, detailsOrCb, maybeCb);
                    const target = { tabId: tabId||undefined };
                    const files = details && (details.file ? [details.file] : details.files);
                    const code = details && details.code;
                    const opts = { target };
                    if (Array.isArray(files) && files.length) opts.files = files; else if (typeof code==='string') { opts.func = function(src){ try{(0,eval)(src);}catch(e){}}; opts.args=[code]; } else { const p = Promise.resolve([]); if (cb) { try{cb([]);}catch(_){} } return p; }
                    const p = chrome.scripting.executeScript(opts);
                    if (cb) { p.then(r=>{ try{cb(r);}catch(_){} }).catch(_=>{ try{cb([]);}catch(_){} }); }
                    return p;
                  };
                }
              } catch(_){}
            })();
            """
        webView.evaluateJavaScript(safeScriptingPatch) { _, err in
            if let err = err {
                Self.logger.error("[Popup] safeScriptingPatch error: \(err.localizedDescription)")
            }
        }

        // Note: Skipping automatic tabs.query test to avoid potential recursion issues
        // Extensions will call tabs.query naturally, and we can debug through console
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.error("[Popup] didFail: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log(
            "[Error] Navigation failed: \(error.localizedDescription)"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.error("[Popup] didFailProvisional: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log(
            "[Error] Provisional navigation failed: \(error.localizedDescription)"
        )
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Self.logger.debug("[Popup] content process terminated")
        PopupConsole.shared.log("[Critical] WebView process terminated")
    }
}

// MARK: - Extension Diagnostics

@available(macOS 15.4, *)
extension ExtensionManager {

    /// Probe the background webview after load to check for JS-level errors.
    /// Output goes to Xcode debug console via NSLog for easy visibility.
    func probeBackgroundHealth(for context: WKWebExtensionContext, name: String) {
        // First probe at 3s, second at 8s (gives boot saga time to complete/fail)
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let bgWV = (context as AnyObject).value(forKey: "_backgroundWebView") as? WKWebView else {
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
    @available(macOS 15.5, *)
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
            let bgWV = (ctx as AnyObject).value(forKey: "_backgroundWebView") as? WKWebView
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

// MARK: - Extension Resource Testing

@available(macOS 15.4, *)
extension ExtensionManager {

    /// List all installed extensions with their UUIDs for easy testing
    func listInstalledExtensionsForTesting() {
        Self.logger.info("Installed Extensions ===")

        if installedExtensions.isEmpty {
            Self.logger.error("No extensions installed")
            return
        }

        for (index, ext) in installedExtensions.enumerated() {
            Self.logger.debug("\(index + 1). \(ext.name)")
            Self.logger.debug("   UUID: \(ext.id)")
            Self.logger.debug("   Version: \(ext.version)")
            Self.logger.debug("   Manifest Version: \(ext.manifestVersion)")
            Self.logger.info("Enabled: \(ext.isEnabled)")
            Self.logger.debug("")
        }
    }
}
