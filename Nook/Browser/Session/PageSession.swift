//
//  PageSession.swift
//  Nook
//
//  One live page for one item. Holds the web view, committed URL, title, favicon, loading,
//  navigation and media state. The item itself (parent, order, home URL) lives in TabTree;
//  the session reports committed URLs and titles to its TabsController.
//

import AppKit
import Combine
import CoreAudio
import FaviconFinder
import SwiftUI
import WebKit

@MainActor
@Observable
final class PageSession: NSObject, Identifiable {
    // MARK: - Identity

    let itemID: UUID
    var id: UUID { itemID }
    /// A session in a private window: ephemeral profile, never saved, no extensions.
    let isPrivate: Bool

    @ObservationIgnored weak var controller: TabsController?
    @ObservationIgnored weak var browserManager: BrowserManager?

    /// The profile whose data store this page uses.
    var profile: Profile? {
        controller?.profile(for: self)
    }

    // MARK: - Page State

    /// Last committed URL (or the URL being loaded when nothing has committed yet).
    var url: URL
    var title: String
    var favicon: SwiftUI.Image

    enum LoadingState: Equatable {
        case idle
        case didStartProvisionalNavigation
        case didCommit
        case didFinish
        case didFail(Error)
        case didFailProvisionalNavigation(Error)

        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                (.didStartProvisionalNavigation, .didStartProvisionalNavigation),
                (.didCommit, .didCommit),
                (.didFinish, .didFinish):
                return true
            case (.didFail, .didFail),
                (.didFailProvisionalNavigation, .didFailProvisionalNavigation):
                return lhs.description == rhs.description
            default:
                return false
            }
        }

        var isLoading: Bool {
            switch self {
            case .idle, .didFinish, .didFail, .didFailProvisionalNavigation:
                return false
            case .didStartProvisionalNavigation, .didCommit:
                return true
            }
        }

        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .didStartProvisionalNavigation:
                return "Loading started"
            case .didCommit:
                return "Content loading"
            case .didFinish:
                return "Loading finished"
            case .didFail(let error):
                return "Loading failed: \(error.localizedDescription)"
            case .didFailProvisionalNavigation(let error):
                return "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    var loadingState: LoadingState = .idle
    var isLoading: Bool { loadingState.isLoading }
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    /// Requests on the current page that the ad blocker's lists match (see RequestStatsEngine).
    var blockedRequestCount: Int = 0

    // MARK: - Web Process Crash Tracking

    var webProcessCrashCount: Int = 0
    var lastWebProcessCrashDate: Date = .distantPast

    // MARK: - Media State

    var hasPlayingVideo: Bool = false
    var hasVideoContent: Bool = false
    var hasPiPActive: Bool = false
    var hasPlayingAudio: Bool = false
    var isAudioMuted: Bool = false
    var hasAudioContent: Bool = false {
        didSet {
            if oldValue != hasAudioContent {
                if hasAudioContent {
                    startNativeAudioMonitoring()
                } else {
                    stopNativeAudioMonitoring()
                }
            }
        }
    }

    // MARK: - Chrome

    var pageBackgroundColor: NSColor? = nil
    var topBarBackgroundColor: NSColor? = nil
    /// Option key state for Peek on link click.
    @ObservationIgnored var isOptionKeyDown: Bool = false
    @ObservationIgnored var onLinkHover: ((String?) -> Void)? = nil
    @ObservationIgnored var onCommandHover: ((String?) -> Void)? = nil
    @ObservationIgnored var pendingContextMenuPayload: WebContextMenuPayload?

    // MARK: - OAuth Flow State

    /// Whether this page hosts an OAuth/sign-in flow popup.
    var isOAuthFlow: Bool = false
    /// The item whose page started this OAuth flow.
    @ObservationIgnored var oauthParentItemID: UUID?
    /// The OAuth provider host (e.g., "accounts.google.com") for tracking protection exemption.
    @ObservationIgnored var oauthProviderHost: String?

    // MARK: - Internal State

    /// One-shot initial-navigation suppression for a WebKit-created popup.
    @ObservationIgnored var isPopupHost: Bool = false
    @ObservationIgnored var hasFavicon: Bool = false
    @ObservationIgnored var faviconFetchInFlight: Bool = false
    @ObservationIgnored var faviconFetchAttempts: Int = 0
    static let maxFaviconRetries = 3

    @ObservationIgnored var lastSampledDomain: String? = nil
    @ObservationIgnored var lastTopBarDomain: String? = nil
    @ObservationIgnored var pendingThemeColorUpdate: DispatchWorkItem? = nil

    @ObservationIgnored var audioDeviceListenerProc: AudioObjectPropertyListenerProc?
    @ObservationIgnored var audioListenerHelper: AudioListenerHelper?
    @ObservationIgnored var isMonitoringNativeAudio = false
    @ObservationIgnored var lastAudioDeviceCheckTime: Date = Date()
    @ObservationIgnored var audioMonitoringTimer: Timer?
    @ObservationIgnored var hasAddedCoreAudioListener = false
    @ObservationIgnored var profileAwaitCancellable: AnyCancellable?
    @ObservationIgnored var webStoreHandler: WebStoreScriptHandler?
    @ObservationIgnored var didNotifyOpenToExtensions: Bool = false

    @ObservationIgnored let themeColorObservedWebViews = NSHashTable<AnyObject>.weakObjects()
    @ObservationIgnored let navigationStateObservedWebViews = NSHashTable<AnyObject>.weakObjects()

    // MARK: - Web View Ownership

    var primaryWebView: WKWebView?
    /// A view created elsewhere (Peek, mini window, popup) that this session adopts on setup.
    @ObservationIgnored var adoptedWebView: WKWebView?
    /// The window that owns the primary web view; nil until a window displays the page.
    @ObservationIgnored var primaryWindowId: UUID?

    var isUnloaded: Bool { primaryWebView == nil }

    /// The existing web view. Never creates one.
    var webView: WKWebView? { primaryWebView }

    /// The web view, created on first access.
    var activeWebView: WKWebView {
        if primaryWebView == nil {
            setupWebView()
        }
        return primaryWebView!
    }

    /// The web view only once a window displays it, so callers never create orphan views.
    var assignedWebView: WKWebView? {
        primaryWindowId != nil ? primaryWebView : nil
    }

    // MARK: - Init

    init(
        itemID: UUID,
        url: URL,
        title: String,
        isPrivate: Bool,
        controller: TabsController?,
        browserManager: BrowserManager?,
        adoptedWebView: WKWebView? = nil
    ) {
        self.itemID = itemID
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
        self.controller = controller
        self.browserManager = browserManager
        self.adoptedWebView = adoptedWebView
        self.favicon = SwiftUI.Image(systemName: "globe")
        super.init()
        restoreFaviconFromCache()
    }

    deinit {
        profileAwaitCancellable?.cancel()
        themeColorObservedWebViews.removeAllObjects()
    }

    // MARK: - Web View Lifecycle

    func loadWebViewIfNeeded() {
        if primaryWebView == nil {
            setupWebView()
        }
        ensureFaviconLoaded()
    }

    /// Makes `webView` the primary view, owned by the window that displays it first.
    func assignWebView(_ webView: WKWebView, toWindow windowId: UUID) {
        primaryWebView = webView
        primaryWindowId = windowId
    }

    private func setupWebView() {
        let interval = BrowserPerformance.signposter.beginInterval("WebViewCreation")
        defer { BrowserPerformance.signposter.endInterval("WebViewCreation", interval) }
        let resolvedProfile = profile
        let configuration: WKWebViewConfiguration
        if let resolvedProfile {
            configuration = BrowserConfiguration.shared.webViewConfiguration(for: resolvedProfile)
        } else {
            // Edge case: no profile yet. Delay creating WKWebView until one resolves.
            if profileAwaitCancellable == nil {
                profileAwaitCancellable = browserManager?
                    .$currentProfile
                    .receive(on: RunLoop.main)
                    .sink { [weak self] value in
                        guard let self else { return }
                        if value != nil && self.primaryWebView == nil {
                            self.profileAwaitCancellable?.cancel()
                            self.profileAwaitCancellable = nil
                            self.setupWebView()
                            if self.primaryWebView != nil {
                                for (_, windowState) in self.browserManager?.windowRegistry?.windows ?? [:] {
                                    windowState.refreshCompositor()
                                }
                            }
                        }
                    }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.profileAwaitCancellable?.cancel()
                    self?.profileAwaitCancellable = nil
                }
            }
            return
        }

        // Private (ephemeral) profiles never get the extension controller: extensions do not
        // run in private pages.
        if configuration.webExtensionController == nil,
           resolvedProfile?.isEphemeral != true,
           let extensionController = ExtensionManager.shared.nativeController {
            configuration.webExtensionController = extensionController
        }

        let adopted = adoptedWebView
        if let adopted {
            primaryWebView = adopted
        } else {
            let created = FocusableWKWebView(frame: .zero, configuration: configuration)
            created.contextMenuBridge = WebContextMenuBridge(session: self, configuration: configuration)
            primaryWebView = created
        }

        guard let webView = primaryWebView else { return }
        (webView as? FocusableWKWebView)?.owningSession = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        setupThemeColorObserver(for: webView)
        setupNavigationStateObservers(for: webView)

        // Adopted Peek and mini-window views have their own controllers without Nook's
        // handlers, so they need the same setup as a fresh view.
        configure(webView)
        // An adopted page already finished loading, so didFinish will not inject the page
        // observers (SPA URL, media state, link hover) for this document.
        if adopted != nil, !webView.isLoading, webView.url != nil {
            injectPageObservers(into: webView)
            if let current = webView.url { url = current }
        }

        // Inform extensions before loading so content scripts and messaging can resolve this
        // page during early document phases.
        if !didNotifyOpenToExtensions {
            ExtensionManager.shared.notifyTabOpened(self)
            if controller?.activeWindowSession === self {
                ExtensionManager.shared.notifyTabActivated(new: self, previous: nil)
            }
            didNotifyOpenToExtensions = true
        }
        // Consume popup suppression only after setup succeeds. WebKit drives the original
        // navigation; any replacement view must load the saved URL.
        let shouldLoadInitialURL = !isPopupHost && adopted == nil
        isPopupHost = false
        if shouldLoadInitialURL {
            load(url)
        }
    }

    /// Handlers, user agent and preferences shared by primary, clone, adopted and popup views.
    /// The view's controller must belong to this view alone: handlers are keyed by name.
    func configure(_ webView: WKWebView) {
        let controller = webView.configuration.userContentController
        for name in messageHandlerNames {
            controller.removeScriptMessageHandler(forName: name)
            controller.add(self, name: name)
        }
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0.1 Safari/605.1.15"
        // Let the web content control its own background so extension styles (like Dark
        // Reader) can paint dark backgrounds. The themed background shows only while loading.
        webView.setValue(true, forKey: "drawsBackground")
        webView.isInspectable = true
        webView.allowsLinkPreview = true
        webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    }

    /// Installs a WebKit-created popup view as this session's primary view. WebKit drives the
    /// popup's first navigation.
    func installPopupWebView(_ webView: FocusableWKWebView) {
        webView.owningSession = self
        webView.contextMenuBridge = WebContextMenuBridge(session: self, configuration: webView.configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        primaryWebView = webView
        configure(webView)
        setupThemeColorObserver(for: webView)
        setupNavigationStateObservers(for: webView)
        if !didNotifyOpenToExtensions, !isPrivate {
            ExtensionManager.shared.notifyTabOpened(self)
            didNotifyOpenToExtensions = true
        }
    }

    /// Updates the extension controller on the existing web view.
    func applyConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        guard let existing = primaryWebView else { return }
        if let extensionController = configuration.webExtensionController {
            existing.configuration.webExtensionController = extensionController
        }
    }

    /// Releases every web view for this page (primary, window clones, adopted view) and resets
    /// live state. The item and its URL stay; selecting it again loads a fresh view.
    func unload() {
        let interval = BrowserPerformance.signposter.beginInterval("TabEviction")
        defer { BrowserPerformance.signposter.endInterval("TabEviction", interval) }
        let primary = primaryWebView
        let coordinator = browserManager?.webViewCoordinator
        let primaryIsPooled = primary.map { view in
            coordinator?.getAllWebViews(for: itemID).contains(where: { $0 === view }) == true
        } ?? false
        coordinator?.removeAllWebViews(for: self)
        if let primary, !primaryIsPooled { cleanupClone(primary) }
        primaryWebView = nil
        adoptedWebView = nil
        // WebKit only supplies the original popup navigation. A replacement view must load the
        // saved URL through the normal setup path.
        isPopupHost = false
        primaryWindowId = nil
        // The next view announces itself again (activation included).
        didNotifyOpenToExtensions = false
        stopNativeAudioMonitoring()
        profileAwaitCancellable?.cancel()
        profileAwaitCancellable = nil
        webStoreHandler = nil
        loadingState = .idle
        hasPiPActive = false
        hasPlayingVideo = false
        hasPlayingAudio = false
        hasAudioContent = false
        hasVideoContent = false
    }

    /// Final cleanup when the page ends (item closed, pinned page closed, window closed).
    func tearDown() {
        hasPiPActive = false
        unload()
        isAudioMuted = false
        browserManager?.cleanupZoomForTab(itemID)
        if webStoreHandler != nil {
            primaryWebView?.configuration.userContentController.removeScriptMessageHandler(
                forName: WebStoreScriptHandler.handlerName, contentWorld: WebStoreScriptHandler.contentWorld)
            webStoreHandler = nil
        }
    }

    /// Detaches a view from this session: handlers, observers, delegates, superview.
    func cleanupClone(_ webView: WKWebView) {
        webView.stopLoading()
        // Stop playback through WebKit; releasing the view tears down its document.
        webView.pauseAllMediaPlayback(completionHandler: nil)

        let controller = webView.configuration.userContentController
        for handlerName in messageHandlerNames + [ContentBlockerManager.requestStatsHandlerName] {
            controller.removeScriptMessageHandler(forName: handlerName)
        }
        controller.removeScriptMessageHandler(
            forName: WebStoreScriptHandler.handlerName, contentWorld: WebStoreScriptHandler.contentWorld)
        controller.removeScriptMessageHandler(
            forName: AdvancedRulesEngine.messageHandlerName, contentWorld: .page)

        // Break the retain cycle WKWebView -> contextMenuBridge -> userContentController -> WKWebView.
        if let focusable = webView as? FocusableWKWebView {
            focusable.contextMenuBridge?.detach()
            focusable.contextMenuBridge = nil
        }

        removeThemeColorObserver(from: webView)
        removeNavigationStateObservers(from: webView)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)
    }

    // MARK: - Navigation

    /// Loads a URL into a specific view. File URLs get read access to their directory so local
    /// subresources load. Uses the protocol cache policy: restoring an evicted page with
    /// returnCacheDataElseLoad served the stale cached document without revalidation.
    static func loadPage(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0
            webView.load(request)
        }
    }

    func load(_ newURL: URL) {
        url = newURL
        loadingState = .didStartProvisionalNavigation

        // Grant extension access before loading so content scripts inject at document_start.
        ExtensionManager.shared.grantExtensionAccessToURL(newURL)

        // Reset audio tracking for the new page; the mute preference is preserved.
        hasAudioContent = false
        hasPlayingAudio = false

        hasFavicon = false
        faviconFetchAttempts = 0

        PageSession.loadPage(newURL, in: activeWebView)

        // Keep other windows displaying this page on the same URL.
        browserManager?.navigateTabAcrossWindows(itemID, to: newURL)

        Task { @MainActor in
            await fetchAndSetFavicon(for: newURL)
        }
    }

    /// Navigates to typed input with search engine normalization.
    func navigate(to input: String) {
        let template = browserManager?.nookSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        guard let validURL = URL(string: normalizeURL(input, queryTemplate: template)) else { return }
        load(validURL)
    }

    func goBack() {
        guard canGoBack else { return }
        primaryWebView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        primaryWebView?.goForward()
    }

    func refresh() {
        // An unloaded page has nothing to reload: recreate it, which loads the saved URL.
        guard primaryWebView != nil else {
            loadWebViewIfNeeded()
            controller?.refreshWindows(showing: itemID)
            return
        }
        loadingState = .didStartProvisionalNavigation
        // The primary view can also belong to the coordinator. Reload each view once.
        var views = browserManager?.webViewCoordinator?.getAllWebViews(for: itemID) ?? []
        if let primary = primaryWebView { views.append(primary) }
        var reloaded = Set<ObjectIdentifier>()
        for view in views where reloaded.insert(ObjectIdentifier(view)).inserted {
            // reload() does nothing when no page ever committed (first load failed).
            if view.backForwardList.currentItem == nil || view.reload() == nil {
                PageSession.loadPage(url, in: view)
            }
        }
    }

    func stop() {
        primaryWebView?.stopLoading()
        loadingState = .idle
    }

    /// Selects this page in the active window (a click inside the web view).
    func activate() {
        guard let window = controller?.window(for: self) else { return }
        controller?.select(itemID, in: window)
    }

    func updateNavigationState() {
        guard let webView = primaryWebView else { return }
        let newCanGoBack = webView.canGoBack
        let newCanGoForward = webView.canGoForward
        if newCanGoBack != canGoBack || newCanGoForward != canGoForward {
            canGoBack = newCanGoBack
            canGoForward = newCanGoForward
        }
    }

    /// KVO on canGoBack/canGoForward gives real-time updates. A single delayed check catches
    /// WebKit's back-forward list settling asynchronously after a commit.
    func updateNavigationStateEnhanced(source: String = "unknown") {
        updateNavigationState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateNavigationState()
        }
    }

    func updateTitle(_ newTitle: String) {
        let resolved = newTitle.isEmpty ? url.host ?? "New Tab" : newTitle
        guard resolved != title else { return }
        title = resolved
        controller?.pageTitleChanged(itemID: itemID, title: resolved)
        ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.title])
    }

    // MARK: - Observation

    func setupNavigationStateObservers(for webView: WKWebView) {
        if !navigationStateObservedWebViews.contains(webView) {
            webView.addObserver(self, forKeyPath: "canGoBack", options: [.new, .initial], context: nil)
            webView.addObserver(self, forKeyPath: "canGoForward", options: [.new, .initial], context: nil)
            webView.addObserver(self, forKeyPath: "title", options: [.new], context: nil)
            // No URL observer: it fired during setup and overwrote restored URLs.
            // didCommit/didFinish own URL updates.
            navigationStateObservedWebViews.add(webView)
        }
    }

    func removeNavigationStateObservers(from webView: WKWebView) {
        if navigationStateObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "canGoBack")
            webView.removeObserver(self, forKeyPath: "canGoForward")
            webView.removeObserver(self, forKeyPath: "title")
            navigationStateObservedWebViews.remove(webView)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "themeColor", let webView = object as? WKWebView {
            // Debounce: themeColor KVO fires several times during a page load.
            pendingThemeColorUpdate?.cancel()
            let item = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateBackgroundColor(from: webView)
            }
            pendingThemeColorUpdate = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        } else if keyPath == "canGoBack" || keyPath == "canGoForward", object is WKWebView {
            updateNavigationState()
        } else if keyPath == "title", let webView = object as? WKWebView {
            // Real-time title updates from KVO (especially for SPAs)
            if let newTitle = webView.title, !newTitle.isEmpty, newTitle != title {
                updateTitle(newTitle)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Favicon

    /// Starts a favicon fetch when none has loaded yet, up to `maxFaviconRetries` failures.
    func ensureFaviconLoaded() {
        guard !hasFavicon, !faviconFetchInFlight else { return }
        guard faviconFetchAttempts < Self.maxFaviconRetries else { return }
        faviconFetchInFlight = true
        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
            faviconFetchInFlight = false
        }
    }

    /// Memory then disk cache, synchronously. Gives restored rows their favicon at once.
    func restoreFaviconFromCache() {
        guard url.scheme == "http" || url.scheme == "https", let host = url.host else { return }
        if let cached = FaviconCache.shared.image(for: host) ?? FaviconCache.shared.imageFromDiskSync(for: host) {
            favicon = SwiftUI.Image(nsImage: cached)
            hasFavicon = true
        }
    }

    func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        guard url.scheme == "http" || url.scheme == "https", url.host != nil else {
            favicon = defaultFavicon
            return
        }
        let cacheKey = url.host ?? url.absoluteString

        if let cached = await FaviconCache.shared.cachedImage(for: cacheKey) {
            favicon = SwiftUI.Image(nsImage: cached)
            hasFavicon = true
            return
        }

        faviconFetchAttempts += 1

        // FaviconFinder parses HTML <link> tags, then falls back to /favicon.ico.
        if let nsImage = await Self.fetchFaviconImage(for: url) {
            FaviconCache.shared.store(nsImage, for: cacheKey)
            favicon = SwiftUI.Image(nsImage: nsImage)
            hasFavicon = true
            return
        }

        // Last resort: the root /favicon.ico (for sites whose <link> targets return 403).
        if let rootFaviconURL = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL,
           let nsImage = await Self.downloadImage(from: rootFaviconURL) {
            FaviconCache.shared.store(nsImage, for: cacheKey)
            favicon = SwiftUI.Image(nsImage: nsImage)
            hasFavicon = true
            return
        }

        // hasFavicon stays false so ensureFaviconLoaded() can retry.
        favicon = defaultFavicon
    }

    private static func fetchFaviconImage(for url: URL) async -> NSImage? {
        do {
            let favicon = try await FaviconFinder(url: url)
                .fetchFaviconURLs()
                .download()
                .largest()
            return favicon.image?.image
        } catch {
            return nil
        }
    }

    private static func downloadImage(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Context Menu

    func deliverContextMenuPayload(_ payload: WebContextMenuPayload?) {
        pendingContextMenuPayload = payload
        if let webView = primaryWebView as? FocusableWKWebView {
            webView.contextMenuPayloadDidUpdate(payload)
        }
    }

    // MARK: - Equality

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PageSession else { return false }
        return itemID == other.itemID
    }

    override var hash: Int { itemID.hashValue }
}
