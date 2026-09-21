// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ContentBlockerManager.swift
//  Nook
//
//  Orchestrator for native ad blocking.
//  Manages enable/disable, per-domain whitelist, per-tab disable, OAuth exemption.
//  Three layers:
//  - Network blocking + simple element hiding: WKContentRuleList (native, out of process)
//  - Cosmetic rules the rule list cannot express (procedural filters):
//    AdvancedRulesEngine lookup + nook-cosmetic.js injected in every frame
//  - Site-specific blockers (YouTube, Facebook, X): bundled scripts, main frame only
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import Foundation
import NookSettings
import WebKit
import OSLog

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
public final class ContentBlockerManager: NSObject {
    public weak var host: ContentBlockerHost?
    private let settings: NookSettingsService
    public private(set) var isEnabled = false
    public private(set) var isCompiling = false

    public init(settings: NookSettingsService) {
        self.settings = settings
        super.init()
    }

    public let filterListManager = FilterListManager()
    public let advancedRulesEngine = AdvancedRulesEngine()
    public private(set) var trackingParamStripper = TrackingParamStripper()
    private var lastRulesHash: String?

    /// In-flight activation; startup tab loading waits on it so the first page is protected.
    public private(set) var activationTask: Task<Void, Never>?
    private var hasActivated = false

    private var compiledRuleLists: [WKContentRuleList] = []
    private var updateTimer: Timer?
    /// How often to look for due lists; each list's own `! Expires:` decides whether it is fetched.
    private static let updateCheckInterval: TimeInterval = 60 * 60

    /// Webviews whose blocking has been removed (whitelisted domain, temporary disable, OAuth flow).
    private let exemptedWebViews = NSHashTable<WKWebView>.weakObjects()

    // MARK: - Exceptions

    private var temporarilyDisabledTabs: [UUID: Date] = [:]
    private var allowedDomains: Set<String> = []

    public func isTemporarilyDisabled(tabId: UUID) -> Bool {
        if let until = temporarilyDisabledTabs[tabId] {
            if until > Date() { return true }
            temporarilyDisabledTabs.removeValue(forKey: tabId)
        }
        return false
    }

