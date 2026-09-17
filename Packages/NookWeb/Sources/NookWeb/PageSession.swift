//
//  PageSession.swift
//  Nook
//
//  One live page for one item. Holds the web view, committed URL, title, favicon, loading,
//  navigation and media state. The item itself (parent, order, home URL) lives in TabTree;
//  the session reports committed URLs and titles to its TabsController.
//

import Combine
import CoreAudio
import FaviconFinder
import NookBlocker
import NookSettings
import OSLog
import SwiftUI
import WebKit

@MainActor
@Observable
public final class PageSession: NSObject, Identifiable {
    // MARK: - Identity

    public let itemID: UUID
    public var id: UUID { itemID }
    @ObservationIgnored static let log = Logger(subsystem: "com.baingurley.nook", category: "PageSession")
    /// A session in a private window: ephemeral profile, never saved, no extensions.
    public let isPrivate: Bool

    @ObservationIgnored public weak var controller: TabsController?

    /// The profile whose data store this page uses.
    public var profile: Profile? {
        controller?.profile(for: self)
    }

    // MARK: - Page State

    /// Last committed URL (or the URL being loaded when nothing has committed yet).
    public var url: URL
    public var title: String
    public var favicon: SwiftUI.Image

    public enum LoadingState: Equatable {
        case idle
        case didStartProvisionalNavigation
        case didCommit
        case didFinish
        case didFail(Error)
        case didFailProvisionalNavigation(Error)

        public static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
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

