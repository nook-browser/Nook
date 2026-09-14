//
//  ContentBlockerManager.swift
//  Nook
//
//  Orchestrator for native ad blocking.
//  Manages enable/disable, per-domain whitelist, per-tab disable, OAuth exemption.
//  Three layers:
//  - Network blocking + simple element hiding: WKContentRuleList (native, out of process)
//  - Advanced rules (cosmetic CSS, extended CSS, scriptlets, JS): AdvancedRulesEngine lookup
//    + nook-advanced-blocking.js runtime injected in every frame
//  - Site-specific blockers (YouTube, Facebook, X): bundled scripts, main frame only
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import Foundation
import WebKit
import OSLog

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentBlockerManager: NSObject {
    weak var browserManager: BrowserManager?
    private(set) var isEnabled = false
    private(set) var isCompiling = false

    let filterListManager = FilterListManager()
    let advancedRulesEngine = AdvancedRulesEngine()
    private(set) var trackingParamStripper = TrackingParamStripper()
    let requestStatsEngine = RequestStatsEngine()
    static let requestStatsHandlerName = "nookRequestStats"

    /// In-flight activation; startup tab loading waits on it so the first page is protected.
    private(set) var activationTask: Task<Void, Never>?

    private var compiledRuleLists: [WKContentRuleList] = []
    private var updateTimer: Timer?
    /// How often to look for due lists; each list's own `! Expires:` decides whether it is fetched.
    private static let updateCheckInterval: TimeInterval = 60 * 60

    /// Webviews whose blocking has been removed (whitelisted domain, temporary disable, OAuth flow).
    private let exemptedWebViews = NSHashTable<WKWebView>.weakObjects()

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
        temporarilyDisabledTabs[tab.id] = Date().addingTimeInterval(duration)
        reconcileAndReload(tab)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak tab] in
            guard let self, let tab else { return }
            if let exp = self.temporarilyDisabledTabs[tab.id], exp <= Date() {
                self.temporarilyDisabledTabs.removeValue(forKey: tab.id)
                self.reconcileAndReload(tab)
            }
        }
    }

    func allowDomain(_ host: String, allowed: Bool = true) {
        let norm = host.lowercased()
        if allowed { allowedDomains.insert(norm) } else { allowedDomains.remove(norm) }
        browserManager?.nookSettings?.adBlockerWhitelist = Array(allowedDomains)

        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let h = tab.existingWebView?.url?.host?.lowercased(), h == norm || h.hasSuffix("." + norm) else { continue }
            reconcileAndReload(tab)
        }
    }

    /// Whitelist matches the host and any subdomain of it.
    func isDomainAllowed(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return allowedDomains.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    private func isExempt(_ tab: Tab, host: String?) -> Bool {
        !isEnabled || isTemporarilyDisabled(tabId: tab.id) || isDomainAllowed(host) || tab.isOAuthFlow
    }

    func shouldApplyBlocking(to tab: Tab) -> Bool {
        !isExempt(tab, host: tab.existingWebView?.url?.host)
    }

    private func reconcileAndReload(_ tab: Tab) {
        guard let wv = tab.existingWebView else { return }
        reconcile(wv, exempt: !shouldApplyBlocking(to: tab))
        wv.reloadFromOrigin()
    }

    // MARK: - Lifecycle

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager

        if let whitelist = browserManager.nookSettings?.adBlockerWhitelist {
            allowedDomains = Set(whitelist.map { $0.lowercased() })
        }
        if let enabled = browserManager.nookSettings?.enabledOptionalFilterLists {
            filterListManager.enabledOptionalFilterListFilenames = Set(enabled)
        }

        // Every new user content controller gets the reply handler (always) and rule lists (when enabled).
        BrowserConfiguration.shared.contentRuleListApplicator = { [weak self] controller in
            self?.configureNewController(controller)
        }
    }

    func setEnabled(_ enabled: Bool) {
        cbLog.info("setEnabled(\(enabled)) — current isEnabled=\(self.isEnabled)")
        guard enabled != isEnabled, !isCompiling else { return }
        if enabled {
            isCompiling = true  // set synchronously so a second setEnabled(true) before the Task starts is a no-op
            activationTask = Task { @MainActor in await activateBlocking() }
        } else {
            deactivateBlocking()
        }
    }

    // MARK: - Activation

    private func activateBlocking() async {
        let start = CFAbsoluteTimeGetCurrent()
        isCompiling = true

        // Bundled snapshots of every default list guarantee rules on first run; the
        // network refresh happens afterwards via scheduleAutoUpdate().
        await rebuild()

        isCompiling = false
        isEnabled = true
        applyToSharedConfiguration()
        applyToExistingWebViews()
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)
        scheduleAutoUpdate()

        cbLog.info("Activated with \(self.compiledRuleLists.count) rule list(s) in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
    }

    private func deactivateBlocking() {
        updateTimer?.invalidate()
        updateTimer = nil
        isEnabled = false
        removeFromSharedConfiguration()
        removeFromExistingWebViews()
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)
        cbLog.info("Deactivated")
    }

    /// Load rules (disk cache, else bundled snapshot), compile rule lists, build the advanced engine.
    private func rebuild() async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        let rules = await Task.detached(priority: .userInitiated) { [filterListManager] in
            filterListManager.loadAllFilterRulesAsLines()
        }.value
        cbLog.info("Loaded \(rules.count) filter rules in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - loadStart), privacy: .public)s")

        let compileStart = CFAbsoluteTimeGetCurrent()
        let result = await ContentRuleListCompiler.compile(rules: rules)
        compiledRuleLists = result.ruleLists
        cbLog.info("Compile completed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - compileStart), privacy: .public)s")

        await advancedRulesEngine.build(rulesText: result.advancedRulesText, reuseSerialized: result.fromCache)
        trackingParamStripper = await Task.detached(priority: .userInitiated) { TrackingParamStripper(rules: rules) }.value
        // Counting engine is not needed for the first paint; build it after activation returns.
        let hash = result.rulesHash
        Task { [requestStatsEngine] in await requestStatsEngine.build(rules: rules, hash: hash) }
    }

    // MARK: - Filter List Updates

    /// Update filter lists from remote sources. Returns true if lists were updated and recompiled.
    @discardableResult
    func updateFilterLists() async -> Bool {
        guard isEnabled, !isCompiling else { return false }
        isCompiling = true
        defer { isCompiling = false }

        let updated = await filterListManager.downloadAllLists()
        if updated {
            await rebuild()
            applyToSharedConfiguration()
            applyToExistingWebViews()
            cbLog.info("Filter lists updated and recompiled")
        }
        browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        return updated
    }

    /// Force recompile (e.g. after enabling/disabling an optional list).
    func recompileFilterLists() async {
        guard isEnabled, !isCompiling else { return }
        isCompiling = true
        defer { isCompiling = false }

        await filterListManager.downloadAllLists(force: true)
        await rebuild()
        applyToSharedConfiguration()
        applyToExistingWebViews()
        browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)
        cbLog.info("Filter lists recompiled")
    }

    private func scheduleAutoUpdate() {
        updateTimer?.invalidate()

        // Immediate check: only lists whose own expiry has elapsed are fetched (conditional GET).
        Task { await updateFilterLists() }

        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateFilterLists()
            }
        }
        updateTimer?.tolerance = 15 * 60
    }

    // MARK: - Tracking parameter removal ($removeparam)

    /// The URL with tracking parameters removed, or nil when nothing should change.
    func strippedTrackingParams(for url: URL, tab: Tab) -> URL? {
        guard isEnabled, !isExempt(tab, host: url.host) else { return nil }
        guard let stripped = trackingParamStripper.strip(url) else { return nil }
        cbLog.info("removeparam \(url.host ?? "-", privacy: .public): \(url.query?.count ?? 0, privacy: .public) -> \(stripped.query?.count ?? 0, privacy: .public) query chars")
        return stripped
    }

    // MARK: - Per-Navigation (main frame, from Tab.decidePolicyFor)

    func setupContentBlockerScripts(for url: URL, in webView: WKWebView, tab: Tab) {
        guard isEnabled else { return }
        let exempt = isExempt(tab, host: url.host)
        reconcile(webView, exempt: exempt)
        tab.blockedRequestCount = 0
        let config = exempt ? nil : advancedRulesEngine.configUserScript(for: url)
        replaceConfigScript(in: webView.configuration.userContentController, with: config)
        cbLog.info("main frame \(url.host ?? "-", privacy: .public): exempt=\(exempt) config=\(config?.source.count ?? 0, privacy: .public)B ruleLists=\(self.compiledRuleLists.count)")
    }

    /// Swap the main-frame configuration script. It must precede the runtime script, so it goes first.
    private func replaceConfigScript(in ucc: WKUserContentController, with script: WKUserScript?) {
        let marker = AdvancedRulesEngine.configScriptMarker
        let existing = ucc.userScripts
        let hadConfig = existing.contains { $0.source.hasPrefix(marker) }
        guard hadConfig || script != nil else { return }
        ucc.removeAllUserScripts()
        if let script { ucc.addUserScript(script) }
        existing.filter { !$0.source.hasPrefix(marker) }.forEach { ucc.addUserScript($0) }
    }

    // MARK: - New controllers (from BrowserConfiguration.freshUserContentController)

    private func configureNewController(_ controller: WKUserContentController) {
        controller.addScriptMessageHandler(self, contentWorld: .page, name: AdvancedRulesEngine.messageHandlerName)
        controller.add(self, name: Self.requestStatsHandlerName)
        guard isEnabled else { return }
        for list in compiledRuleLists { controller.add(list) }
        // Static scripts arrive by copy from the shared configuration.
    }

    // MARK: - Shared Configuration

    private func applyToSharedConfiguration() {
        let ucc = BrowserConfiguration.shared.webViewConfiguration.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists { ucc.add(list) }
        ensureStaticScripts(in: ucc)
    }

    private func removeFromSharedConfiguration() {
        let ucc = BrowserConfiguration.shared.webViewConfiguration.userContentController
        ucc.removeAllContentRuleLists()
        removeOwnScripts(from: ucc)
    }

    // MARK: - Per-WebView

    private func reconcile(_ webView: WKWebView, exempt: Bool) {
        let isExempt = exemptedWebViews.contains(webView)
        if exempt && !isExempt {
            removeBlocking(from: webView)
        } else if !exempt && isExempt {
            applyBlocking(to: webView)
        }
    }

    private func applyBlocking(to webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists { ucc.add(list) }
        ensureStaticScripts(in: ucc)
        exemptedWebViews.remove(webView)
    }

    private func removeBlocking(from webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        removeOwnScripts(from: ucc)
        exemptedWebViews.add(webView)
    }

    private func applyToExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            if shouldApplyBlocking(to: tab) { applyBlocking(to: wv) } else { removeBlocking(from: wv) }
        }
    }

    private func removeFromExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            removeBlocking(from: wv)
        }
        exemptedWebViews.removeAllObjects()
    }

    private func ensureStaticScripts(in ucc: WKUserContentController) {
        let marker = AdvancedRulesEngine.scriptMarker
        guard !ucc.userScripts.contains(where: { $0.source.hasPrefix(marker) }) else { return }
        AdvancedRulesEngine.staticUserScripts.forEach { ucc.addUserScript($0) }
    }

    private func removeOwnScripts(from ucc: WKUserContentController) {
        let markers = [AdvancedRulesEngine.scriptMarker, AdvancedRulesEngine.configScriptMarker]
        let remaining = ucc.userScripts.filter { script in !markers.contains { script.source.hasPrefix($0) } }
        guard remaining.count != ucc.userScripts.count else { return }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    private func tab(for webView: WKWebView) -> Tab? {
        browserManager?.tabManager.allTabs().first { $0.existingWebView === webView }
    }
}

