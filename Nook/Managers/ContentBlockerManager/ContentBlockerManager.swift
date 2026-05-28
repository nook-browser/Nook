//
//  ContentBlockerManager.swift
//  Nook
//
//  Orchestrator for native ad blocking.
//  Manages enable/disable, per-domain whitelist, per-tab disable, OAuth exemption.
//  Coordinates filter download, compilation, and injection via three layers:
//  - Network blocking (WKContentRuleList)
//  - Cosmetic filtering (CSS injection via WKUserScript)
//  - Scriptlet injection (JS main-world WKUserScript via AdGuard Scriptlets corelibs)
//

import Foundation
import WebKit
import OSLog

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentBlockerManager {
    weak var browserManager: BrowserManager?
    private(set) var isEnabled: Bool = false
    private(set) var isCompiling: Bool = false

    let filterListManager = FilterListManager()
    private let advancedBlockingEngine = AdvancedBlockingEngine()

    private var compiledRuleLists: [WKContentRuleList] = []
    private var updateTimer: Timer?
    private static let updateInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    private var thirdPartyCookieScript: WKUserScript {
        let js = """
        (function() {
          try {
            if (window.top === window) return;
            var ref = document.referrer || "";
            var thirdParty = false;
            try {
              var refHost = ref ? new URL(ref).hostname : null;
              thirdParty = !!refHost && refHost !== window.location.hostname;
            } catch (e) { thirdParty = false; }
            if (!thirdParty) return;
            Object.defineProperty(document, 'cookie', {
              configurable: false, enumerable: false,
              get: function() { return ''; },
              set: function(_) { return true; }
            });
            try {
              document.requestStorageAccess = function() { return Promise.reject(new DOMException('Blocked by Nook', 'NotAllowedError')); };
            } catch (e) {}
          } catch (e) {}
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
        if let wv = tab.existingWebView {
            removeBlocking(from: wv)
            wv.reloadFromOrigin()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak tab] in
            guard let self, let tab else { return }
            if let exp = self.temporarilyDisabledTabs[tab.id], exp <= Date() {
                self.temporarilyDisabledTabs.removeValue(forKey: tab.id)
                if self.shouldApplyBlocking(to: tab), let wv = tab.existingWebView {
                    self.applyBlocking(to: wv)
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func allowDomain(_ host: String, allowed: Bool = true) {
        let norm = host.lowercased()
        if allowed { allowedDomains.insert(norm) } else { allowedDomains.remove(norm) }

        // Persist to settings
        browserManager?.nookSettings?.adBlockerWhitelist = Array(allowedDomains)

        if let bm = browserManager {
            for tab in bm.tabManager.allTabs() {
                if tab.existingWebView?.url?.host?.lowercased() == norm, let wv = tab.existingWebView {
                    if allowed { removeBlocking(from: wv) } else { applyBlocking(to: wv) }
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func isDomainAllowed(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return allowedDomains.contains(h)
    }

    // MARK: - Lifecycle

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager

        // Hydrate whitelist from persisted settings
        if let whitelist = browserManager.nookSettings?.adBlockerWhitelist {
            allowedDomains = Set(whitelist.map { $0.lowercased() })
        }

        // Hydrate enabled optional filter lists
        if let enabled = browserManager.nookSettings?.enabledOptionalFilterLists {
            filterListManager.enabledOptionalFilterListFilenames = Set(enabled)
        }
    }

    func setEnabled(_ enabled: Bool) {
        cbLog.info("setEnabled(\(enabled)) — current isEnabled=\(self.isEnabled)")
        guard enabled != isEnabled else { return }
        if !enabled {
            isEnabled = false
            deactivateBlocking()
        } else {
            Task { @MainActor in
                await activateBlocking()
                isEnabled = true
                cbLog.info("Content blocker fully activated")
            }
        }
    }

    // MARK: - Activation

    private func activateBlocking() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        isCompiling = true

        // Download filter lists if we have none cached
        if !filterListManager.hasCachedLists {
            cbLog.info("No cached filter lists — downloading")
            await filterListManager.downloadAllLists()
            cbLog.info("Download completed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))s")
        }

        // Load raw filter text
        let loadStart = CFAbsoluteTimeGetCurrent()
        let rules = await Task.detached(priority: .userInitiated) { [filterListManager] in
            filterListManager.loadAllFilterRulesAsLines()
        }.value
        cbLog.info("Loaded \(rules.count) filter rules in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - loadStart))s")

        // Compile via SafariConverterLib → WKContentRuleLists + advancedRulesText
        let compileStart = CFAbsoluteTimeGetCurrent()
        let result = await ContentRuleListCompiler.compile(rules: rules)
        compiledRuleLists = result.ruleLists
        cbLog.info("Compile completed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - compileStart))s")

        // Configure advanced blocking engine with scriptlet/CSS rules
        advancedBlockingEngine.configure(advancedRulesText: result.advancedRulesText)

        isCompiling = false

        // Register applicator for new tab controllers
        BrowserConfiguration.shared.contentRuleListApplicator = { [weak self] controller in
            self?.applyRuleLists(to: controller)
        }

        // Apply to shared configuration and existing webviews
        applyToSharedConfiguration()
        applyToExistingWebViews()

        // Post update notification
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        // Record initial download timestamp
        if browserManager?.nookSettings?.adBlockerLastUpdate == nil {
            browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        }

        // Schedule periodic filter list updates
        scheduleAutoUpdate()

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        cbLog.info("Activated with \(self.compiledRuleLists.count) rule list(s) in \(String(format: "%.2f", totalTime))s total")
    }

    private func deactivateBlocking() {
        updateTimer?.invalidate()
        updateTimer = nil

        BrowserConfiguration.shared.contentRuleListApplicator = nil

        removeFromSharedConfiguration()
        removeFromExistingWebViews()

        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        cbLog.info("Deactivated")
    }

    // MARK: - Filter List Updates

    /// Update filter lists from remote sources. Returns true if lists were updated and recompiled.
    func updateFilterLists() async -> Bool {
        guard isEnabled else { return false }

        isCompiling = true
        let updated = await filterListManager.downloadAllLists()

        if updated {
            let rules = filterListManager.loadAllFilterRulesAsLines()
            let result = await ContentRuleListCompiler.compile(rules: rules)
            compiledRuleLists = result.ruleLists
            advancedBlockingEngine.configure(advancedRulesText: result.advancedRulesText)

            applyToSharedConfiguration()
            applyToExistingWebViews()

            browserManager?.nookSettings?.adBlockerLastUpdate = Date()

            cbLog.info("Filter lists updated and recompiled")
        }

        isCompiling = false
        return updated
    }

    /// Force recompile all filter lists (e.g. after enabling/disabling an optional list).
    func recompileFilterLists() async {
        guard isEnabled else { return }

        isCompiling = true

        // Download any lists we don't have cached yet
        await filterListManager.downloadAllLists()

        // Load and compile
        let rules = await Task.detached(priority: .userInitiated) { [filterListManager] in
            filterListManager.loadAllFilterRulesAsLines()
        }.value

        let result = await ContentRuleListCompiler.compile(rules: rules)
        compiledRuleLists = result.ruleLists
        advancedBlockingEngine.configure(advancedRulesText: result.advancedRulesText)

        applyToSharedConfiguration()
        applyToExistingWebViews()

        browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        isCompiling = false
        cbLog.info("Filter lists recompiled")
    }

    // MARK: - Auto-Update

    private func scheduleAutoUpdate() {
        updateTimer?.invalidate()

        // Check if an update is due now (>24h since last update)
        if let lastUpdate = browserManager?.nookSettings?.adBlockerLastUpdate {
            let elapsed = Date().timeIntervalSince(lastUpdate)
            if elapsed >= Self.updateInterval {
                Task { await updateFilterLists() }
            }
        }

        // Schedule repeating timer for daily checks
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateFilterLists()
            }
        }
        updateTimer?.tolerance = 60 * 60  // 1 hour tolerance for energy efficiency
    }

    // MARK: - Per-Navigation Injection

    /// Set up content blocker scripts for a navigation. Called from Tab's decidePolicyFor.
    func setupContentBlockerScripts(for url: URL, in webView: WKWebView, tab: Tab) {
        guard isEnabled else { return }

        // For exempted navigations, remove all blocking (including WKContentRuleList) and return
        if isDomainAllowed(url.host) || isTemporarilyDisabled(tabId: tab.id) || tab.isOAuthFlow {
            removeBlocking(from: webView)
            return
        }

        // Ensure network-level blocking is active (may have been removed for a previous allowed-domain navigation)
        applyBlocking(to: webView)

        let ucc = webView.configuration.userContentController

        // Remove previous content blocker scripts (identified by marker comment)
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter { !$0.source.hasPrefix(marker) }
        if remaining.count != ucc.userScripts.count {
            ucc.removeAllUserScripts()
            remaining.forEach { ucc.addUserScript($0) }
        }

        // Inject all advanced blocking scripts (scriptlets + CSS + cosmetic)
        let scripts = advancedBlockingEngine.userScripts(for: url)
        for script in scripts {
            ucc.addUserScript(script)
        }

        let host = url.host ?? "unknown"
        cbLog.info("setupScripts for \(host, privacy: .public): \(scripts.count) advanced scripts, ruleLists=\(self.compiledRuleLists.count)")
    }

    /// Fallback injection after didFinish — re-inject cosmetic CSS if scripts didn't take.
    func injectFallbackScripts(for url: URL, in webView: WKWebView, tab: Tab) {
        guard isEnabled else { return }
        guard !isDomainAllowed(url.host) else { return }
        guard !isTemporarilyDisabled(tabId: tab.id) else { return }
        guard !tab.isOAuthFlow else { return }

        // Re-inject CSS/cosmetic scripts as fallback
        let scripts = advancedBlockingEngine.userScripts(for: url)
        for script in scripts {
            webView.evaluateJavaScript(script.source) { _, error in
                if let error {
                    cbLog.warning("Fallback injection error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Rule List Application (for BrowserConfig)

    /// Apply compiled rule lists to a WKUserContentController.
    func applyRuleLists(to controller: WKUserContentController) {
        guard isEnabled else { return }
        for list in compiledRuleLists {
            controller.add(list)
        }
        if !controller.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            controller.addUserScript(thirdPartyCookieScript)
        }
    }

    // MARK: - Shared Configuration

    private func applyToSharedConfiguration() {
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists {
            ucc.add(list)
        }
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeFromSharedConfiguration() {
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter {
            !$0.source.contains("document.referrer") && !$0.source.hasPrefix(marker)
        }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    // MARK: - Per-WebView Helpers

    func shouldApplyBlocking(to tab: Tab) -> Bool {
        if !isEnabled { return false }
        if isTemporarilyDisabled(tabId: tab.id) { return false }
        if isDomainAllowed(tab.existingWebView?.url?.host) { return false }
        if tab.isOAuthFlow { return false }
        return true
    }

    private func applyBlocking(to webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists {
            ucc.add(list)
        }
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeBlocking(from webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter {
            !$0.source.contains("document.referrer") && !$0.source.hasPrefix(marker)
        }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    private func applyToExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            if shouldApplyBlocking(to: tab) {
                applyBlocking(to: wv)
            } else {
                removeBlocking(from: wv)
            }
        }
    }

    private func removeFromExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            removeBlocking(from: wv)
        }
    }

    func refreshFor(tab: Tab) {
        guard let wv = tab.existingWebView else { return }
        if shouldApplyBlocking(to: tab) {
            applyBlocking(to: wv)
        } else {
            removeBlocking(from: wv)
        }
        wv.reloadFromOrigin()
    }
}
