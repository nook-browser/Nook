//
//  TrackingProtectionManager.swift
//  Pulse
//
//  Provides opt-in cross-site tracking protections using a combination of
//  WKContentRuleList (tracker domain/resource blocking) and a conservative
//  third‑party storage shim for iframes. New and existing WKWebViews are updated
//  when the setting changes.
//
import Foundation
import WebKit

@MainActor
final class TrackingProtectionManager {
    weak var browserManager: BrowserManager?
    private(set) var isEnabled: Bool = false

    private let ruleListIdentifier = "PulseTrackingBlocker"
    private var installedRuleList: WKContentRuleList?
    private var thirdPartyCookieScript: WKUserScript {
        // Disable document.cookie in third‑party iframes (based on referrer host)
        let js = """
        (function() {
          try {
            // Detect if current document is embedded by a different host
            var ref = document.referrer || "";
            var thirdParty = false;
            try {
              var refHost = ref ? new URL(ref).hostname : null;
              thirdParty = !!refHost && refHost !== window.location.hostname;
            } catch (e) { thirdParty = false; }
            if (!thirdParty) return;

            // Neuter document.cookie in this context and deny Storage Access API
            Object.defineProperty(document, 'cookie', {
              configurable: false,
              enumerable: false,
              get: function() { return ''; },
              set: function(_) { return true; }
            });
            try {
              document.requestStorageAccess = function() { return Promise.reject(new DOMException('Blocked by Pulse', 'NotAllowedError')); };
            } catch (e) {}
          } catch (e) {
            // best-effort; do nothing on failure
          }
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        Task { @MainActor in
            if enabled {
                await installRuleListIfNeeded()
                applyToSharedConfiguration()
                applyToExistingWebViews()
            } else {
                removeFromSharedConfiguration()
                removeFromExistingWebViews()
            }
        }
    }

    // MARK: - Installation
    private func installRuleListIfNeeded() async {
        // Try to fetch a cached compiled list first
        guard let store = WKContentRuleListStore.default() else { return }
        if let existing = await withCheckedContinuation({ (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.lookUpContentRuleList(forIdentifier: ruleListIdentifier) { list, _ in cont.resume(returning: list) }
        }) {
            self.installedRuleList = existing
            return
        }

        // Compile JSON rules (attempt cookie‑blocking first, then fallback to domain blocks only)
        let rules = Self.makeRuleJSON()
        var compiled = await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.compileContentRuleList(forIdentifier: ruleListIdentifier, encodedContentRuleList: rules) { list, error in
                if let error { print("[TrackingProtection] Rule compile error: \(error)") }
                cont.resume(returning: list)
            }
        }
        if compiled == nil {
            let fallback = Self.makeRuleJSON(blockCookies: false)
            compiled = await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
                store.compileContentRuleList(forIdentifier: ruleListIdentifier + ".fallback", encodedContentRuleList: fallback) { list, error in
                    if let error { print("[TrackingProtection] Fallback rule compile error: \(error)") }
                    cont.resume(returning: list)
                }
            }
        }
        if let compiled { self.installedRuleList = compiled }
    }

    private func applyToSharedConfiguration() {
        guard let list = installedRuleList else { return }
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        ucc.add(list)
        // Ensure the script is installed once
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeFromSharedConfiguration() {
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        // Remove our specific script (identified by referrer check)
        let remaining = ucc.userScripts.filter { !$0.source.contains("document.referrer") }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    private func applyToExistingWebViews() {
        guard let bm = browserManager else { return }
        let allTabs = bm.tabManager.allTabs()
        for tab in allTabs {
            guard let wv = tab.webView else { continue }
            if let list = installedRuleList {
                wv.configuration.userContentController.removeAllContentRuleLists()
                wv.configuration.userContentController.add(list)
            }
            let ucc = wv.configuration.userContentController
            if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
                ucc.addUserScript(thirdPartyCookieScript)
            }
            // Reload to apply rules consistently
            wv.reloadFromOrigin()
        }
    }

    private func removeFromExistingWebViews() {
        guard let bm = browserManager else { return }
        let allTabs = bm.tabManager.allTabs()
        for tab in allTabs {
            guard let wv = tab.webView else { continue }
            let ucc = wv.configuration.userContentController
            ucc.removeAllContentRuleLists()
            let remaining = ucc.userScripts.filter { !$0.source.contains("document.referrer") }
            ucc.removeAllUserScripts()
            remaining.forEach { ucc.addUserScript($0) }
            wv.reloadFromOrigin()
        }
    }

    // MARK: - Rules
    private static func makeRuleJSON(blockCookies: Bool = true) -> String {
        // Small built-in list of common tracking hosts and a generic third‑party cookie block.
        // If the 'block-cookies' action is unsupported, compile will fail; rule list store
        // will still return nil, and the manager will rely on domain block rules only.
        let trackers: [String] = [
            "google-analytics\\.com",
            "analytics\\.google\\.com",
            "googletagmanager\\.com",
            "googletagservices\\.com",
            "doubleclick\\.net",
            "facebook\\.net",
            "connect\\.facebook\\.net",
            "graph\\.facebook\\.com",
            "adsystem\\.com",
            "adservice\\.google\\.com",
            "hotjar\\.com",
            "segment\\.io",
            "cdn\\.segment\\.com",
            "mixpanel\\.com",
            "sentry\\.io",
            "optimizely\\.com",
            "newrelic\\.com",
            "clarity\\.ms",
        ]

        var rules: [[String: Any]] = []
        if blockCookies {
            // Attempt a third‑party cookie block
            rules.append([
                "trigger": [
                    "url-filter": ".*",
                    "load-type": ["third-party"]
                ],
                "action": ["type": "block-cookies"]
            ])
        }

        for host in trackers {
            rules.append([
                "trigger": ["url-filter": host],
                "action": ["type": "block"]
            ])
        }

        // Encode to JSON
        if let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }
}