// MARK: - Subframe lookups (nook-advanced-blocking.js asks by its own frame URL)

extension ContentBlockerManager: WKScriptMessageHandlerWithReply {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard isEnabled, let webView = message.webView else { replyHandler(nil, nil); return }

        let body = message.body as? [String: Any]
        let frameURL = message.frameInfo.request.url
            ?? (body?["url"] as? String).flatMap { URL(string: $0) }
        guard let pageUrl = frameURL, let scheme = pageUrl.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            replyHandler(nil, nil); return
        }

        let topUrl = webView.url
        if let tab = tab(for: webView) {
            if isExempt(tab, host: topUrl?.host) { replyHandler(nil, nil); return }
        } else if isDomainAllowed(topUrl?.host) {
            replyHandler(nil, nil); return
        }

        let conf = advancedRulesEngine.configuration(for: pageUrl, topUrl: message.frameInfo.isMainFrame ? nil : topUrl)
        cbLog.info("frame lookup \(pageUrl.host ?? "-", privacy: .public) main=\(message.frameInfo.isMainFrame) rules=\(conf == nil ? 0 : 1, privacy: .public)")
        replyHandler(conf, nil)
    }
}

// MARK: - Blocked-request counting (nook-request-stats.js reports observed resource URLs)

extension ContentBlockerManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isEnabled, message.name == Self.requestStatsHandlerName,
              let webView = message.webView, let tab = tab(for: webView),
              let body = message.body as? [String: Any],
              let raw = body["requests"] as? [[String: Any]] else { return }
        let requests: [(url: String, type: String)] = raw.compactMap {
            guard let u = $0["url"] as? String, let t = $0["type"] as? String else { return nil }
            return (u, t)
        }
        guard !requests.isEmpty else { return }
        let source = message.frameInfo.request.url?.absoluteString ?? webView.url?.absoluteString ?? ""
        Task { [requestStatsEngine, weak tab] in
            let n = await requestStatsEngine.blockedCount(of: requests, sourceURL: source)
            if n > 0, let tab {
                await MainActor.run { tab.blockedRequestCount += n }
                cbLog.debug("stats: \(n, privacy: .public)/\(requests.count, privacy: .public) blocked for \(URL(string: source)?.host ?? "-", privacy: .public)")
            }
        }
    }
}