        public var isLoading: Bool {
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

    public var loadingState: LoadingState = .idle
    public var isLoading: Bool { loadingState.isLoading }
    public var canGoBack: Bool = false
    public var canGoForward: Bool = false

    // MARK: - Web Process Crash Tracking

    public var webProcessCrashCount: Int = 0
    public var lastWebProcessCrashDate: Date = .distantPast

    // MARK: - Media State

    public var hasPlayingVideo: Bool = false
    public var hasVideoContent: Bool = false
    public var hasPiPActive: Bool = false
    public var hasPlayingAudio: Bool = false
    public var isAudioMuted: Bool = false
    public var hasAudioContent: Bool = false {
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

    public var pageBackgroundColor: PlatformColor? = nil
    public var topBarBackgroundColor: PlatformColor? = nil
    /// Option key state for Peek on link click.
    @ObservationIgnored public var isOptionKeyDown: Bool = false
    @ObservationIgnored public var onLinkHover: ((String?) -> Void)? = nil
    @ObservationIgnored public var onCommandHover: ((String?) -> Void)? = nil
    @ObservationIgnored public var pendingContextMenuPayload: WebContextMenuPayload?

    // MARK: - OAuth Flow State

    /// Whether this page hosts an OAuth/sign-in flow popup.
    public var isOAuthFlow: Bool = false
    /// The item whose page started this OAuth flow.
    @ObservationIgnored public var oauthParentItemID: UUID?
    /// The OAuth provider host (e.g., "accounts.google.com") for tracking protection exemption.
    @ObservationIgnored public var oauthProviderHost: String?

    // MARK: - Internal State

    /// One-shot initial-navigation suppression for a WebKit-created popup.
    @ObservationIgnored public var isPopupHost: Bool = false
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
    @ObservationIgnored var webStoreHandler: AnyObject?
    @ObservationIgnored var didNotifyOpenToExtensions: Bool = false

    @ObservationIgnored let themeColorObservedWebViews = NSHashTable<AnyObject>.weakObjects()
    @ObservationIgnored let navigationStateObservedWebViews = NSHashTable<AnyObject>.weakObjects()

    // MARK: - Web View Ownership

    public var primaryWebView: WKWebView?
    /// A view created elsewhere (Peek, mini window, popup) that this session adopts on setup.
    @ObservationIgnored public var adoptedWebView: WKWebView?
    /// The window that owns the primary web view; nil until a window displays the page.
    @ObservationIgnored public var primaryWindowId: UUID?

    public var isUnloaded: Bool { primaryWebView == nil }

    /// The existing web view. Never creates one.
    public var webView: WKWebView? { primaryWebView }

    /// The web view, created on first access.
    public var activeWebView: WKWebView {
        if primaryWebView == nil {
            setupWebView()
        }
        return primaryWebView!
    }

    /// The web view only once a window displays it, so callers never create orphan views.
    public var assignedWebView: WKWebView? {
        primaryWindowId != nil ? primaryWebView : nil
    }

    // MARK: - Init

    public init(
        itemID: UUID,
        url: URL,
        title: String,
        isPrivate: Bool,
        controller: TabsController?,
        adoptedWebView: WKWebView? = nil
    ) {
        self.itemID = itemID
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
        self.controller = controller
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

    public func loadWebViewIfNeeded() {
        if primaryWebView == nil {
            setupWebView()
        }
        ensureFaviconLoaded()
    }

    /// Makes `webView` the primary view, owned by the window that displays it first.
    public func assignWebView(_ webView: WKWebView, toWindow windowId: UUID) {
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
                profileAwaitCancellable = controller?.sessionDelegate?
                    .currentProfilePublisher
                    .receive(on: RunLoop.main)
                    .sink { [weak self] value in
                        guard let self else { return }
                        if value != nil && self.primaryWebView == nil {
                            self.profileAwaitCancellable?.cancel()
                            self.profileAwaitCancellable = nil
                            self.setupWebView()
                            if self.primaryWebView != nil {
                                for (_, windowState) in self.controller?.windowRegistry.windows ?? [:] {
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
           let extensionController = controller?.tabEvents?.nativeController {
            configuration.webExtensionController = extensionController
        }

        let adopted = adoptedWebView
        if let adopted {
            primaryWebView = adopted
        } else {
            let created = controller?.webViews?.makeWebView(configuration: configuration)
            (created as? SessionWebView)?.contextMenuBridge = WebContextMenuBridge(session: self, configuration: configuration)
            primaryWebView = created
        }

        guard let webView = primaryWebView else { return }
        (webView as? SessionWebView)?.owningSession = self
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
            controller?.tabEvents?.tabOpened(self)
            if controller?.activeWindowSession === self {
                controller?.tabEvents?.tabActivated(new: self, previous: nil)
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
    public func configure(_ webView: WKWebView) {
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
    public func installPopupWebView(_ webView: WKWebView) {
        (webView as? SessionWebView)?.owningSession = self
        (webView as? SessionWebView)?.contextMenuBridge = WebContextMenuBridge(session: self, configuration: webView.configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        primaryWebView = webView
        configure(webView)
        setupThemeColorObserver(for: webView)
        setupNavigationStateObservers(for: webView)
        if !didNotifyOpenToExtensions, !isPrivate {
            controller?.tabEvents?.tabOpened(self)
            didNotifyOpenToExtensions = true
        }
    }

    /// Updates the extension controller on the existing web view.
    public func applyConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        guard let existing = primaryWebView else { return }
        if let extensionController = configuration.webExtensionController {
            existing.configuration.webExtensionController = extensionController
        }
    }

    /// Releases every web view for this page (primary, window clones, adopted view) and resets
    /// live state. The item and its URL stay; selecting it again loads a fresh view.
    public func unload() {
        let interval = BrowserPerformance.signposter.beginInterval("TabEviction")
        defer { BrowserPerformance.signposter.endInterval("TabEviction", interval) }
        let primary = primaryWebView
        let coordinator = controller?.webViews
        let primaryIsPooled = primary.map { view in
            coordinator?.allWebViews(for: itemID).contains(where: { $0 === view }) == true
        } ?? false
        coordinator?.releaseWebViews(for: self)
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
    public func tearDown() {
        hasPiPActive = false
        unload()
        isAudioMuted = false
        controller?.sessionDelegate?.cleanupZoom(for: itemID)
        if webStoreHandler != nil {
            if let controller = primaryWebView?.configuration.userContentController {
                self.controller?.sessionDelegate?.removeWebStoreHandler(from: controller)
            }
            webStoreHandler = nil
        }
    }

    /// Detaches a view from this session: handlers, observers, delegates, superview.
    public func cleanupClone(_ webView: WKWebView) {
        webView.stopLoading()
        // Stop playback through WebKit; releasing the view tears down its document.
        webView.pauseAllMediaPlayback(completionHandler: nil)

        let controller = webView.configuration.userContentController
        for handlerName in messageHandlerNames {
            controller.removeScriptMessageHandler(forName: handlerName)
        }
        self.controller?.sessionDelegate?.removeWebStoreHandler(from: controller)
        controller.removeScriptMessageHandler(
            forName: AdvancedRulesEngine.messageHandlerName, contentWorld: .page)

        // Break the retain cycle WKWebView -> contextMenuBridge -> userContentController -> WKWebView.
        if let focusable = webView as? SessionWebView {
            focusable.contextMenuBridge?.detach()
            focusable.contextMenuBridge = nil
        }

        removeThemeColorObserver(from: webView)
        removeNavigationStateObservers(from: webView)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.controller?.webViews?.removeFromContainers(webView)
    }

    // MARK: - Navigation

    /// Loads a URL into a specific view. File URLs get read access to their directory so local
    /// subresources load. Uses the protocol cache policy: restoring an evicted page with
    /// returnCacheDataElseLoad served the stale cached document without revalidation.
    public static func loadPage(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0
            webView.load(request)
        }
    }

    public func load(_ newURL: URL) {
        url = newURL
        loadingState = .didStartProvisionalNavigation

        // Grant extension access before loading so content scripts inject at document_start.
        controller?.tabEvents?.grantAccess(to: newURL)

        // Reset audio tracking for the new page; the mute preference is preserved.
        hasAudioContent = false
        hasPlayingAudio = false

        hasFavicon = false
        faviconFetchAttempts = 0

        PageSession.loadPage(newURL, in: activeWebView)

        // Keep other windows displaying this page on the same URL.
        controller?.sessionDelegate?.navigateAcrossWindows(itemID, to: newURL)

        Task { @MainActor in
            await fetchAndSetFavicon(for: newURL)
        }
    }

    /// Navigates to typed input with search engine normalization.
    public func navigate(to input: String) {
        let template = controller?.settings.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        guard let validURL = URL(string: normalizeURL(input, queryTemplate: template)) else { return }
        load(validURL)
    }

    public func goBack() {
        guard canGoBack else { return }
        primaryWebView?.goBack()
    }

    public func goForward() {
        guard canGoForward else { return }
        primaryWebView?.goForward()
    }

    public func refresh() {
        // An unloaded page has nothing to reload: recreate it, which loads the saved URL.
        guard primaryWebView != nil else {
            loadWebViewIfNeeded()
            controller?.refreshWindows(showing: itemID)
            return
        }
        loadingState = .didStartProvisionalNavigation
        // The primary view can also belong to the coordinator. Reload each view once.
        var views = controller?.webViews?.allWebViews(for: itemID) ?? []
        if let primary = primaryWebView { views.append(primary) }
        var reloaded = Set<ObjectIdentifier>()
        for view in views where reloaded.insert(ObjectIdentifier(view)).inserted {
            // reload() does nothing when no page ever committed (first load failed).
            if view.backForwardList.currentItem == nil || view.reload() == nil {
                PageSession.loadPage(url, in: view)
            }
        }
    }

    public func stop() {
        primaryWebView?.stopLoading()
        loadingState = .idle
    }

    /// Selects this page in the active window (a click inside the web view).
    public func activate() {
        guard let window = controller?.window(for: self) else { return }
        controller?.select(itemID, in: window)
    }

    public func updateNavigationState() {
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
    public func updateNavigationStateEnhanced(source: String = "unknown") {
        updateNavigationState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateNavigationState()
        }
    }

    public func updateTitle(_ newTitle: String) {
        let resolved = newTitle.isEmpty ? url.host ?? "New Tab" : newTitle
        guard resolved != title else { return }
        title = resolved
        controller?.pageTitleChanged(itemID: itemID, title: resolved)
        controller?.tabEvents?.tabPropertiesChanged(self, properties: [.title])
    }

    // MARK: - Observation

    public func setupNavigationStateObservers(for webView: WKWebView) {
        if !navigationStateObservedWebViews.contains(webView) {
            webView.addObserver(self, forKeyPath: "canGoBack", options: [.new, .initial], context: nil)
            webView.addObserver(self, forKeyPath: "canGoForward", options: [.new, .initial], context: nil)
            webView.addObserver(self, forKeyPath: "title", options: [.new], context: nil)
            // No URL observer: it fired during setup and overwrote restored URLs.
            // didCommit/didFinish own URL updates.
            navigationStateObservedWebViews.add(webView)
        }
    }

    public func removeNavigationStateObservers(from webView: WKWebView) {
        if navigationStateObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "canGoBack")
            webView.removeObserver(self, forKeyPath: "canGoForward")
            webView.removeObserver(self, forKeyPath: "title")
            navigationStateObservedWebViews.remove(webView)
        }
    }

    public override func observeValue(
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
    public func ensureFaviconLoaded() {
        guard !hasFavicon, !faviconFetchInFlight else { return }
        guard faviconFetchAttempts < Self.maxFaviconRetries else { return }
        faviconFetchInFlight = true
        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
            faviconFetchInFlight = false
        }
    }

    /// Memory then disk cache, synchronously. Gives restored rows their favicon at once.
    public func restoreFaviconFromCache() {
        guard url.scheme == "http" || url.scheme == "https", let host = url.host else { return }
        if let cached = FaviconCache.shared.image(for: host) ?? FaviconCache.shared.imageFromDiskSync(for: host) {
            favicon = SwiftUI.Image(platformImage: cached)
            hasFavicon = true
        }
    }

    public func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        guard url.scheme == "http" || url.scheme == "https", url.host != nil else {
            favicon = defaultFavicon
            return
        }
        let cacheKey = url.host ?? url.absoluteString

        if let cached = await FaviconCache.shared.cachedImage(for: cacheKey) {
            favicon = SwiftUI.Image(platformImage: cached)
            hasFavicon = true
            return
        }

        faviconFetchAttempts += 1

        // FaviconFinder parses HTML <link> tags, then falls back to /favicon.ico.
        if let nsImage = await Self.fetchFaviconImage(for: url) {
            FaviconCache.shared.store(nsImage, for: cacheKey)
            favicon = SwiftUI.Image(platformImage: nsImage)
            hasFavicon = true
            return
        }

        // Last resort: the root /favicon.ico (for sites whose <link> targets return 403).
        if let rootFaviconURL = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL,
           let nsImage = await Self.downloadImage(from: rootFaviconURL) {
            FaviconCache.shared.store(nsImage, for: cacheKey)
            favicon = SwiftUI.Image(platformImage: nsImage)
            hasFavicon = true
            return
        }

        // hasFavicon stays false so ensureFaviconLoaded() can retry.
        favicon = defaultFavicon
    }

    private static func fetchFaviconImage(for url: URL) async -> PlatformImage? {
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

    private static func downloadImage(from url: URL) async -> PlatformImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            return PlatformImage(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Context Menu

    public func deliverContextMenuPayload(_ payload: WebContextMenuPayload?) {
        pendingContextMenuPayload = payload
        if let webView = primaryWebView as? SessionWebView {
            webView.contextMenuPayloadDidUpdate(payload)
        }
    }

    // MARK: - Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PageSession else { return false }
        return itemID == other.itemID
    }

    public override var hash: Int { itemID.hashValue }
}
