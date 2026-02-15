//
//  TrackingProtectionManager.swift
//  Nook
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

    private let ruleListIdentifier = "NookTrackingBlocker"
    private var installedRuleList: WKContentRuleList?
    private var thirdPartyCookieScript: WKUserScript {
        // Disable document.cookie in third‑party iframes only (never main-frame)
        let js = """
        (function() {
          try {
            // Only act in embedded contexts
            if (window.top === window) return;
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
              document.requestStorageAccess = function() { return Promise.reject(new DOMException('Blocked by Nook', 'NotAllowedError')); };
            } catch (e) {}
          } catch (e) {
            // best-effort; do nothing on failure
          }
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Exceptions
    private var temporarilyDisabledTabs: [UUID: Date] = [:]
    private var allowedDomains: Set<String> = []

    func isTemporarilyDisabled(tabId: UUID) -> Bool {
        if let until = temporarilyDisabledTabs[tabId] {
            if until > Date() { return true }
            temporarilyDisabledTabs.removeValue(forKey: tabId)
        }
        return false
    }

    func disableTemporarily(for tab: Tab, duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        temporarilyDisabledTabs[tab.id] = until
        if let wv = tab.webView {
            removeTracking(from: wv)
            wv.reloadFromOrigin()
        }
        // Schedule re-apply after expiration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak tab] in
            guard let self, let tab else { return }
            // Cleanup expired entry
            if let exp = self.temporarilyDisabledTabs[tab.id], exp <= Date() {
                self.temporarilyDisabledTabs.removeValue(forKey: tab.id)
                if self.shouldApplyTracking(to: tab), let wv = tab.webView {
                    self.applyTracking(to: wv)
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func allowDomain(_ host: String, allowed: Bool = true) {
        let norm = host.lowercased()
        if allowed { allowedDomains.insert(norm) } else { allowedDomains.remove(norm) }
        // Update existing views for this host
        if let bm = browserManager {
            for tab in bm.tabManager.allTabs() {
                if tab.webView?.url?.host?.lowercased() == norm, let wv = tab.webView {
                    if allowed { removeTracking(from: wv) } else { applyTracking(to: wv) }
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func isDomainAllowed(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return allowedDomains.contains(h)
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
            if shouldApplyTracking(to: tab) {
                applyTracking(to: wv)
            } else {
                removeTracking(from: wv)
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
            removeTracking(from: wv)
            wv.reloadFromOrigin()
        }
    }

    // MARK: - Per-WebView helpers
    private func shouldApplyTracking(to tab: Tab) -> Bool {
        if !isEnabled { return false }
        if isTemporarilyDisabled(tabId: tab.id) { return false }
        if isDomainAllowed(tab.webView?.url?.host) { return false }
        // Never apply tracking protection to OAuth flow tabs
        if tab.isOAuthFlow { return false }
        return true
    }

    private func applyTracking(to webView: WKWebView) {
        guard let list = installedRuleList else { return }
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        ucc.add(list)
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeTracking(from webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        // Remove our specific script (identified by referrer check)
        let remaining = ucc.userScripts.filter { !$0.source.contains("document.referrer") }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    func refreshFor(tab: Tab) {
        guard let wv = tab.webView else { return }
        if shouldApplyTracking(to: tab) {
            applyTracking(to: wv)
        } else {
            removeTracking(from: wv)
        }
        wv.reloadFromOrigin()
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