    public func disableTemporarily(for session: any BlockablePage, duration: TimeInterval) {
        temporarilyDisabledTabs[session.itemID] = Date().addingTimeInterval(duration)
        reconcileAndReload(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak session] in
            guard let self, let session else { return }
            if let exp = self.temporarilyDisabledTabs[session.itemID], exp <= Date() {
                self.temporarilyDisabledTabs.removeValue(forKey: session.itemID)
                self.reconcileAndReload(session)
            }
        }
    }

    public func allowDomain(_ host: String, allowed: Bool = true) {
        let norm = host.lowercased()
        if allowed { allowedDomains.insert(norm) } else { allowedDomains.remove(norm) }
        settings.adBlockerWhitelist = Array(allowedDomains)

        for session in self.host?.blockablePages ?? [] {
            guard let h = session.webView?.url?.host?.lowercased(), h == norm || h.hasSuffix("." + norm) else { continue }
            reconcileAndReload(session)
        }
    }

    /// Whitelist matches the host and any subdomain of it.
    public func isDomainAllowed(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return allowedDomains.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    private func isExempt(itemID: UUID, isOAuthFlow: Bool, host: String?) -> Bool {
        !isEnabled || isTemporarilyDisabled(tabId: itemID) || isDomainAllowed(host) || isOAuthFlow
    }

    private func isExempt(_ session: any BlockablePage, host: String?) -> Bool {
        isExempt(itemID: session.itemID, isOAuthFlow: session.isOAuthFlow, host: host)
    }

    public func shouldApplyBlocking(to session: any BlockablePage) -> Bool {
        !isExempt(session, host: session.webView?.url?.host)
    }

    private func reconcileAndReload(_ session: any BlockablePage) {
        guard let wv = session.webView else { return }
        reconcile(wv, exempt: !shouldApplyBlocking(to: session))
        wv.reloadFromOrigin()
    }

    // MARK: - Lifecycle

    public func attach(host: ContentBlockerHost) {
        self.host = host

        allowedDomains = Set(settings.adBlockerWhitelist.map { $0.lowercased() })
        filterListManager.enabledOptionalFilterListFilenames = Set(settings.enabledOptionalFilterLists)

        // Every new user content controller gets the reply handler (always) and rule lists (when enabled).
        host.onNewUserContentController { [weak self] controller in
            self?.configureNewController(controller)
        }
    }

    public func setEnabled(_ enabled: Bool) {
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
        // Later activations are a Settings toggle: those pages were loaded unblocked on purpose.
        let isFirstActivation = !hasActivated
        hasActivated = true
        applyToExistingWebViews(reloadingPagesLoadedWithoutBlocking: isFirstActivation)
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
        let enabledFilenames = filterListManager.enabledOptionalFilterListFilenames
        let rules = await Task.detached(priority: .userInitiated) { [filterListManager] in
            filterListManager.loadAllFilterRulesAsLines(enabledFilenames: enabledFilenames)
        }.value
        cbLog.info("Loaded \(rules.count) filter rules in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - loadStart), privacy: .public)s")

        let compileStart = CFAbsoluteTimeGetCurrent()
        let result = await ContentRuleListCompiler.compile(rules: rules)
        compiledRuleLists = result.ruleLists
        cbLog.info("Compile completed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - compileStart), privacy: .public)s")

        await advancedRulesEngine.build(rules: rules)
        trackingParamStripper = await Task.detached(priority: .userInitiated) { TrackingParamStripper(rules: rules) }.value
        lastRulesHash = result.rulesHash
    }

    // MARK: - Filter List Updates

    /// Update filter lists from remote sources. Returns true if lists were updated and recompiled.
    @discardableResult
    public func updateFilterLists() async -> Bool {
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
        settings.adBlockerLastUpdate = Date()
        return updated
    }

    /// Force recompile (e.g. after enabling/disabling an optional list).
    public func recompileFilterLists() async {
        guard isEnabled, !isCompiling else { return }
        isCompiling = true
        defer { isCompiling = false }

        await filterListManager.downloadAllLists(force: true)
        await rebuild()
        applyToSharedConfiguration()
        applyToExistingWebViews()
        settings.adBlockerLastUpdate = Date()
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
    public func strippedTrackingParams(for url: URL, tab session: any BlockablePage) -> URL? {
        strippedTrackingParams(for: url, exempt: isExempt(session, host: url.host))
    }

    private func strippedTrackingParams(for url: URL, exempt: Bool) -> URL? {
        guard isEnabled, !exempt else { return nil }
        guard let stripped = trackingParamStripper.strip(url) else { return nil }
        cbLog.info("removeparam \(url.host ?? "-", privacy: .private(mask: .hash)): \(url.query?.count ?? 0, privacy: .public) -> \(stripped.query?.count ?? 0, privacy: .public) query chars")
        return stripped
    }

    // MARK: - Per-Navigation (main frame, from PageSession.decidePolicyFor)

    public func setupContentBlockerScripts(for url: URL, in webView: WKWebView, tab session: any BlockablePage) {
        guard isEnabled else { return }
        setupContentBlockerScripts(for: url, in: webView, exempt: isExempt(session, host: url.host))
    }

    private func setupContentBlockerScripts(for url: URL, in webView: WKWebView, exempt: Bool) {
        reconcile(webView, exempt: exempt)
        let config = exempt ? nil : advancedRulesEngine.configUserScript(for: url)
        replaceConfigScript(in: webView.configuration.userContentController, with: config)
        cbLog.info("main frame \(url.host ?? "-", privacy: .private(mask: .hash)): exempt=\(exempt) config=\(config?.source.count ?? 0, privacy: .public)B ruleLists=\(self.compiledRuleLists.count)")
    }

    /// Swap the main-frame configuration script. It must precede the runtime script, so it goes first.
    private func replaceConfigScript(in ucc: WKUserContentController, with script: WKUserScript?) {
        let marker = AdvancedRulesEngine.configScriptMarker
        // `userScripts` is bridged lazily from WebKit's NSArray; evaluate everything we need from it
        // BEFORE removeAllUserScripts(), or the stale proxy traps on the next index read (Release-only crash).
        let all = ucc.userScripts
        // Only Nook's own scripts are re-added; see WKUserScript+NookOwned.
        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) }
        let current = all.first { $0.source.hasPrefix(marker) }?.source

        // Nothing changed, so leave the list alone. WKUserContentController has no
        // remove-one API, so any edit costs one addUserScript IPC per surviving
        // script. configUserScript never returns nil, so the old `script != nil`
        // test was always true and this rewrote the whole list on every
        // navigation, which froze redirect-heavy sites. The tweak managers have
        // always compared content here; this one did not.
        guard current != script?.source else { return }

        ucc.removeAllUserScripts()
        if let script { ucc.addUserScript(script) }
        others.forEach { ucc.addUserScript($0) }
    }

    // MARK: - New controllers (from BrowserConfiguration.freshUserContentController)

    private func configureNewController(_ controller: WKUserContentController) {
        controller.addScriptMessageHandler(self, contentWorld: .page, name: AdvancedRulesEngine.messageHandlerName)
        guard isEnabled else { return }
        for list in compiledRuleLists { controller.add(list) }
        // Static scripts arrive by copy from the shared configuration.
    }

    // MARK: - Shared Configuration

    private func applyToSharedConfiguration() {
        guard let ucc = self.host?.sharedUserContentController else { return }
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists { ucc.add(list) }
        ensureStaticScripts(in: ucc)
    }

    private func removeFromSharedConfiguration() {
        guard let ucc = self.host?.sharedUserContentController else { return }
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

    /// A page that committed before blocking was ready can only be fixed by reloading it:
    /// rule lists are evaluated at navigation time and document-start scripts have already run.
    private func applyToExistingWebViews(reloadingPagesLoadedWithoutBlocking reloading: Bool = false) {
        for session in self.host?.blockablePages ?? [] {
            guard let wv = session.webView else { continue }
            // Exempt pages (allowlist, per-tab off, OAuth) loaded as intended; never reload them.
            guard shouldApplyBlocking(to: session) else { removeBlocking(from: wv); continue }
            applyBlocking(to: wv)
            guard reloading, let url = wv.url, url.scheme != "about" else { continue }
            wv.reload()
        }
    }

    private func removeFromExistingWebViews() {
        for session in self.host?.blockablePages ?? [] {
            guard let wv = session.webView else { continue }
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
        let all = ucc.userScripts
        let ours = all.nookOwned
        let remaining = ours.filter { script in !markers.contains { script.source.hasPrefix($0) } }
        guard remaining.count != ours.count else { return }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    private func session(for webView: WKWebView) -> (any BlockablePage)? {
        host?.blockablePage(for: webView)
    }
}

// MARK: - Subframe lookups (nook-cosmetic.js asks by its own frame URL)

extension ContentBlockerManager: WKScriptMessageHandlerWithReply {
    public func userContentController(
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
        if let session = session(for: webView) {
            if isExempt(session, host: topUrl?.host) { replyHandler(nil, nil); return }
        } else if isDomainAllowed(topUrl?.host) {
            replyHandler(nil, nil); return
        }

        let conf = advancedRulesEngine.configuration(for: pageUrl, topUrl: message.frameInfo.isMainFrame ? nil : topUrl)
        cbLog.info("frame lookup \(pageUrl.host ?? "-", privacy: .private(mask: .hash)) main=\(message.frameInfo.isMainFrame) rules=\(conf == nil ? 0 : 1, privacy: .public)")
        replyHandler(conf, nil)
    }
}
