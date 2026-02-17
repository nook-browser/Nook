//
//  Tab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AVFoundation
import AppKit
import Combine
import CoreAudio
import FaviconFinder
import Foundation
import SwiftUI
import WebKit

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject, WKDownloadDelegate {
    public let id: UUID
    var url: URL
    var name: String
    var favicon: SwiftUI.Image
    var spaceId: UUID?
    var index: Int
    var profileId: UUID?
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool = false

    // Track Option key state for Peek functionality
    var isOptionKeyDown: Bool = false

    // MARK: - OAuth Flow State
    /// Whether this tab is hosting an OAuth/sign-in flow popup
    var isOAuthFlow: Bool = false
    /// Reference to the parent tab that initiated this OAuth flow
    var oauthParentTabId: UUID?
    /// The OAuth provider host (e.g., "accounts.google.com") for tracking protection exemption
    var oauthProviderHost: String?
    /// The URL pattern that indicates OAuth completion (redirect back to original domain)
    var oauthCompletionURLPattern: String?

    // MARK: - Pin State
    var isPinned: Bool = false  // Global pinned (essentials)
    var isSpacePinned: Bool = false  // Space-level pinned
    var folderId: UUID?  // Folder membership for tabs within spacepinned area
    
    // MARK: - Ephemeral State
    /// Whether this tab belongs to an ephemeral/incognito session
    var isEphemeral: Bool {
        return resolveProfile()?.isEphemeral ?? false
    }

    // MARK: - Favicon Cache
    // Global favicon cache shared across profiles by design to increase hit rate
    // and reduce duplicate downloads. Favicons are cached persistently to survive app restarts.
    private static var faviconCache: [String: SwiftUI.Image] = [:]
    private static let faviconCacheQueue = DispatchQueue(
        label: "favicon.cache", attributes: .concurrent)
    private static let faviconCacheLock = NSLock()

    // Persistent cache storage
    private static let faviconCacheDirectory: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let faviconDir = cacheDir.appendingPathComponent("FaviconCache")
        try? FileManager.default.createDirectory(at: faviconDir, withIntermediateDirectories: true)
        return faviconDir
    }()

    // MARK: - Loading State
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
                // Compare error descriptions for equality
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

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    // Restored navigation state from undo/session restoration (applied when web view is created)
    var restoredCanGoBack: Bool?
    var restoredCanGoForward: Bool?

    // MARK: - Video State
    @Published var hasPlayingVideo: Bool = false
    @Published var hasVideoContent: Bool = false  // Track if tab has any video content
    @Published var hasPiPActive: Bool = false

    // MARK: - Audio State
    @Published var hasPlayingAudio: Bool = false
    @Published var isAudioMuted: Bool = false
    @Published var hasAudioContent: Bool = false {
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
    @Published var pageBackgroundColor: NSColor? = nil
    @Published var topBarBackgroundColor: NSColor? = nil
    
    // Track the last domain/subdomain we sampled color for
    private var lastSampledDomain: String? = nil

    // MARK: - Rename State
    @Published var isRenaming: Bool = false
    @Published var editingName: String = ""

    // MARK: - Native Audio Monitoring
    private var audioDeviceListenerProc: AudioObjectPropertyListenerProc?
    private var isMonitoringNativeAudio = false
    private var lastAudioDeviceCheckTime: Date = Date()
    private var audioMonitoringTimer: Timer?
    private var hasAddedCoreAudioListener = false
    private var profileAwaitCancellable: AnyCancellable?
    private var extensionAwaitCancellable: AnyCancellable?

    // Web Store integration
    private var webStoreHandler: WebStoreScriptHandler?

    // Debounce task for SPA navigation persistence
    private var spaPersistDebounceTask: Task<Void, Never>?

    // MARK: - Tab State
    var isUnloaded: Bool {
        return _webView == nil
    }

    private var _webView: WKWebView?
    private var _existingWebView: WKWebView?
    var pendingContextMenuPayload: WebContextMenuPayload?
    var didNotifyOpenToExtensions: Bool = false
    
    // MARK: - WebView Ownership Tracking (Memory Optimization)
    /// The window ID that currently "owns" the primary WebView for this tab
    /// If nil, no window is displaying this tab yet
    var primaryWindowId: UUID?
    
    /// Returns true if this tab has an assigned primary WebView (displayed in any window)
    var hasAssignedPrimaryWebView: Bool {
        return primaryWindowId != nil && _webView != nil
    }
    
    /// Returns the WebView IF it has been assigned to a window, nil otherwise
    /// This prevents creating "orphan" WebViews that are never displayed
    var assignedWebView: WKWebView? {
        // Only return WebView if it's been assigned to a window
        // This prevents the old behavior of creating a WebView on first access
        return primaryWindowId != nil ? _webView : nil
    }
    
    var webView: WKWebView? {
        if _webView == nil {
            let stackSymbols = Thread.callStackSymbols.prefix(8).joined(separator: "\n  ")
            print("🔍 [MEMDEBUG] Tab.webView LAZY ACCESS - Tab: \(id.uuidString.prefix(8)), URL: \(url.absoluteString)")
            print("🔍 [MEMDEBUG] Stack trace:\n  \(stackSymbols)")
            setupWebView()
        }
        return _webView
    }

    var activeWebView: WKWebView {
        if _webView == nil {
            setupWebView()
        }
        return _webView!
    }

    /// Returns the existing WebView without triggering lazy initialization
    var existingWebView: WKWebView? {
        return _webView
    }
    
    /// Assigns the WebView to a specific window as its "primary" display
    /// Call this when a window first displays this tab
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        print("🔍 [MEMDEBUG] Tab.assignWebViewToWindow() - Tab: \(id.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(webView).toOpaque())")
        
        // If we already have a WebView assigned to a different window, this is an error
        // (should have been caught by WebViewCoordinator)
        if let existingWindow = primaryWindowId, existingWindow != windowId {
            print("⚠️ [MEMDEBUG] WARNING: Reassigning WebView from window \(existingWindow.uuidString.prefix(8)) to \(windowId.uuidString.prefix(8))")
        }
        
        _webView = webView
        primaryWindowId = windowId
        
        print("🔍 [MEMDEBUG]   -> Primary window assigned: \(windowId.uuidString.prefix(8))")
    }

    weak var browserManager: BrowserManager?
    weak var nookSettings: NookSettingsService?

    // MARK: - Link Hover Callback
    var onLinkHover: ((String?) -> Void)? = nil
    var onCommandHover: ((String?) -> Void)? = nil

    private let themeColorObservedWebViews = NSHashTable<AnyObject>.weakObjects()
    private let navigationStateObservedWebViews = NSHashTable<AnyObject>.weakObjects()

    var isCurrentTab: Bool {
        // This property is used in contexts where we don't have window state
        // For now, we'll keep it using the global current tab for backward compatibility
        return browserManager?.tabManager.currentTab?.id == id
    }

    var isActiveInSpace: Bool {
        guard let spaceId = self.spaceId,
            let browserManager = self.browserManager,
            let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        else {
            return isCurrentTab  // Fallback to current tab for pinned tabs or if no space
        }
        return space.activeTabId == id
    }

    var isLoading: Bool {
        return loadingState.isLoading
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        browserManager: BrowserManager? = nil,
        existingWebView: WKWebView? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.index = index
        self.browserManager = browserManager
        self._existingWebView = existingWebView
        super.init()

        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
        }
    }

    public init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.index = index
        self.browserManager = nil
        super.init()

        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
        }
    }

    // MARK: - Controls
    func goBack() {
        guard canGoBack else { return }
        _webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        _webView?.goForward()
    }

    func refresh() {
        loadingState = .didStartProvisionalNavigation
        _webView?.reload()

        // Synchronize refresh across all windows that are displaying this tab
        browserManager?.reloadTabAcrossWindows(self.id)
    }

    func stop() {
        _webView?.stopLoading()
        loadingState = .idle
    }

    private func updateNavigationState() {
        guard let webView = _webView else { return }

        // Force UI update by notifying object will change
        objectWillChange.send()

        let newCanGoBack = webView.canGoBack
        let newCanGoForward = webView.canGoForward

        // Only update if values actually changed to prevent unnecessary redraws
        if newCanGoBack != canGoBack || newCanGoForward != canGoForward {
            canGoBack = newCanGoBack
            canGoForward = newCanGoForward

            // Notify TabManager to persist navigation state
            browserManager?.tabManager.updateTabNavigationState(self)
        }
    }

    /// Applies restored navigation state from undo/session restoration.
    /// Call this after setting up navigation observers to ensure proper initial state.
    private func applyRestoredNavigationState() {
        guard let back = restoredCanGoBack else { return }
        // Only apply restored state if webView hasn't already set different values
        // This preserves actual webView state when it differs from restored state
        if back != canGoBack {
            canGoBack = back
        }
        if let forward = restoredCanGoForward, forward != canGoForward {
            canGoForward = forward
        }
        // Clear restored state after applying
        restoredCanGoBack = nil
        restoredCanGoForward = nil
    }

    /// Enhanced navigation state update with aggressive timing for same-domain navigation
    func updateNavigationStateEnhanced(source: String = "unknown") {
        // Immediate update
        updateNavigationState()

        // Additional delayed updates to catch timing issues with same-domain navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNavigationState()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updateNavigationState()
        }
    }

    // MARK: - Chrome Web Store Integration

    /// Inject Web Store script after navigation completes
    private func injectWebStoreScriptIfNeeded(for url: URL, in webView: WKWebView) {
        guard let browserManager = browserManager else {
            return
        }

        guard BrowserConfiguration.isChromeWebStore(url) else { return }

        // Ensure message handler is registered (remove old handler first to avoid duplicates)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "nookWebStore")

        webStoreHandler = WebStoreScriptHandler(browserManager: browserManager)
        webView.configuration.userContentController.add(webStoreHandler!, name: "nookWebStore")

        // Get the script source from bundle
        guard let script = BrowserConfiguration.webStoreInjectorScript() else { return }

        // Inject with slight delay to ensure DOM is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript(script.source) { _, error in
                if let error = error {
                    print("[Tab] Web Store script injection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Boosts Integration
    
    // Track boost scripts to optimize removal (only remove boost scripts, not all scripts)
    // Use array instead of Set since WKUserScript doesn't conform to Hashable
    private var currentBoostScripts: [WKUserScript] = []
    
    private func setupBoostUserScript(for url: URL, in webView: WKWebView) {
        guard let browserManager = browserManager,
            let domain = url.host
        else {
            return
        }

        let userContentController = webView.configuration.userContentController
        let boostScriptIdentifier = "NOOK_BOOST_SCRIPT_IDENTIFIER"
        
        // Optimized: Only remove boost scripts, preserve other user scripts
        // This is much faster than removing all scripts and re-adding them
        if !currentBoostScripts.isEmpty {
            // Remove only the boost scripts we previously added
            // Compare by source content since WKUserScript doesn't conform to Equatable
            let allScripts = userContentController.userScripts
            userContentController.removeAllUserScripts()
            
            // Re-add only non-boost scripts (those not in our tracked list)
            let boostScriptSources = Set(currentBoostScripts.map { $0.source })
            for script in allScripts {
                if !boostScriptSources.contains(script.source) {
                    userContentController.addUserScript(script)
                }
            }
            
            currentBoostScripts.removeAll()
        } else {
            // First time setup - still need to check for any existing boost scripts
            // (in case webview was reused or scripts were added elsewhere)
            let existingBoostScripts = userContentController.userScripts.filter { script in
                script.source.contains(boostScriptIdentifier)
            }
            
            if !existingBoostScripts.isEmpty {
                // Remove existing boost scripts
                let remainingScripts = userContentController.userScripts.filter { script in
                    !script.source.contains(boostScriptIdentifier)
                }
                userContentController.removeAllUserScripts()
                remainingScripts.forEach { userContentController.addUserScript($0) }
            }
        }

        // Check if this domain has a boost configured
        guard let boostConfig = browserManager.boostsManager.getBoost(for: domain) else {
            // No boost for this domain - scripts already removed above
            return
        }

        print("🚀 [Tab] Setting up boost user scripts for domain: \(domain)")

        // Create and add boost user scripts (will inject at document start)
        // Returns array: [fontScript (optional), mainBoostScript]
        let boostScripts = browserManager.boostsManager.createBoostUserScripts(for: boostConfig, domain: domain)
        
        // Track these scripts for efficient removal later
        // Prevent duplicates by checking if script source already exists
        let existingSources = Set(userContentController.userScripts.map { $0.source })
        for script in boostScripts {
            // Only add if not already present (prevents duplicates during rapid navigation)
            if !existingSources.contains(script.source) {
                currentBoostScripts.append(script)
                userContentController.addUserScript(script)
            }
        }
        print("✅ [Tab] Added \(boostScripts.count) boost script(s) for: \(domain)")
    }
    
    private func injectBoostIfNeeded(for url: URL, in webView: WKWebView) {
        // This method is kept for backward compatibility but boost injection
        // now happens via user scripts at document start
        // Fallback: still inject if user script didn't work
        guard let browserManager = browserManager,
            let domain = url.host
        else {
            return
        }

        // Check if this domain has a boost configured
        guard let boostConfig = browserManager.boostsManager.getBoost(for: domain) else {
            return
        }

        print("🚀 [Tab] Fallback boost injection for domain: \(domain)")

        // Inject boost with a slight delay to ensure DOM is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            browserManager.boostsManager.injectBoost(boostConfig, into: webView) { success in
                if success {
                    print("✅ [Tab] Fallback boost injection successful for: \(domain)")
                } else {
                    print("❌ [Tab] Fallback boost injection failed for: \(domain)")
                }
            }
        }
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        print("🔍 [MEMDEBUG] Tab.setupWebView() START - Tab: \(id.uuidString.prefix(8)), Name: \(name), URL: \(url.absoluteString)")
        print("🔍 [MEMDEBUG]   _webView exists: \(_webView != nil), _existingWebView exists: \(_existingWebView != nil)")
        
        let resolvedProfile = resolveProfile()
        let configuration: WKWebViewConfiguration
        if let profile = resolvedProfile {
            configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(
                for: profile)
        } else {
            // Edge case: currentProfile not yet available. Delay creating WKWebView until it resolves.
            if profileAwaitCancellable == nil {
                print(
                    "[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile…"
                )
                profileAwaitCancellable = browserManager?
                    .$currentProfile
                    .receive(on: RunLoop.main)
                    .sink { [weak self] value in
                        guard let self = self else { return }
                        if value != nil && self._webView == nil {
                            self.profileAwaitCancellable?.cancel()
                            self.profileAwaitCancellable = nil
                            self.setupWebView()
                        }
                    }
            }
            return
        }


        // No need to block on extensionsLoaded — the shared config already has the
        // extension controller set (from setupExtensionController). Content scripts will
        // inject once individual extension contexts finish loading asynchronously.

        // Ensure the configuration has the extension controller so content scripts can inject
        if #available(macOS 15.5, *) {
            if configuration.webExtensionController == nil,
               let controller = ExtensionManager.shared.nativeController {
                configuration.webExtensionController = controller
            }
            let ctrl = configuration.webExtensionController
            let ctxs = ctrl?.extensionContexts.count ?? -1
            let samePool = configuration.processPool === BrowserConfiguration.shared.webViewConfiguration.processPool
            print("[EXT-CFG] '\(name)' controller=\(ctrl != nil), contexts=\(ctxs), sameProcessPool=\(samePool), existing=\(_existingWebView != nil)")
        }

        // Check if we have an existing WebView to inject
        if let existingWebView = _existingWebView {
            _webView = existingWebView
        } else {
            let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
            _webView = newWebView
            print("🔍 [MEMDEBUG] Tab CREATED NEW PRIMARY WebView - Tab: \(id.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(newWebView).toOpaque()), ConfigStore: \(configuration.websiteDataStore.identifier?.uuidString.prefix(8) ?? "default")")
            if let fv = _webView as? FocusableWKWebView {
                fv.owningTab = self
                fv.contextMenuBridge = WebContextMenuBridge(tab: self, configuration: configuration)
            }
        }

        _webView?.navigationDelegate = self
        _webView?.uiDelegate = self
        _webView?.allowsBackForwardNavigationGestures = true
        _webView?.allowsMagnification = true

        if let webView = _webView {
            setupThemeColorObserver(for: webView)
            setupNavigationStateObservers(for: webView)
            applyRestoredNavigationState()
        }

        // Only set up script handlers and user agent for new WebViews
        // Existing WebViews (from Peek) already have these configured
        if _existingWebView == nil {
            // Remove existing handlers first to prevent duplicates
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "linkHover")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "commandHover")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "commandClick")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "pipStateChange")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "mediaStateChange_\(id.uuidString)")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "backgroundColor_\(id.uuidString)")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "historyStateDidChange")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "NookIdentity")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "nookWebStore")
            _webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: "nookShortcutDetect")

            // Add handlers
            _webView?.configuration.userContentController.add(self, name: "linkHover")
            _webView?.configuration.userContentController.add(self, name: "commandHover")
            _webView?.configuration.userContentController.add(self, name: "commandClick")
            _webView?.configuration.userContentController.add(self, name: "pipStateChange")
            _webView?.configuration.userContentController.add(
                self, name: "mediaStateChange_\(id.uuidString)")
            _webView?.configuration.userContentController.add(
                self, name: "backgroundColor_\(id.uuidString)")
            _webView?.configuration.userContentController.add(self, name: "historyStateDidChange")
            _webView?.configuration.userContentController.add(self, name: "NookIdentity")
            _webView?.configuration.userContentController.add(self, name: "nookShortcutDetect")

            // Add Web Store integration handler for Chrome Web Store extension installs
            if let browserManager = browserManager {
                webStoreHandler = WebStoreScriptHandler(browserManager: browserManager)
                _webView?.configuration.userContentController.add(
                    webStoreHandler!, name: "nookWebStore")

                // Inject Web Store script at setup time if already on Chrome Web Store
                if BrowserConfiguration.isChromeWebStore(url),
                    let script = BrowserConfiguration.webStoreInjectorScript()
                {
                    _webView?.configuration.userContentController.addUserScript(script)
                }
            }

            _webView?.customUserAgent =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0.1 Safari/605.1.15"

            // Let the web content control its own background so extension styles
            // (like Dark Reader) can paint dark backgrounds. The app's themed
            // background is only visible while the page is loading.
            _webView?.setValue(true, forKey: "drawsBackground")
        }

        if let webView = _webView {
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }

            webView.allowsLinkPreview = true
            webView.configuration.preferences
                .isFraudulentWebsiteWarningEnabled = true
            webView.configuration.preferences
                .javaScriptCanOpenWindowsAutomatically = true
            // No ad-hoc page script injection here; rely on WKWebExtension
        }

        // For existing WebViews, ensure the delegates are updated to point to this tab
        if _existingWebView != nil {
            print("🔍 [MEMDEBUG] Tab setup COMPLETE (existing WebView) - Tab: \(id.uuidString.prefix(8))")
        } else {
            print("🔍 [MEMDEBUG] Tab setup COMPLETE (new WebView) - Tab: \(id.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(_webView!).toOpaque())")
        }

        // Inform extensions that this tab's view is now open/available BEFORE loading,
        // so content scripts and messaging can resolve this tab during early document phases
        if #available(macOS 15.5, *), didNotifyOpenToExtensions == false {
            ExtensionManager.shared.notifyTabOpened(self)
            // Also activate this tab if it's the current one, so the controller
            // can route chrome.runtime messages correctly
            if browserManager?.currentTabForActiveWindow()?.id == self.id {
                ExtensionManager.shared.notifyTabActivated(newTab: self, previous: nil)
            }
            didNotifyOpenToExtensions = true
        }
        // For popup-hosting tabs, don't trigger an initial navigation. WebKit will
        // drive the load into this returned webView from createWebViewWith:.
        // Also don't reload if we're using an existing WebView (from Peek)
        if !isPopupHost && _existingWebView == nil {
            loadURL(url)
        }
    }

    // Resolve the Profile for this tab via its space association, or fall back to currentProfile, then default profile
    func resolveProfile() -> Profile? {
        // First, check if we have a direct profileId assignment (including ephemeral tabs)
        if let pid = profileId {
            // Check ephemeral profiles first
            if let windowState = browserManager?.windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == self.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == pid {
                return ephemeralProfile
            }
            // Check regular profiles
            if let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid }) {
                return profile
            }
        }
        
        // Attempt to resolve via associated space
        if let sid = spaceId,
            let space = browserManager?.tabManager.spaces.first(where: { $0.id == sid })
        {
            if let pid = space.profileId,
                let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid })
            {
                return profile
            }
        }
        // Fallback to the current profile
        if let cp = browserManager?.currentProfile { return cp }
        // Final fallback to the default profile
        return browserManager?.profileManager.profiles.first
    }

    // Minimal hook to satisfy ExtensionManager: update extension controller on existing webView.
    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        guard let existing = _webView else { return }
        if #available(macOS 15.5, *), let controller = configuration.webExtensionController {
            existing.configuration.webExtensionController = controller
        }
    }

    // MARK: - Tab Actions
    func closeTab() {
        print("Closing tab: \(self.name)")

        // IMMEDIATELY RESET PiP STATE to prevent any further PiP operations
        hasPiPActive = false

        // MEMORY LEAK FIX: Use comprehensive cleanup instead of scattered cleanup
        performComprehensiveWebViewCleanup()

        // 11. RESET ALL STATE
        hasPlayingVideo = false
        hasVideoContent = false
        hasPlayingAudio = false
        hasAudioContent = false
        isAudioMuted = false
        hasPiPActive = false
        loadingState = .idle

        // 13. CLEANUP ZOOM DATA
        browserManager?.cleanupZoomForTab(self.id)

        // 14. FORCE COMPOSITOR UPDATE
        // Note: This is called during tab loading, so we use the global current tab
        // The compositor will handle window-specific visibility in its update methods
        browserManager?.compositorManager.updateTabVisibility(
            currentTabId: browserManager?.tabManager.currentTab?.id)

        // 13. STOP NATIVE AUDIO MONITORING
        stopNativeAudioMonitoring()

        // 14. REMOVE THEME COLOR OBSERVER
        if let webView = _webView {
            removeThemeColorObserver(from: webView)
            removeNavigationStateObservers(from: webView)
        }

        // 15. REMOVE FROM TAB MANAGER
        browserManager?.tabManager.removeTab(self.id)

        // Cancel any pending observations
        profileAwaitCancellable?.cancel()
        profileAwaitCancellable = nil
        extensionAwaitCancellable?.cancel()
        extensionAwaitCancellable = nil

        print("Tab killed: \(name)")
    }

    deinit {
        // MEMORY LEAK FIX: Ensure cleanup when tab is deallocated
        // Note: We can't access main actor-isolated properties in deinit,
        // but we can still clean up non-actor properties

        // Cancel any pending observations
        profileAwaitCancellable?.cancel()
        profileAwaitCancellable = nil
        extensionAwaitCancellable?.cancel()
        extensionAwaitCancellable = nil

        // Clear theme color observers
        themeColorObservedWebViews.removeAllObjects()

        // Note: stopNativeAudioMonitoring() is main actor-isolated and cannot be called from deinit
        // The cleanup will be handled by the closeTab() method which is called before deinit

        print("🧹 [Tab] deinit cleanup completed for: \(name)")
    }

    func loadURL(_ newURL: URL) {
        self.url = newURL
        loadingState = .didStartProvisionalNavigation

        // Grant extension access before loading so content scripts inject at document_start
        if #available(macOS 15.4, *) {
            ExtensionManager.shared.grantExtensionAccessToURL(newURL)
        }

        // Reset audio tracking for new page but preserve mute state
        hasAudioContent = false
        hasPlayingAudio = false
        // Note: isAudioMuted is preserved to maintain user's mute preference

        if newURL.isFileURL {
            // Grant read access to the containing directory for local resources
            let directoryURL = newURL.deletingLastPathComponent()
            print("🔧 [Tab] Loading file URL with directory access: \(directoryURL.path)")
            activeWebView.loadFileURL(newURL, allowingReadAccessTo: directoryURL)
        } else {
            // Regular URL loading with aggressive caching
            var request = URLRequest(url: newURL)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30.0
            print("🚀 [Tab] Loading URL with cache policy: \(request.cachePolicy.rawValue)")
            activeWebView.load(request)
        }

        // Synchronize navigation across all windows that are displaying this tab
        browserManager?.syncTabAcrossWindows(self.id)

        Task { @MainActor in
            await fetchAndSetFavicon(for: newURL)
        }
    }

    func loadURL(_ urlString: String) {
        guard let newURL = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL)
    }

    /// Navigate to a new URL with proper search engine normalization
    func navigateToURL(_ input: String) {
        let engine = nookSettings?.searchEngine ?? .google
        let normalizedUrl = normalizeURL(input, provider: engine)

        guard let validURL = URL(string: normalizedUrl) else {
            print("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        print("🌐 [Tab] Navigating current tab to: \(normalizedUrl)")
        loadURL(validURL)
    }

    func requestPictureInPicture() {
        // In multi-window setup, we need to work with the WebView that's actually visible
        // in the current window, not just the first WebView created
        if let browserManager = browserManager,
           let activeWindowId = browserManager.windowRegistry?.activeWindow?.id,
            let activeWebView = browserManager.getWebView(for: self.id, in: activeWindowId)
        {
            // Use the WebView that's actually visible in the current window
            PiPManager.shared.requestPiP(for: self, webView: activeWebView)
        } else {
            // Fallback to the original behavior for backward compatibility
            PiPManager.shared.requestPiP(for: self)
        }
    }

    // MARK: - Rename Methods
    func startRenaming() {
        isRenaming = true
        editingName = name
    }

    func saveRename() {
        if !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isRenaming = false
        editingName = ""
    }

    func cancelRename() {
        isRenaming = false
        editingName = ""
    }

    // MARK: - Simple Media Detection (mainly for manual checks)
    func checkMediaState() {
        // Get all web views for this tab across all windows
        let allWebViews: [WKWebView]
        if let coordinator = browserManager?.webViewCoordinator {
            allWebViews = coordinator.getAllWebViews(for: id)
        } else if let webView = _webView {
            // Fallback to original web view for backward compatibility
            allWebViews = [webView]
        } else {
            return
        }

        // Simple state check - optimized single-pass version
        let mediaCheckScript = """
            (() => {
                const audios = document.querySelectorAll('audio');
                const videos = document.querySelectorAll('video');

                // Single pass through audios
                const hasPlayingAudio = Array.from(audios).some(audio =>
                    !audio.paused && !audio.ended && audio.readyState >= 2
                );

                // Single pass through videos for all checks
                let hasPlayingVideoWithAudio = false;
                let hasPlayingVideo = false;

                Array.from(videos).forEach(video => {
                    const isPlaying = !video.paused && !video.ended && video.readyState >= 2;
                    if (isPlaying) {
                        hasPlayingVideo = true;
                        if (!video.muted && video.volume > 0) {
                            hasPlayingVideoWithAudio = true;
                        }
                    }
                });

                const hasAudioContent = hasPlayingAudio || hasPlayingVideoWithAudio;

                return {
                    hasAudioContent: hasAudioContent,
                    hasPlayingAudio: hasAudioContent,
                    hasVideoContent: videos.length > 0,
                    hasPlayingVideo: hasPlayingVideo
                };
            })();
            """

        // Check media state across all web views and aggregate results
        var aggregatedResults: [String: Bool] = [
            "hasAudioContent": false,
            "hasPlayingAudio": false,
            "hasVideoContent": false,
            "hasPlayingVideo": false,
        ]

        let group = DispatchGroup()

        for webView in allWebViews {
            group.enter()
            webView.evaluateJavaScript(mediaCheckScript) { result, error in
                defer { group.leave() }

                if let error = error {
                    print("[Media Check] Error: \(error.localizedDescription)")
                    return
                }

                if let state = result as? [String: Bool] {
                    // Aggregate results - if any web view has media, the tab has media
                    aggregatedResults["hasAudioContent"] =
                        (aggregatedResults["hasAudioContent"] ?? false)
                        || (state["hasAudioContent"] ?? false)
                    aggregatedResults["hasPlayingAudio"] =
                        (aggregatedResults["hasPlayingAudio"] ?? false)
                        || (state["hasPlayingAudio"] ?? false)
                    aggregatedResults["hasVideoContent"] =
                        (aggregatedResults["hasVideoContent"] ?? false)
                        || (state["hasVideoContent"] ?? false)
                    aggregatedResults["hasPlayingVideo"] =
                        (aggregatedResults["hasPlayingVideo"] ?? false)
                        || (state["hasPlayingVideo"] ?? false)
                }
            }
        }

        // Update tab state after all web views have been checked
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.hasAudioContent = aggregatedResults["hasAudioContent"] ?? false
            self.hasPlayingAudio = aggregatedResults["hasPlayingAudio"] ?? false
            self.hasVideoContent = aggregatedResults["hasVideoContent"] ?? false
            self.hasPlayingVideo = aggregatedResults["hasPlayingVideo"] ?? false
        }
    }

    private func injectMediaDetection(to webView: WKWebView) {
        let mediaDetectionScript = """
            (function() {
                const handlerName = 'mediaStateChange_\(id.uuidString)';

                // Track current URL for navigation detection
                window.__NookCurrentURL = window.location.href;

                function resetSoundTracking() {
                    window.webkit.messageHandlers[handlerName].postMessage({
                        hasAudioContent: false,
                        hasPlayingAudio: false,
                        hasVideoContent: false,
                        hasPlayingVideo: false
                    });
                    setTimeout(checkMediaState, 100);
                }

                const originalPushState = history.pushState;
                const originalReplaceState = history.replaceState;

                history.pushState = function(...args) {
                    originalPushState.apply(history, args);
                    setTimeout(() => {
                        if (window.location.href !== window.__NookCurrentURL) {
                            window.__NookCurrentURL = window.location.href;
                            resetSoundTracking();
                        }
                    }, 0);
                };

                history.replaceState = function(...args) {
                    originalReplaceState.apply(history, args);
                    setTimeout(() => {
                        if (window.location.href !== window.__NookCurrentURL) {
                            window.__NookCurrentURL = window.location.href;
                            resetSoundTracking();
                        }
                    }, 0);
                };

                // Listen for popstate events (back/forward)
                window.addEventListener('popstate', resetSoundTracking);

                function checkMediaState() {
                    const audios = document.querySelectorAll('audio');
                    const videos = document.querySelectorAll('video');

                    // Standard media detection
                    let hasPlayingAudio = false;
                    let hasPlayingVideoWithAudio = false;
                    let hasPlayingVideo = false;

                    // Check audio elements with enhanced detection
                    Array.from(audios).forEach(audio => {
                        const standardPlaying = !audio.paused && !audio.ended && audio.readyState >= 2;

                        // Enhanced detection for DRM content using WebKit properties
                        let drmAudioPlaying = false;
                        try {
                            // Check for decoded audio bytes (WebKit-specific)
                            if ('webkitAudioDecodedByteCount' in audio) {
                                const decodedBytes = audio.webkitAudioDecodedByteCount;
                                if (window.__NookLastDecodedBytes === undefined) {
                                    window.__NookLastDecodedBytes = {};
                                }
                                const lastBytes = window.__NookLastDecodedBytes[audio.src] || 0;
                                if (decodedBytes > lastBytes && audio.currentTime > 0) {
                                    drmAudioPlaying = true;
                                }
                                window.__NookLastDecodedBytes[audio.src] = decodedBytes;
                            }

                            // Check if current time is progressing (for DRM content)
                            if (!window.__NookLastCurrentTime) window.__NookLastCurrentTime = {};
                            const lastTime = window.__NookLastCurrentTime[audio.src] || 0;
                            if (audio.currentTime > lastTime + 0.1 && audio.readyState >= 2) {
                                drmAudioPlaying = true;
                            }
                            window.__NookLastCurrentTime[audio.src] = audio.currentTime;
                        } catch (e) {
                            // Silently continue if WebKit properties aren't available
                        }

                        if (standardPlaying || drmAudioPlaying) {
                            hasPlayingAudio = true;
                        }
                    });

                    // Check video elements with enhanced detection
                    Array.from(videos).forEach(video => {
                        const standardPlaying = !video.paused && !video.ended && video.readyState >= 2;

                        // Enhanced detection for DRM video content
                        let drmVideoPlaying = false;
                        try {
                            // Check for decoded bytes (WebKit-specific)
                            if ('webkitAudioDecodedByteCount' in video || 'webkitVideoDecodedByteCount' in video) {
                                const audioBytes = video.webkitAudioDecodedByteCount || 0;
                                const videoBytes = video.webkitVideoDecodedByteCount || 0;
                                if (!window.__NookLastVideoBytes) window.__NookLastVideoBytes = {};
                                const lastAudioBytes = window.__NookLastVideoBytes[video.src + '_audio'] || 0;
                                const lastVideoBytes = window.__NookLastVideoBytes[video.src + '_video'] || 0;

                                if ((audioBytes > lastAudioBytes || videoBytes > lastVideoBytes) && video.currentTime > 0) {
                                    drmVideoPlaying = true;
                                }
                                window.__NookLastVideoBytes[video.src + '_audio'] = audioBytes;
                                window.__NookLastVideoBytes[video.src + '_video'] = videoBytes;
                            }

                            // Check if current time is progressing
                            if (!window.__NookLastVideoCurrentTime) window.__NookLastVideoCurrentTime = {};
                            const lastTime = window.__NookLastVideoCurrentTime[video.src] || 0;
                            if (video.currentTime > lastTime + 0.1 && video.readyState >= 2) {
                                drmVideoPlaying = true;
                            }
                            window.__NookLastVideoCurrentTime[video.src] = video.currentTime;
                        } catch (e) {
                            // Silently continue if WebKit properties aren't available
                        }

                        const isPlaying = standardPlaying || drmVideoPlaying;
                        if (isPlaying) {
                            hasPlayingVideo = true;
                            if (!video.muted && video.volume > 0) {
                                hasPlayingVideoWithAudio = true;
                            }
                        }
                    });

                    // Additional heuristic detection for streaming sites
                    let heuristicAudioDetected = false;
                    try {
                        // Check for common streaming site indicators
                        const isSpotify = window.location.hostname.includes('spotify.com');
                        const isYouTube = window.location.hostname.includes('youtube.com') || window.location.hostname.includes('youtu.be');
                        const isSoundCloud = window.location.hostname.includes('soundcloud.com');
                        const isAppleMusic = window.location.hostname.includes('music.apple.com');

                        if (isSpotify) {
                            const playButton = document.querySelector('[data-testid="control-button-playpause"]');
                            if (playButton) {
                                const ariaLabel = playButton.getAttribute('aria-label') || '';
                                heuristicAudioDetected = ariaLabel.toLowerCase().includes('pause');
                            }
                        } else if (isYouTube) {
                            const player = document.querySelector('.html5-video-player');
                            const video = document.querySelector('video');
                            if (player && video) {
                                heuristicAudioDetected = player.classList.contains('playing-mode') ||
                                                       (!video.paused && video.currentTime > 0);
                            }
                        } else if (isSoundCloud) {
                            const playButton = document.querySelector('.playControl');
                            heuristicAudioDetected = playButton && playButton.classList.contains('playing');
                        } else if (isAppleMusic) {
                            const playButton = document.querySelector('button[aria-label*="pause"], button[aria-label*="Pause"]');
                            heuristicAudioDetected = !!playButton;
                        }
                    } catch (e) {}

                    const hasAudioContent = hasPlayingAudio || hasPlayingVideoWithAudio || heuristicAudioDetected;

                    window.webkit.messageHandlers[handlerName].postMessage({
                        hasAudioContent: hasAudioContent,
                        hasPlayingAudio: hasAudioContent,
                        hasVideoContent: videos.length > 0,
                        hasPlayingVideo: hasPlayingVideo
                    });
                }

                function addAudioListeners(element) {
                    ['play', 'pause', 'ended', 'loadedmetadata', 'canplay', 'volumechange', 'timeupdate'].forEach(event => {
                        element.addEventListener(event, function() {
                            setTimeout(checkMediaState, 50);
                        });
                    });

                    try {
                        if ('webkitneedkey' in element) {
                            element.addEventListener('webkitneedkey', function() {
                                setTimeout(checkMediaState, 100);
                            });
                        }

                        if ('encrypted' in element) {
                            element.addEventListener('encrypted', function() {
                                setTimeout(checkMediaState, 100);
                            });
                        }
                    } catch (e) {}
                }

                document.querySelectorAll('video, audio').forEach(addAudioListeners);

                const mediaObserver = new MutationObserver(function(mutations) {
                    let hasChanges = false;
                    mutations.forEach(function(mutation) {
                        mutation.addedNodes.forEach(function(node) {
                            if (node.nodeType === 1) {
                                if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') {
                                    addAudioListeners(node);
                                    hasChanges = true;
                                } else if (node.querySelector) {
                                    const mediaElements = node.querySelectorAll('video, audio');
                                    if (mediaElements.length > 0) {
                                        mediaElements.forEach(addAudioListeners);
                                        hasChanges = true;
                                    }
                                }
                            }
                        });

                        mutation.removedNodes.forEach(function(node) {
                            if (node.nodeType === 1) {
                                if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ||
                                    (node.querySelector && node.querySelectorAll('video, audio').length > 0)) {
                                    hasChanges = true;
                                }
                            }
                        });
                    });

                    if (hasChanges) {
                        setTimeout(checkMediaState, 100);
                    }
                });
                mediaObserver.observe(document.body, { childList: true, subtree: true });

                function setupStreamingSiteMonitoring() {
                    const hostname = window.location.hostname;

                    if (hostname.includes('spotify.com')) {
                        const observer = new MutationObserver(() => {
                            setTimeout(checkMediaState, 100);
                        });

                        const playerArea = document.querySelector('[data-testid="now-playing-widget"]') || document.body;
                        if (playerArea) {
                            observer.observe(playerArea, {
                                childList: true,
                                subtree: true,
                                attributes: true,
                                attributeFilter: ['aria-label', 'class', 'data-testid']
                            });
                        }
                    } else if (hostname.includes('youtube.com') || hostname.includes('youtu.be')) {
                        window.addEventListener('yt-navigate-finish', () => {
                            setTimeout(checkMediaState, 500);
                        });

                        const observer = new MutationObserver(() => {
                            setTimeout(checkMediaState, 100);
                        });

                        const playerElement = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
                        if (playerElement) {
                            observer.observe(playerElement, {
                                attributes: true,
                                attributeFilter: ['class']
                            });
                        }
                    } else if (hostname.includes('soundcloud.com')) {
                        const observer = new MutationObserver(() => {
                            setTimeout(checkMediaState, 100);
                        });

                        const playerElement = document.querySelector('.playControls') || document.body;
                        observer.observe(playerElement, {
                            childList: true,
                            subtree: true,
                            attributes: true,
                            attributeFilter: ['class']
                        });
                    } else if (hostname.includes('music.apple.com')) {
                        const observer = new MutationObserver(() => {
                            setTimeout(checkMediaState, 100);
                        });

                        const playerElement = document.querySelector('.web-chrome-playback-controls') || document.body;
                        observer.observe(playerElement, {
                            childList: true,
                            subtree: true,
                            attributes: true,
                            attributeFilter: ['aria-label', 'class']
                        });
                    }
                }

                setTimeout(setupStreamingSiteMonitoring, 1000);
                setTimeout(checkMediaState, 500);
                setInterval(() => {
                    checkMediaState();
                }, 5000);
            })();
            """

        webView.evaluateJavaScript(mediaDetectionScript) { result, error in
            if let error = error {
                print("[Media Detection] Error: \(error.localizedDescription)")
            } else {
                print("[Media Detection] Audio event tracking injected successfully")
            }
        }
    }

    func unloadWebView() {
        print("🔄 [Tab] Unloading webview for: \(name)")

        guard let webView = _webView else {
            print("🔄 [Tab] WebView already unloaded for: \(name)")
            return
        }

        // FORCE KILL ALL MEDIA AND PROCESSES
        webView.stopLoading()

        // Kill all media and PiP via JavaScript
        let killScript = """
            (() => {
                // FORCE KILL ALL PiP SESSIONS FIRST
                try {
                    // Exit any active PiP sessions
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                    }

                    // Force exit WebKit PiP for all videos
                    document.querySelectorAll('video').forEach(video => {
                        if (video.webkitSupportsPresentationMode && video.webkitPresentationMode === 'picture-in-picture') {
                            video.webkitSetPresentationMode('inline');
                        }
                    });

                    // Disable PiP on all videos permanently
                    document.querySelectorAll('video').forEach(video => {
                        video.disablePictureInPicture = true;
                        video.webkitSupportsPresentationMode = false;
                    });
                } catch (e) {
                    console.log('PiP destruction error:', e);
                }

                // Kill all media
                document.querySelectorAll('video, audio').forEach(el => {
                    el.pause();
                    el.currentTime = 0;
                    el.src = '';
                    el.load();
                    el.remove();
                });

                // Kill all WebAudio
                if (window.AudioContext || window.webkitAudioContext) {
                    if (window.__NookAudioContexts) {
                        window.__NookAudioContexts.forEach(ctx => ctx.close());
                        delete window.__NookAudioContexts;
                    }
                }

                // Kill all timers
                const maxId = setTimeout(() => {}, 0);
                for (let i = 0; i < maxId; i++) {
                    clearTimeout(i);
                    clearInterval(i);
                }

                // Force garbage collection if available
                if (window.gc) {
                    window.gc();
                }
            })();
            """
        webView.evaluateJavaScript(killScript) { _, error in
            if let error = error {
                print("[Tab] Error during media/PiP kill in unload: \(error.localizedDescription)")
            } else {
                print("[Tab] Media and PiP successfully killed during unload for: \(self.name)")
            }
        }

        // Clean up message handlers - use comprehensive cleanup
        let controller = webView.configuration.userContentController
        let allMessageHandlers = [
            "linkHover",
            "commandHover",
            "commandClick",
            "pipStateChange",
            "mediaStateChange_\(id.uuidString)",
            "backgroundColor_\(id.uuidString)",
            "historyStateDidChange",
            "NookIdentity",
        ]

        for handlerName in allMessageHandlers {
            controller.removeScriptMessageHandler(forName: handlerName)
        }

        // Remove from view hierarchy and clear delegates
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // FORCE TERMINATE THE WEB CONTENT PROCESS
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }

        // Remove theme color and navigation state observers before clearing webview reference
        if let webView = _webView {
            removeThemeColorObserver(from: webView)
            removeNavigationStateObservers(from: webView)
        }

        // Clear the webview reference (this will trigger reload when accessed)
        _webView = nil

        // Stop native audio monitoring since webview is unloaded
        stopNativeAudioMonitoring()

        // Reset loading state
        loadingState = .idle

        print("💀 [Tab] WebView FORCE UNLOADED for: \(name)")
    }

    func loadWebViewIfNeeded() {
        if _webView == nil {
            print("🔄 [Tab] Loading webview for: \(name)")
            setupWebView()
        }
    }

    func toggleMute() {
        setMuted(!isAudioMuted)
    }

    func setMuted(_ muted: Bool) {
        if let webView = _webView {
            // Set the mute state using MuteableWKWebView's muted property
            webView.isMuted = muted
        } else {
            print("🔇 [Tab] Mute state queued at \(muted); base webView not loaded yet")
        }

        browserManager?.setMuteState(
            muted, for: id, originatingWindowId: browserManager?.windowRegistry?.activeWindow?.id)

        // Update our internal state
        DispatchQueue.main.async { [weak self] in
            self?.isAudioMuted = muted
        }
    }

    // MARK: - Native Audio Monitoring
    private func startNativeAudioMonitoring() {
        guard !isMonitoringNativeAudio else { return }
        isMonitoringNativeAudio = true

        audioMonitoringTimer = Timer.scheduledTimer(
            timeInterval: 1.0, target: self,
            selector: #selector(handleNativeAudioMonitoringTimer(_:)), userInfo: nil, repeats: true)

        setupAudioSessionNotifications()
    }

    private func stopNativeAudioMonitoring() {
        guard isMonitoringNativeAudio else { return }
        isMonitoringNativeAudio = false

        audioMonitoringTimer?.invalidate()
        audioMonitoringTimer = nil

        removeCoreAudioPropertyListeners()
    }

    private func setupAudioSessionNotifications() {
        setupCoreAudioPropertyListeners()
    }

    private func setupCoreAudioPropertyListeners() {
        guard !hasAddedCoreAudioListener else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        audioDeviceListenerProc = { (objectID, numAddresses, addresses, clientData) in
            guard let clientData = clientData else { return noErr }
            let tab = Unmanaged<Tab>.fromOpaque(clientData).takeUnretainedValue()

            DispatchQueue.main.async {
                tab.checkNativeAudioActivity()
            }

            return noErr
        }

        if let listenerProc = audioDeviceListenerProc {
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerProc,
                Unmanaged.passUnretained(self).toOpaque()
            )

            if status == noErr {
                hasAddedCoreAudioListener = true
            }
        }
    }

    private func removeCoreAudioPropertyListeners() {
        guard hasAddedCoreAudioListener, let listenerProc = audioDeviceListenerProc else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if status == noErr {
            hasAddedCoreAudioListener = false
            audioDeviceListenerProc = nil
        }
    }

    @objc private func handleNativeAudioMonitoringTimer(_ timer: Timer) {
        checkNativeAudioActivity()
    }

    private func checkNativeAudioActivity() {
        let now = Date()
        guard now.timeIntervalSince(lastAudioDeviceCheckTime) > 0.5 else { return }
        lastAudioDeviceCheckTime = now

        let isDeviceActive = isDefaultAudioDeviceActive()

        if isDeviceActive && hasAudioContent {
            if !hasPlayingAudio {
                hasPlayingAudio = true
            }
        } else if hasPlayingAudio && !isDeviceActive {
            hasPlayingAudio = false
        }
    }

    private func isDefaultAudioDeviceActive() -> Bool {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            return false
        }

        var isRunning: UInt32 = 0
        dataSize = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isRunning
        )

        return runningStatus == noErr && isRunning != 0
    }

    // MARK: - Background Color Management
    func setupThemeColorObserver(for webView: WKWebView) {
        guard #available(macOS 12.0, *) else { return }
        if !themeColorObservedWebViews.contains(webView) {
            webView.addObserver(
                self, forKeyPath: "themeColor", options: [.new, .initial], context: nil)
            themeColorObservedWebViews.add(webView)
        }
    }

    func removeThemeColorObserver(from webView: WKWebView) {
        guard #available(macOS 12.0, *) else { return }
        if themeColorObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "themeColor")
            themeColorObservedWebViews.remove(webView)
        }
    }

    // MARK: - Navigation State Observation

    /// Set up KVO observers for navigation state properties
    func setupNavigationStateObservers(for webView: WKWebView) {
        if !navigationStateObservedWebViews.contains(webView) {
            webView.addObserver(
                self, forKeyPath: "canGoBack", options: [.new, .initial], context: nil)
            webView.addObserver(
                self, forKeyPath: "canGoForward", options: [.new, .initial], context: nil)
            webView.addObserver(
                self, forKeyPath: "title", options: [.new], context: nil)
            // NOTE: URL observer removed - it was firing during setup and overwriting
            // restored URLs. URL updates are handled by didCommit/didFinish delegates.
            navigationStateObservedWebViews.add(webView)
            print("🔍 [Tab] Set up navigation state observers for \(name)")
        }
    }

    /// Remove KVO observers for navigation state properties
    func removeNavigationStateObservers(from webView: WKWebView) {
        if navigationStateObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "canGoBack")
            webView.removeObserver(self, forKeyPath: "canGoForward")
            webView.removeObserver(self, forKeyPath: "title")
            // NOTE: URL observer removed - see setupNavigationStateObservers
            navigationStateObservedWebViews.remove(webView)
            print("🔍 [Tab] Removed navigation state observers for \(name)")
        }
    }

    /// MEMORY LEAK FIX: Comprehensive WebView cleanup to prevent memory leaks
    func cleanupCloneWebView(_ webView: WKWebView) {
        print("🧹 [Tab] Starting comprehensive WebView cleanup for: \(name)")

        // 1. Stop all loading and media
        webView.stopLoading()

        // 2. Kill all media and JavaScript execution
        let killScript = """
            (() => {
                try {
                    // Kill all media
                    document.querySelectorAll('video, audio').forEach(el => {
                        el.pause();
                        el.currentTime = 0;
                        el.src = '';
                        el.load();
                    });

                    // Kill all WebAudio contexts
                    if (window.AudioContext || window.webkitAudioContext) {
                        if (window.__NookAudioContexts) {
                            window.__NookAudioContexts.forEach(ctx => ctx.close());
                            delete window.__NookAudioContexts;
                        }
                    }

                    // Kill all timers
                    const maxId = setTimeout(() => {}, 0);
                    for (let i = 0; i < maxId; i++) {
                        clearTimeout(i);
                        clearInterval(i);
                    }
                } catch (e) {
                    console.log('Cleanup script error:', e);
                }
            })();
            """
        webView.evaluateJavaScript(killScript) { _, error in
            if let error = error {
                print("⚠️ [Tab] Cleanup script error: \(error.localizedDescription)")
            }
        }

        // 3. Remove ALL message handlers comprehensively
        let controller = webView.configuration.userContentController
        let allMessageHandlers = [
            "linkHover",
            "commandHover",
            "commandClick",
            "pipStateChange",
            "mediaStateChange_\(id.uuidString)",
            "backgroundColor_\(id.uuidString)",
            "historyStateDidChange",
            "NookIdentity",
        ]

        for handlerName in allMessageHandlers {
            controller.removeScriptMessageHandler(forName: handlerName)
        }

        // 4. Remove theme color and navigation state observers
        removeThemeColorObserver(from: webView)
        removeNavigationStateObservers(from: webView)

        // 5. Clear all delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // 6. Remove from view hierarchy
        webView.removeFromSuperview()

        // 7. Force remove from compositor
        browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)

        print("✅ [Tab] WebView cleanup completed for: \(name)")
    }

    /// MEMORY LEAK FIX: Comprehensive cleanup for the main tab WebView
    public func performComprehensiveWebViewCleanup() {
        guard let webView = _webView else { return }

        print("🧹 [Tab] Performing comprehensive cleanup for main WebView: \(name)")

        // Use the same comprehensive cleanup as clone WebViews
        cleanupCloneWebView(webView)

        // Additional cleanup for main WebView
        _webView = nil

        print("✅ [Tab] Main WebView cleanup completed for: \(name)")
    }

    public override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "themeColor", let webView = object as? WKWebView {
            updateBackgroundColor(from: webView)
        } else if keyPath == "canGoBack" || keyPath == "canGoForward",
            let webView = object as? WKWebView
        {
            // Real-time navigation state updates from KVO observers
            let observedKeyPath = keyPath ?? "<unknown>"
            print(
                "🔄 [Tab] KVO navigation state change for \(name): \(observedKeyPath) = \(webView.canGoBack), \(webView.canGoForward)"
            )
            updateNavigationState()
        } else if keyPath == "title", let webView = object as? WKWebView {
            // Real-time title updates from KVO (especially for SPAs)
            if let newTitle = webView.title, !newTitle.isEmpty, newTitle != self.name {
                print("📄 [Tab] KVO title change for \(name): '\(newTitle)'")
                updateTitle(newTitle)
            }
        } else if keyPath == "URL", let webView = object as? WKWebView {
            // URL observer disabled - was causing restored URLs to be overwritten
            // URL updates are handled by didCommit/didFinish navigation delegates
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func updateBackgroundColor(from webView: WKWebView) {
        // Check if we should sample based on domain change
        guard let currentURL = webView.url,
              let currentDomain = extractDomain(from: currentURL) else {
            // If no URL/domain, still try theme color but skip pixel sampling
            if #available(macOS 12.0, *), let themeColor = webView.themeColor {
                DispatchQueue.main.async { [weak self] in
                    self?.pageBackgroundColor = themeColor
                    webView.underPageBackgroundColor = themeColor
                }
            }
            return
        }
        
        // Only sample if domain changed or we haven't sampled yet
        let shouldSample = lastSampledDomain != currentDomain
        
        var newColor: NSColor? = nil

        if #available(macOS 12.0, *) {
            newColor = webView.themeColor
        }

        if let themeColor = newColor {
            DispatchQueue.main.async { [weak self] in
                self?.pageBackgroundColor = themeColor
                webView.underPageBackgroundColor = themeColor
                // Update sampled domain even for theme color
                if shouldSample {
                    self?.lastSampledDomain = currentDomain
                }
            }
        } else if shouldSample {
            // Only extract via pixel sampling if domain changed
            extractBackgroundColorWithJavaScript(from: webView)
        }
    }
    
    /// Extract domain and subdomain from URL (e.g., "subdomain.example.com" -> "subdomain.example.com")
    private func extractDomain(from url: URL) -> String? {
        guard let host = url.host else { return nil }
        return host
    }

    private func extractBackgroundColorWithJavaScript(from webView: WKWebView) {
        guard let sampleRect = colorSampleRect(for: webView) else {
            runLegacyBackgroundColorScript(on: webView)
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = sampleRect
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = 1

        webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, error in
            guard let self = self, let webView = webView else { return }

            if let color = image?.singlePixelColor {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.pageBackgroundColor = color
                    webView.underPageBackgroundColor = color
                    // Update sampled domain after successful extraction
                    if let currentURL = webView.url,
                       let currentDomain = self.extractDomain(from: currentURL) {
                        self.lastSampledDomain = currentDomain
                    }
                }
            } else {
                self.runLegacyBackgroundColorScript(on: webView)
            }
        }
    }

    private func colorSampleRect(for webView: WKWebView) -> CGRect? {
        let bounds = webView.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }

        var sampleX = bounds.midX
        sampleX = min(max(bounds.minX, sampleX), bounds.maxX - 1)

        let offset: CGFloat = 2.0
        let yCandidate: CGFloat
        if webView.isFlipped {
            yCandidate = bounds.minY + offset
        } else {
            yCandidate = bounds.maxY - offset - 1
        }
        let sampleY = min(max(yCandidate, bounds.minY), bounds.maxY - 1)

        return CGRect(x: sampleX, y: sampleY, width: 1, height: 1)
    }
    
    private func topRightPixelRect(for webView: WKWebView) -> CGRect? {
        let bounds = webView.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        
        // Sample the top-rightmost pixel
        let sampleX = bounds.maxX - 1
        let sampleY: CGFloat
        if webView.isFlipped {
            // In flipped coordinates, minY is at the top
            sampleY = bounds.minY
        } else {
            // In non-flipped coordinates, maxY is at the top
            sampleY = bounds.maxY - 1
        }
        
        return CGRect(x: sampleX, y: sampleY, width: 1, height: 1)
    }
    
    private func extractTopBarColor(from webView: WKWebView) {
        guard let sampleRect = topRightPixelRect(for: webView) else {
            return
        }
        
        let configuration = WKSnapshotConfiguration()
        configuration.rect = sampleRect
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = 1
        
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self = self else { return }
            
            if let color = image?.singlePixelColor {
                DispatchQueue.main.async {
                    self.topBarBackgroundColor = color
                }
            }
        }
    }

    private func runLegacyBackgroundColorScript(on webView: WKWebView) {
        let colorExtractionScript = """
            (function() {
                function rgbToHex(r, g, b) {
                    return '#' + [r, g, b].map(x => {
                        const hex = x.toString(16);
                        return hex.length === 1 ? '0' + hex : hex;
                    }).join('');
                }

                function parseColor(color) {
                    const div = document.createElement('div');
                    div.style.color = color;
                    document.body.appendChild(div);
                    const computedColor = window.getComputedStyle(div).color;
                    document.body.removeChild(div);

                    const match = computedColor.match(/rgb\\((\\d+),\\s*(\\d+),\\s*(\\d+)\\)/);
                    if (match) {
                        return rgbToHex(parseInt(match[1]), parseInt(match[2]), parseInt(match[3]));
                    }
                    return null;
                }

                function extractBackgroundColor() {
                    const body = document.body;
                    const html = document.documentElement;

                    // Try body background first
                    let bodyBg = window.getComputedStyle(body).backgroundColor;
                    if (bodyBg && bodyBg !== 'rgba(0, 0, 0, 0)' && bodyBg !== 'transparent') {
                        return parseColor(bodyBg);
                    }

                    // Try html background
                    let htmlBg = window.getComputedStyle(html).backgroundColor;
                    if (htmlBg && htmlBg !== 'rgba(0, 0, 0, 0)' && htmlBg !== 'transparent') {
                        return parseColor(htmlBg);
                    }

                    // Try sampling dominant colors from visible elements
                    const sampleElements = [
                        document.querySelector('header'),
                        document.querySelector('nav'),
                        document.querySelector('main'),
                        document.querySelector('.container'),
                        document.querySelector('#main'),
                        document.querySelector('[class*="background"]'),
                        document.querySelector('[class*="bg"]')
                    ].filter(el => el);

                    for (const el of sampleElements) {
                        const bg = window.getComputedStyle(el).backgroundColor;
                        if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                            return parseColor(bg);
                        }
                    }

                    // Fallback: detect if page looks dark or light and return appropriate gray
                    const isDarkMode = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                    const textColor = window.getComputedStyle(body).color;
                    const isLightText = textColor && (textColor.includes('255') || textColor.includes('white'));

                    if (isDarkMode || isLightText) {
                        return '#1a1a1a'; // Dark gray for dark themes
                    } else {
                        return '#ffffff'; // White for light themes
                    }
                }

                const bgColor = extractBackgroundColor();
                if (bgColor) {
                    window.webkit.messageHandlers['backgroundColor_\(id.uuidString)'].postMessage({
                        backgroundColor: bgColor
                    });
                }
            })();
            """

        webView.evaluateJavaScript(colorExtractionScript) { _, _ in }
    }

    // MARK: - JavaScript Injection
    private func injectLinkHoverJavaScript(to webView: WKWebView) {
        let linkHoverScript = """
            (function() {
                var currentHoveredLink = null;
                var isCommandPressed = false;
                var hoverCheckInterval = null;

                function sendLinkHover(href) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHover) {
                        window.webkit.messageHandlers.linkHover.postMessage(href);
                    }
                }

                function sendCommandHover(href) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commandHover) {
                        window.webkit.messageHandlers.commandHover.postMessage(href);
                    }
                }

                // Track Command key state
                document.addEventListener('keydown', function(e) {
                    if (e.metaKey) {
                        isCommandPressed = true;
                        if (currentHoveredLink) {
                            sendCommandHover(currentHoveredLink);
                        }
                    }
                });

                document.addEventListener('keyup', function(e) {
                    if (!e.metaKey) {
                        isCommandPressed = false;
                        sendCommandHover(null);
                    }
                });

                // Use a completely passive approach - add invisible event listeners directly to links
                function attachLinkListeners() {
                    var links = document.querySelectorAll('a[href]');
                    links.forEach(function(link) {
                        if (!link.dataset.NookListener) {
                            link.dataset.NookListener = 'true';

                            link.addEventListener('mouseenter', function() {
                                currentHoveredLink = link.href;
                                sendLinkHover(link.href);
                                if (isCommandPressed) {
                                    sendCommandHover(link.href);
                                }
                            }, { passive: true });

                            link.addEventListener('mouseleave', function() {
                                if (currentHoveredLink === link.href) {
                                    currentHoveredLink = null;
                                    sendLinkHover(null);
                                    sendCommandHover(null);
                                }
                            }, { passive: true });
                        }
                    });
                }

                // Initial attachment
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', attachLinkListeners);
                } else {
                    attachLinkListeners();
                }

                // Re-attach when DOM changes (for dynamic content)
                var observer = new MutationObserver(function(mutations) {
                    var needsReattach = false;
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                            needsReattach = true;
                        }
                    });
                    if (needsReattach) {
                        setTimeout(attachLinkListeners, 100);
                    }
                });
                observer.observe(document.body, { childList: true, subtree: true });

                // Handle command+click for new tabs
                document.addEventListener('click', function(e) {
                    if (e.metaKey) {
                        var target = e.target;
                        while (target && target !== document) {
                            if (target.tagName === 'A' && target.href) {
                                e.preventDefault();
                                e.stopPropagation();

                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commandClick) {
                                    window.webkit.messageHandlers.commandClick.postMessage(target.href);
                                }
                                return false;
                            }
                            target = target.parentElement;
                        }
                    }
                });
            })();
            """

        webView.evaluateJavaScript(linkHoverScript) { result, error in
            if let error = error {
                print("Error injecting link hover JavaScript: \(error.localizedDescription)")
            }
        }
    }

    private func injectHistoryStateObserver(into webView: WKWebView) {
        let historyScript = """
            (function() {
                if (window.__nookHistorySyncInstalled) { return; }
                window.__nookHistorySyncInstalled = true;

                function notify() {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.historyStateDidChange) {
                            window.webkit.messageHandlers.historyStateDidChange.postMessage(window.location.href);
                        }
                    } catch (err) {
                        console.error('historyStateDidChange failed', err);
                    }
                }

                var originalPushState = history.pushState;
                history.pushState = function() {
                    var result = originalPushState.apply(this, arguments);
                    setTimeout(notify, 0);
                    return result;
                };

                var originalReplaceState = history.replaceState;
                history.replaceState = function() {
                    var result = originalReplaceState.apply(this, arguments);
                    setTimeout(notify, 0);
                    return result;
                };

                window.addEventListener('popstate', notify);
                window.addEventListener('hashchange', notify);
                document.addEventListener('yt-navigate-finish', notify);

                notify();
            })();
            """

        webView.evaluateJavaScript(historyScript) { _, error in
            if let error = error {
                print(
                    "[Tab] Error injecting history observer JavaScript: \(error.localizedDescription)"
                )
            }
        }
    }

    private func injectPiPStateListener(to webView: WKWebView) {
        let pipStateScript = """
            (function() {
                function notifyPiPStateChange(isActive) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pipStateChange) {
                        window.webkit.messageHandlers.pipStateChange.postMessage({ active: isActive });
                    }
                }

                document.addEventListener('enterpictureinpicture', function() {
                    notifyPiPStateChange(true);
                });

                document.addEventListener('leavepictureinpicture', function() {
                    notifyPiPStateChange(false);
                });

                const videos = document.querySelectorAll('video');
                videos.forEach(video => {
                    if (video.webkitSupportsPresentationMode) {
                        video.addEventListener('webkitpresentationmodechanged', function() {
                            const isInPiP = video.webkitPresentationMode === 'picture-in-picture';
                            notifyPiPStateChange(isInPiP);
                        });
                    }
                });

                const observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        mutation.addedNodes.forEach(function(node) {
                            if (node.tagName === 'VIDEO' && node.webkitSupportsPresentationMode) {
                                node.addEventListener('webkitpresentationmodechanged', function() {
                                    const isInPiP = node.webkitPresentationMode === 'picture-in-picture';
                                    notifyPiPStateChange(isInPiP);
                                });
                            }
                        });
                    });
                });

                observer.observe(document.body, { childList: true, subtree: true });
            })();
            """

        webView.evaluateJavaScript(pipStateScript) { result, error in
            if let error = error {
                print("Error injecting PiP state listener: \(error.localizedDescription)")
            } else {
                print("[PiP] State listener injected successfully")
            }
        }
    }
    
    private func injectShortcutDetection(to webView: WKWebView) {
        // Inject the JS script from WebsiteShortcutDetector for runtime shortcut detection
        let script = WebsiteShortcutDetector.jsDetectionScript
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("⚠️ [Tab] Error injecting shortcut detection: \(error.localizedDescription)")
            } else {
                print("⌨️ [Tab] Shortcut detection script injected")
            }
        }
    }

    func activate() {
        browserManager?.tabManager.setActiveTab(self)
        // Media state is automatically tracked by injected script
    }

    func pause() {
        if !hasPiPActive && !PiPManager.shared.isPiPActive(for: self) {
            _webView?.evaluateJavaScript(
                "document.querySelectorAll('video, audio').forEach(el => el.pause());",
                completionHandler: nil
            )
        }

        hasPlayingVideo = false
        hasPlayingAudio = false
    }

    func updateTitle(_ title: String) {
        let newName = title.isEmpty ? url.host ?? "New Tab" : title
        // Only update if title actually changed to prevent redundant redraws
        guard newName != self.name else { return }
        self.name = newName
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.title])
        }
    }

    // MARK: - Favicon Logic
    private func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        // Skip favicon fetching for non-web schemes
        guard url.scheme == "http" || url.scheme == "https", url.host != nil
        else {
            await MainActor.run {
                self.favicon = defaultFavicon
            }
            return
        }

        // Check cache first
        let cacheKey = url.host ?? url.absoluteString
        if let cachedFavicon = Self.getCachedFavicon(for: cacheKey) {
            print("🎯 [Favicon] Cache hit for: \(cacheKey)")
            await MainActor.run {
                self.favicon = cachedFavicon
            }
            return
        }

        print("🌐 [Favicon] Cache miss for: \(cacheKey), fetching from network...")

        do {
            let favicon = try await FaviconFinder(url: url)
                .fetchFaviconURLs()
                .download()
                .largest()

            if let faviconImage = favicon.image {
                let nsImage = faviconImage.image
                let swiftUIImage = SwiftUI.Image(nsImage: nsImage)

                // Cache the favicon (both in memory and on disk)
                Self.cacheFavicon(swiftUIImage, for: cacheKey)
                Self.saveFaviconToDisk(nsImage, for: cacheKey)
                print("💾 [Favicon] Cached favicon for: \(cacheKey)")

                await MainActor.run {
                    self.favicon = swiftUIImage
                }
            } else {
                await MainActor.run {
                    self.favicon = defaultFavicon
                }
            }
        } catch {
            print(
                "Error fetching favicon for \(url): \(error.localizedDescription)"
            )
            await MainActor.run {
                self.favicon = defaultFavicon
            }
        }
    }

    // MARK: - Favicon Cache Management
    static func getCachedFavicon(for key: String) -> SwiftUI.Image? {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }

        // Check memory cache first
        if let cachedFavicon = faviconCache[key] {
            return cachedFavicon
        }

        // Check persistent cache
        if let persistentFavicon = loadFaviconFromDisk(for: key) {
            // Load into memory cache for faster access
            faviconCache[key] = persistentFavicon
            return persistentFavicon
        }

        return nil
    }

    static func cacheFavicon(_ favicon: SwiftUI.Image, for key: String) {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }

        faviconCache[key] = favicon

        // Limit cache size to prevent memory issues
        if faviconCache.count > 100 {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(faviconCache.keys.prefix(20))
            for keyToRemove in keysToRemove {
                faviconCache.removeValue(forKey: keyToRemove)
                removeFaviconFromDisk(for: keyToRemove)
            }
        }
    }

    // MARK: - Cache Management
    static func clearFaviconCache() {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        faviconCache.removeAll()
        clearAllFaviconCacheFromDisk()
    }

    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        return (faviconCache.count, Array(faviconCache.keys))
    }

    // MARK: - Persistent Storage Helpers
    private static func saveFaviconToDisk(_ nsImage: NSImage, for key: String) {
        let fileURL = faviconCacheDirectory.appendingPathComponent("\(key).png")

        // Convert NSImage to PNG data and save
        if let tiffData = nsImage.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffData),
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
            try? pngData.write(to: fileURL)
        }
    }

    private static func loadFaviconFromDisk(for key: String) -> SwiftUI.Image? {
        let fileURL = faviconCacheDirectory.appendingPathComponent("\(key).png")

        guard let imageData = try? Data(contentsOf: fileURL),
            let nsImage = NSImage(data: imageData)
        else {
            return nil
        }

        return SwiftUI.Image(nsImage: nsImage)
    }

    private static func removeFaviconFromDisk(for key: String) {
        let fileURL = faviconCacheDirectory.appendingPathComponent("\(key).png")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func clearAllFaviconCacheFromDisk() {
        try? FileManager.default.removeItem(at: faviconCacheDirectory)
        try? FileManager.default.createDirectory(
            at: faviconCacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - WKNavigationDelegate
extension Tab: WKNavigationDelegate {

    // MARK: - Loading Start
    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        print(
            "🌐 [Tab] didStartProvisionalNavigation for: \(webView.url?.absoluteString ?? "unknown")"
        )
        loadingState = .didStartProvisionalNavigation
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

        if let newURL = webView.url {
            // Only reset for actual URL changes, not just reloads
            if newURL.absoluteString != self.url.absoluteString {
                hasAudioContent = false
                hasPlayingAudio = false
                // Note: isAudioMuted is preserved to maintain user's mute preference
                print(
                    "🔄 [Tab] Swift reset audio tracking for navigation to: \(newURL.absoluteString)"
                )
                // Reset sampled domain to force resampling on new page
                if let newDomain = extractDomain(from: newURL),
                   newDomain != lastSampledDomain {
                    lastSampledDomain = nil
                }
                // Update URL but don't persist yet - wait for navigation to complete
                self.url = newURL
            } else {
                self.url = newURL
            }
        }
    }

    // MARK: - Content Committed
    public func webView(
        _ webView: WKWebView,
        didCommit navigation: WKNavigation!
    ) {
        print("🌐 [Tab] didCommit navigation for: \(webView.url?.absoluteString ?? "unknown")")
        loadingState = .didCommit
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

        if let newURL = webView.url {
            self.url = newURL
            browserManager?.syncTabAcrossWindows(self.id)
            // Update website shortcut detector with new URL
            browserManager?.keyboardShortcutManager?.websiteShortcutDetector.updateCurrentURL(newURL)
            if #available(macOS 15.5, *) {
                ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.URL])
            }
            // Don't persist here - wait for navigation to complete
        }
    }

    // MARK: - Loading Success
    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        print("✅ [Tab] didFinish navigation for: \(webView.url?.absoluteString ?? "unknown")")
        loadingState = .didFinish
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

        if let newURL = webView.url {
            self.url = newURL
            if #available(macOS 15.5, *) {
                ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.URL])

                // Extension diagnostics: check content scripts, background worker, and messaging
                ExtensionManager.shared.diagnoseExtensionState(for: webView, url: newURL)
            }
            browserManager?.syncTabAcrossWindows(self.id)

            // Load saved zoom level for the new domain
            browserManager?.loadZoomForTab(self.id)

            // CHROME WEB STORE INTEGRATION: Inject script after navigation
            injectWebStoreScriptIfNeeded(for: newURL, in: webView)

            // BOOSTS: Inject boost if domain has one configured
            injectBoostIfNeeded(for: newURL, in: webView)
        }

        // CRITICAL: Update navigation state after back/forward navigation
        updateNavigationStateEnhanced(source: "didFinish")

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String {
                print("📄 [Tab] Got title from JavaScript: '\(title)'")
                DispatchQueue.main.async {
                    self?.updateTitle(title)

                    // Add to profile-aware history after title is updated
                    if let currentURL = webView.url {
                        let profile = self?.resolveProfile()
                        let profileId = profile?.id ?? self?.browserManager?.currentProfile?.id
                        let isEphemeral = profile?.isEphemeral ?? false
                        self?.browserManager?.historyManager.addVisit(
                            url: currentURL,
                            title: title,
                            timestamp: Date(),
                            tabId: self?.id,
                            profileId: profileId,
                            isEphemeral: isEphemeral
                        )
                    }

                    // Persist tab changes after navigation completes (only once)
                    self?.browserManager?.tabManager.persistSnapshot()
                }
            } else if let jsError = error {
                print("⚠️ [Tab] Failed to get document.title: \(jsError.localizedDescription)")
                // Still persist even if title fetch failed, since URL was updated
                DispatchQueue.main.async {
                    self?.browserManager?.tabManager.persistSnapshot()
                }
            }
        }

        // Fetch favicon after page loads
        if let currentURL = webView.url {
            Task { @MainActor in
                await self.fetchAndSetFavicon(for: currentURL)
            }
        }

        injectLinkHoverJavaScript(to: webView)
        injectPiPStateListener(to: webView)
        injectMediaDetection(to: webView)
        injectHistoryStateObserver(into: webView)
        injectShortcutDetection(to: webView)
        updateNavigationStateEnhanced(source: "didCommit")

        // Trigger background color extraction after page fully loads
        // Wait a bit for boosts to apply and rendering to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak webView] in
            guard let self = self, let webView = webView else { return }
            // Only sample if page is still loaded (not navigating away)
            if self.loadingState == .didFinish {
                self.updateBackgroundColor(from: webView)
                // Extract top bar color once per page load (resamples on any navigation)
                self.extractTopBarColor(from: webView)
            }
        }

        // Apply mute state using MuteableWKWebView if the tab was previously muted
        if isAudioMuted {
            setMuted(true)
        }
        
        // Check for OAuth completion and auto-close if needed
        if isOAuthFlow, let currentURL = webView.url {
            checkOAuthCompletion(url: currentURL)
        }
    }

    // MARK: - Loading Failed (after content started loading)
    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        print("❌ [Tab] didFail navigation for: \(webView.url?.absoluteString ?? "unknown")")
        print("   Error: \(error.localizedDescription)")
        loadingState = .didFail(error)

        // Set error favicon on navigation failure
        Task { @MainActor in
            self.favicon = Image(systemName: "exclamationmark.triangle")
        }

        updateNavigationStateEnhanced(source: "didFail")
    }

    // MARK: - Loading Failed (before content started loading)
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print(
            "💥 [Tab] didFailProvisionalNavigation for: \(webView.url?.absoluteString ?? "unknown")")
        print("   Error: \(error.localizedDescription)")
        loadingState = .didFailProvisionalNavigation(error)

        // Set connection error favicon
        Task { @MainActor in
            self.favicon = Image(systemName: "wifi.exclamationmark")
        }

        updateNavigationStateEnhanced(source: "didFailProvisional")
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let handled = browserManager?.authenticationManager.handleAuthenticationChallenge(
            challenge,
            for: self,
            completionHandler: completionHandler
        ), handled {
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
            navigationAction.targetFrame?.isMainFrame == true
        {
            browserManager?.maybeShowOAuthAssist(for: url, in: self)

            // Grant extension access to this URL BEFORE navigation starts
            // so content scripts can inject at document_start
            if #available(macOS 15.4, *) {
                ExtensionManager.shared.grantExtensionAccessToURL(url)
            }

            // Setup boost user script before navigation starts
            setupBoostUserScript(for: url, in: webView)
        }

        // Check for Option+click to trigger Peek for any link
        if let url = navigationAction.request.url,
            navigationAction.navigationType == .linkActivated,
            isOptionKeyDown
        {

            // Trigger Peek instead of normal navigation
            decisionHandler(.cancel)
            RunLoop.current.perform { [weak self] in
                guard let self else { return }
                self.browserManager?.peekManager.presentExternalURL(url, from: self)
            }
            return
        }

        if #available(macOS 12.3, *), navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse,
            let disposition = response.allHeaderFields["Content-Disposition"] as? String,
            disposition.lowercased().contains("attachment")
        {
            decisionHandler(.download)
            return
        }

        if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    //MARK: - Downloads
    public func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationAction.request.url ?? URL(string: "https://example.com")!
        let suggestedFilename = navigationAction.request.url?.lastPathComponent ?? "download"

        print("🔽 [Tab] Download started from navigationAction: \(originalURL.absoluteString)")
        print("🔽 [Tab] Suggested filename: \(suggestedFilename)")
        print("🔽 [Tab] BrowserManager available: \(browserManager != nil)")

        _ = browserManager?.downloadManager.addDownload(
            download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationResponse.response.url ?? URL(string: "https://example.com")!
        let suggestedFilename = navigationResponse.response.url?.lastPathComponent ?? "download"

        print("🔽 [Tab] Download started from navigationResponse: \(originalURL.absoluteString)")
        print("🔽 [Tab] Suggested filename: \(suggestedFilename)")
        print("🔽 [Tab] BrowserManager available: \(browserManager != nil)")

        _ = browserManager?.downloadManager.addDownload(
            download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }

    // MARK: - WKDownloadDelegate
    public func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String, completionHandler: @escaping (URL?) -> Void
    ) {
        print("🔽 [Tab] WKDownloadDelegate decideDestinationUsing called")
        // Handle download destination directly
        guard
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first
        else {
            completionHandler(nil)
            return
        }

        let defaultName = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let cleanName = defaultName.replacingOccurrences(of: "/", with: "_")
        var dest = downloads.appendingPathComponent(cleanName)

        // Handle duplicate files
        let ext = dest.pathExtension
        let base = dest.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            dest = downloads.appendingPathComponent(newName)
            counter += 1
        }

        print("🔽 [Tab] Download destination set: \(dest.path)")
        completionHandler(dest)
    }

    public func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void
    ) {
        print("🔽 [Tab] WKDownloadDelegate decideDestinationUsing (macOS) called")
        // Handle download destination directly for macOS
        guard
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first
        else {
            completionHandler(
                FileManager.default.temporaryDirectory.appendingPathComponent("download"), false)
            return
        }

        let defaultName = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let cleanName = defaultName.replacingOccurrences(of: "/", with: "_")
        var dest = downloads.appendingPathComponent(cleanName)

        // Handle duplicate files
        let ext = dest.pathExtension
        let base = dest.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            dest = downloads.appendingPathComponent(newName)
            counter += 1
        }

        print("🔽 [Tab] Download destination set: \(dest.path)")
        // Return true to grant sandbox extension - this allows WebKit to write to the destination
        completionHandler(dest, true)
    }

    public func download(_ download: WKDownload, didFinishDownloadingTo location: URL) {
        print("🔽 [Tab] Download finished to: \(location.path)")
        // Download completed successfully
    }

    public func download(_ download: WKDownload, didFailWithError error: Error) {
        print("🔽 [Tab] Download failed: \(error.localizedDescription)")
        // Download failed
    }

}

// MARK: - WKScriptMessageHandler
extension Tab: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "linkHover":
            let href = message.body as? String
            DispatchQueue.main.async {
                self.onLinkHover?(href)
            }

        case "commandHover":
            let href = message.body as? String
            DispatchQueue.main.async {
                self.onCommandHover?(href)
            }

        case "commandClick":
            if let href = message.body as? String, let url = URL(string: href) {
                DispatchQueue.main.async {
                    self.handleCommandClick(url: url)
                }
            }

        case "pipStateChange":
            if let dict = message.body as? [String: Any], let active = dict["active"] as? Bool {
                DispatchQueue.main.async {
                    print("[PiP] State change detected from web: \(active)")
                    self.hasPiPActive = active
                }
            }

        case let name where name.hasPrefix("mediaStateChange_"):
            if let dict = message.body as? [String: Bool] {
                DispatchQueue.main.async {
                    self.hasPlayingVideo = dict["hasPlayingVideo"] ?? false
                    self.hasVideoContent = dict["hasVideoContent"] ?? false
                    self.hasAudioContent = dict["hasAudioContent"] ?? false
                    self.hasPlayingAudio = dict["hasPlayingAudio"] ?? false
                    // Don't override isAudioMuted - it's managed by toggleMute()
                }
            }

        case let name where name.hasPrefix("backgroundColor_"):
            if let dict = message.body as? [String: String],
                let colorHex = dict["backgroundColor"]
            {
                DispatchQueue.main.async {
                    self.pageBackgroundColor = NSColor(hex: colorHex)
                    if let webView = self._webView, let color = NSColor(hex: colorHex) {
                        webView.underPageBackgroundColor = color
                        // Update sampled domain after successful extraction
                        if let currentURL = webView.url,
                           let currentDomain = self.extractDomain(from: currentURL) {
                            self.lastSampledDomain = currentDomain
                        }
                    }
                }
            }
            

        case "historyStateDidChange":
            if let href = message.body as? String, let url = URL(string: href) {
                DispatchQueue.main.async {
                    if self.url.absoluteString != url.absoluteString {
                        self.url = url
                        self.browserManager?.syncTabAcrossWindows(self.id)

                        // Debounce persistence for SPA navigation to avoid excessive writes
                        self.spaPersistDebounceTask?.cancel()
                        self.spaPersistDebounceTask = Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                            guard !Task.isCancelled else { return }
                            self?.browserManager?.tabManager.persistSnapshot()
                        }
                    }
                }
            }

        case "NookIdentity":
            handleOAuthRequest(message: message)
            
        case "nookShortcutDetect":
            handleShortcutDetection(message: message)

        default:
            break
        }
    }
    
    private func handleShortcutDetection(message: WKScriptMessage) {
        // Handle detected shortcuts from JS injection
        guard let shortcutsString = message.body as? String,
              let currentURL = _webView?.url?.absoluteString else { return }
        
        // Parse the comma-separated shortcuts
        let shortcuts = Set(shortcutsString.split(separator: ",").map { String($0) })
        
        // Update the detector with detected shortcuts for this URL
        browserManager?.keyboardShortcutManager?.websiteShortcutDetector.updateJSDetectedShortcuts(
            for: currentURL,
            shortcuts: shortcuts
        )
    }

    private func handleCommandClick(url: URL) {
        // Create a new tab with the URL and focus it
        browserManager?.tabManager.createNewTab(
            url: url.absoluteString, in: browserManager?.tabManager.currentSpace)
    }

    private func handleOAuthRequest(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
            let urlString = dict["url"] as? String,
            let url = URL(string: urlString)
        else {
            print("❌ [Tab] Invalid OAuth request: missing or invalid URL")
            return
        }
        let interactive = dict["interactive"] as? Bool ?? true
        let prefersEphemeral = dict["prefersEphemeral"] as? Bool ?? false
        let providedScheme = (dict["callbackScheme"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let rawRequestId = (dict["requestId"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let requestId = (rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString)

        print(
            "🔐 [Tab] OAuth request received: id=\(requestId) url=\(url.absoluteString) interactive=\(interactive) ephemeral=\(prefersEphemeral) scheme=\(providedScheme ?? "nil")"
        )

        guard let manager = browserManager else {
            finishIdentityFlow(requestId: requestId, with: .failure(.unableToStart))
            return
        }

        let identityRequest = AuthenticationManager.IdentityRequest(
            requestId: requestId,
            url: url,
            interactive: interactive,
            prefersEphemeralSession: prefersEphemeral,
            explicitCallbackScheme: providedScheme?.isEmpty == true ? nil : providedScheme
        )

        manager.authenticationManager.beginIdentityFlow(identityRequest, from: self)
    }

    func finishIdentityFlow(
        requestId: String,
        with result: AuthenticationManager.IdentityFlowResult
    ) {
        guard let webView else {
            print("⚠️ [Tab] Unable to deliver identity result; webView missing")
            return
        }

        var payload: [String: Any] = ["requestId": requestId]

        switch result {
        case .success(let url):
            payload["status"] = "success"
            payload["url"] = url.absoluteString
        case .cancelled:
            payload["status"] = "cancelled"
            payload["code"] = "cancelled"
            payload["message"] = "Authentication cancelled by user."
        case .failure(let failure):
            payload["status"] = "failure"
            payload["code"] = failure.code
            payload["message"] = failure.message
        }

        if let status = payload["status"] as? String {
            let urlDescription = payload["url"] as? String ?? "nil"
            print(
                "🔐 [Tab] Identity flow completed: id=\(requestId) status=\(status) url=\(urlDescription)"
            )
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            print("❌ [Tab] Failed to serialise identity payload for requestId=\(requestId)")
            return
        }

        let script =
            "window.__nookCompleteIdentityFlow && window.__nookCompleteIdentityFlow(\(jsonString));"
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                print("❌ [Tab] Failed to deliver identity result: \(error.localizedDescription)")
            }
        }
    }

    private func isLikelyOAuthOrExternalWindow(url: URL, windowFeatures: WKWindowFeatures) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""

        // Check for OAuth-related URLs
        let oauthHosts = [
            "accounts.google.com", "login.microsoftonline.com", "login.live.com",
            "appleid.apple.com", "github.com", "gitlab.com", "bitbucket.org",
            "auth0.com", "okta.com", "onelogin.com", "pingidentity.com",
            "slack.com", "zoom.us", "login.cloudflareaccess.com",
            "oauth", "auth", "login", "signin",
        ]

        // Check if host contains OAuth-related terms
        if oauthHosts.contains(where: { host.contains($0) }) {
            return true
        }

        // Check for OAuth paths and query parameters
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize")
            || path.contains("/signin") || path.contains("/login") || path.contains("/callback")
        {
            return true
        }

        if query.contains("client_id=") || query.contains("redirect_uri=")
            || query.contains("response_type=") || query.contains("scope=")
        {
            return true
        }

        // Check window features that suggest external/popup behavior
        if let width = windowFeatures.width, let height = windowFeatures.height,
            width.doubleValue > 0 && height.doubleValue > 0
        {
            // If specific dimensions are set, it's likely a popup
            return true
        }

        // Note: WKWindowFeatures visibility properties are NSNumber? and don't directly map to enum values
        // We'll rely on URL patterns and dimensions for popup detection

        return false
    }

    // MARK: - Peek Detection

    private func shouldRedirectToPeek(url: URL) -> Bool {
        // Always redirect to Peek if Option key is down (for any URL)
        if isOptionKeyDown {
            return true
        }

        // Check if this is an external domain URL
        guard let currentHost = self.url.host,
            let newHost = url.host
        else { return false }

        // If hosts are different, it's an external URL
        if currentHost != newHost {
            return true
        }

        return false
    }

}

// MARK: - WKUIDelegate
extension Tab: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let bm = browserManager else { return nil }

        // OAuth and signin flows should open in a miniwindow for better UX
        // The miniwindow handles OAuth completion detection and notifies the parent tab
        // Skip this for extension-originated navigations — extensions manage their own auth flows
        let sourceScheme = navigationAction.sourceFrame.request.url?.scheme?.lowercased() ?? ""
        let isFromExtension = sourceScheme == "webkit-extension" || sourceScheme == "safari-web-extension"
        if !isFromExtension,
            let url = navigationAction.request.url,
            isLikelyOAuthOrExternalWindow(url: url, windowFeatures: windowFeatures)
        {
            print("🔐 [Tab] OAuth/signin popup detected, opening in miniwindow: \(url.absoluteString)")
            
            // Auto-allow the OAuth provider domain for tracking protection
            if let providerHost = url.host?.lowercased() {
                bm.oauthAllowDomain(providerHost)
            }
            
            // Store reference to parent tab for completion callback
            let parentTabId = self.id
            
            // Open OAuth flow in miniwindow
            bm.externalMiniWindowManager.present(url: url) { [weak bm] success, finalURL in
                print("🔐 [Tab] Miniwindow OAuth flow completed: success=\(success), url=\(finalURL?.absoluteString ?? "nil")")
                
                guard let bm = bm else { return }
                
                // Find the parent tab and reload it
                if let parentTab = bm.tabManager.allTabs().first(where: { $0.id == parentTabId }) {
                    DispatchQueue.main.async {
                        if success {
                            bm.tabManager.setActiveTab(parentTab)
                            parentTab.activeWebView.reload()
                            print("🔐 [Tab] Parent tab reloaded after successful OAuth")
                        }
                    }
                }
            }
            
            return nil  // Don't create a WebView, miniwindow handles it
        }

        // For regular popups, check if this should be redirected to Peek
        // Skip Peek for extension-originated navigations
        if !isFromExtension,
            let url = navigationAction.request.url,
            shouldRedirectToPeek(url: url)
        {

            // Trigger Peek after returning control to WebKit to avoid runloop-mode issues
            RunLoop.current.perform { [weak self, weak bm] in
                guard let self, let bm else { return }
                bm.peekManager.presentExternalURL(url, from: self)
            }

            return nil  // Don't create a WebView, we're using Peek
        }

        // For regular popups, create a new webView with the EXACT configuration that WebKit provided
        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)

        // Create a new tab to manage this webView
        let space = bm.tabManager.currentSpace
        let newTab = bm.tabManager.createPopupTab(in: space)

        // Set up the new webView with the same delegates and settings as the current tab
        newWebView.navigationDelegate = newTab
        newWebView.uiDelegate = newTab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true

        // Set the owning tab reference
        newWebView.owningTab = newTab

        // Store the webView in the new tab
        newTab._webView = newWebView

        // Set up message handlers
        // Remove any existing handlers first to avoid duplicates
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "linkHover")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "commandHover")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "commandClick")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "pipStateChange")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "mediaStateChange_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "backgroundColor_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "historyStateDidChange")
        newWebView.configuration.userContentController.removeScriptMessageHandler(
            forName: "NookIdentity")

        // Now add the handlers
        newWebView.configuration.userContentController.add(newTab, name: "linkHover")
        newWebView.configuration.userContentController.add(newTab, name: "commandHover")
        newWebView.configuration.userContentController.add(newTab, name: "commandClick")
        newWebView.configuration.userContentController.add(newTab, name: "pipStateChange")
        newWebView.configuration.userContentController.add(
            newTab, name: "mediaStateChange_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.add(
            newTab, name: "backgroundColor_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.add(newTab, name: "historyStateDidChange")
        newWebView.configuration.userContentController.add(newTab, name: "NookIdentity")

        // Set custom user agent
        newWebView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0.1 Safari/605.1.15"

        // Configure preferences
        newWebView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        newWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Load the URL if provided
        if let url = navigationAction.request.url, url.scheme != nil,
            url.absoluteString != "about:blank"
        {
            newTab.loadURL(url)
        }

        return newWebView
    }

    // MARK: - OAuth Tab Helpers
    
    /// Sets up message handlers for an OAuth popup tab
    private func setupOAuthTabMessageHandlers(for tab: Tab, webView: WKWebView) {
        let userContentController = webView.configuration.userContentController
        
        // Remove any existing handlers first
        let handlerNames = ["linkHover", "commandHover", "commandClick", "pipStateChange",
                           "mediaStateChange_\(tab.id.uuidString)",
                           "backgroundColor_\(tab.id.uuidString)",
                           "historyStateDidChange", "NookIdentity"]
        
        for handlerName in handlerNames {
            userContentController.removeScriptMessageHandler(forName: handlerName)
        }
        
        // Add handlers for the OAuth tab
        userContentController.add(tab, name: "linkHover")
        userContentController.add(tab, name: "commandHover")
        userContentController.add(tab, name: "commandClick")
        userContentController.add(tab, name: "pipStateChange")
        userContentController.add(tab, name: "mediaStateChange_\(tab.id.uuidString)")
        userContentController.add(tab, name: "backgroundColor_\(tab.id.uuidString)")
        userContentController.add(tab, name: "historyStateDidChange")
        userContentController.add(tab, name: "NookIdentity")
    }
    
    /// Checks if a URL indicates OAuth completion and handles the flow
    private func checkOAuthCompletion(url: URL) {
        guard isOAuthFlow, let parentTabId = oauthParentTabId,
              let bm = browserManager else { return }
        
        let urlString = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        
        // Check for OAuth success indicators
        let successIndicators = ["code=", "access_token=", "id_token=", "oauth_token=",
                                "oauth_verifier=", "session_state=", "samlresponse="]
        
        // Check for OAuth error indicators
        let errorIndicators = ["error=", "access_denied", "invalid_request", "denied"]
        
        let isSuccess = successIndicators.contains { urlString.contains($0) }
        let isError = errorIndicators.contains { urlString.contains($0) }
        
        // Check if this is a redirect back to the original domain (not the OAuth provider)
        if let providerHost = oauthProviderHost, !host.contains(providerHost),
           (isSuccess || isError || !isLikelyOAuthURL(url)) {
            
            print("🔐 [Tab] OAuth flow completed: success=\(isSuccess), closing OAuth tab")
            
            // Find and reload the parent tab
            if let parentTab = bm.tabManager.allTabs().first(where: { $0.id == parentTabId }) {
                DispatchQueue.main.async { [weak bm] in
                    // Switch to parent tab
                    bm?.tabManager.setActiveTab(parentTab)
                    // Reload parent tab to pick up authenticated state
                    parentTab.activeWebView.reload()
                }
            }
            
            // Close this OAuth tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak bm, weak self] in
                guard let self = self, let bm = bm else { return }
                print("🔐 [Tab] Auto-closing OAuth tab: \(self.name)")
                bm.tabManager.removeTab(self.id)
            }
        }
    }
    
    /// Determines if a URL is likely an OAuth-related URL
    private func isLikelyOAuthURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        
        let oauthHosts = [
            "accounts.google.com", "login.microsoftonline.com", "login.live.com",
            "appleid.apple.com", "github.com", "gitlab.com", "bitbucket.org",
            "auth0.com", "okta.com", "onelogin.com", "pingidentity.com",
            "slack.com", "zoom.us", "login.cloudflareaccess.com",
            "oauth", "auth", "login", "signin"
        ]
        
        if oauthHosts.contains(where: { host.contains($0) }) { return true }
        
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize")
            || path.contains("/signin") || path.contains("/login") || path.contains("/callback") {
            return true
        }
        
        if query.contains("client_id=") || query.contains("redirect_uri=")
            || query.contains("response_type=") || query.contains("scope=") {
            return true
        }
        
        return false
    }

    private func handleMiniWindowAuthCompletion(success: Bool, finalURL: URL?) {
        print(
            "🪟 [Tab] Popup OAuth flow completed: success=\(success), finalURL=\(finalURL?.absoluteString ?? "nil")"
        )

        if success {
            DispatchQueue.main.async { [weak self] in
                self?.activeWebView.reload()
            }
        } else {
            print("🪟 [Tab] Popup OAuth authentication failed")
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Confirm"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let result = alert.runModal()
        completionHandler(result == .alertFirstButtonReturn)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "JavaScript Prompt"
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            completionHandler(textField.stringValue)
        } else {
            completionHandler(nil)
        }
    }

    // MARK: - File Upload Support
    public func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {

        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.canChooseFiles = true
        openPanel.resolvesAliases = true
        openPanel.title = "Choose File"
        openPanel.prompt = "Choose"

        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async {
            if let window = webView.window {
                // Present as sheet if we have a window
                openPanel.beginSheetModal(for: window) { response in
                    print("📁 [Tab] Open panel sheet completed with response: \(response)")
                    if response == .OK {
                        print(
                            "📁 [Tab] User selected files: \(openPanel.urls.map { $0.lastPathComponent })"
                        )
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [Tab] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            } else {
                // Fall back to modal presentation
                openPanel.begin { response in
                    print("📁 [Tab] Open panel modal completed with response: \(response)")
                    if response == .OK {
                        print(
                            "📁 [Tab] User selected files: \(openPanel.urls.map { $0.lastPathComponent })"
                        )
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [Tab] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            }
        }
    }

    // MARK: - Full-Screen Video Support
    @available(macOS 10.15, *)
    public func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [Tab] Entering full-screen for video - delegate method called!")

        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [Tab] No window found for full-screen")
            completionHandler(
                false,
                NSError(
                    domain: "Tab", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }

        print("🎬 [Tab] Found window: \(window), entering full-screen...")

        // Enter full-screen mode
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
            print("🎬 [Tab] Full-screen toggle called")
        }

        // Call completion handler immediately - WebKit will handle the actual full-screen transition
        completionHandler(true, nil)
    }

    @available(macOS 10.15, *)
    public func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [Tab] Exiting full-screen for video - delegate method called!")

        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [Tab] No window found for exiting full-screen")
            completionHandler(
                false,
                NSError(
                    domain: "Tab", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No window available for exiting full-screen"
                    ]))
            return
        }

        print("🎬 [Tab] Found window: \(window), exiting full-screen...")

        // Exit full-screen mode
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
            print("🎬 [Tab] Full-screen exit toggle called")
        }

        // Call completion handler immediately - WebKit will handle the actual full-screen transition
        completionHandler(true, nil)
    }

    // MARK: - WebAuthn / Passkey Support

    /// Handle requests for media capture authorization (including WebAuthn/passkey requests)
    @available(macOS 13.0, *)
    public func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        print(
            "🔐 [Tab] Media capture authorization requested for type: \(type.rawValue) from origin: \(origin)"
        )

        // For passkeys/WebAuthn, we want to grant permission
        // The system will handle the actual Touch ID/Face ID prompt
        decisionHandler(.grant)
    }
}

// MARK: - Find in Page
extension Tab {
    typealias FindResult = Result<(matchCount: Int, currentIndex: Int), Error>
    typealias FindCompletion = @Sendable (FindResult) -> Void

    func findInPage(_ text: String, completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let browserManager = browserManager,
            let activeWindowId = browserManager.windowRegistry?.activeWindow?.id
        {
            targetWebView = browserManager.getWebView(for: self.id, in: activeWindowId)
        } else {
            targetWebView = _webView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "Tab", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
            return
        }

        // First clear any existing highlights
        clearFindInPage()

        // If text is empty, return no matches
        guard !text.isEmpty else {
            completion(.success((matchCount: 0, currentIndex: 0)))
            return
        }

        // Use JavaScript to search and highlight text
        let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let script = """
            (function() {
                // Check if document is ready
                if (!document.body) {
                    return { matchCount: 0, currentIndex: 0, error: 'Document not ready' };
                }

                // Remove existing highlights
                var existingHighlights = document.querySelectorAll('.nook-find-highlight');
                existingHighlights.forEach(function(el) {
                    var parent = el.parentNode;
                    parent.replaceChild(document.createTextNode(el.textContent), el);
                    parent.normalize();
                });

                if ('\(escapedText)' === '') {
                    return { matchCount: 0, currentIndex: 0 };
                }

                var searchText = '\(escapedText)';
                var matchCount = 0;
                var currentIndex = 0;

                // Create a tree walker to find text nodes
                var walker = document.createTreeWalker(
                    document.body,
                    NodeFilter.SHOW_TEXT,
                    {
                        acceptNode: function(node) {
                            // Skip script and style elements
                            var parent = node.parentElement;
                            if (parent && (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE')) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            return NodeFilter.FILTER_ACCEPT;
                        }
                    }
                );

                var textNodes = [];
                var node;
                while (node = walker.nextNode()) {
                    textNodes.push(node);
                }

                // Search and highlight
                textNodes.forEach(function(textNode) {
                    var text = textNode.textContent;
                    if (text && text.length > 0) {
                        var regex = new RegExp('(' + searchText.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&') + ')', 'gi');
                        var matches = text.match(regex);

                        if (matches && matches.length > 0) {
                            matchCount += matches.length;
                            var highlightedHTML = text.replace(regex, '<span class="nook-find-highlight" style="background-color: yellow; color: black;">$1</span>');

                            var wrapper = document.createElement('div');
                            wrapper.innerHTML = highlightedHTML;

                            var parent = textNode.parentNode;
                            while (wrapper.firstChild) {
                                parent.insertBefore(wrapper.firstChild, textNode);
                            }
                            parent.removeChild(textNode);
                        }
                    }
                });

                // Scroll to first match
                var firstHighlight = document.querySelector('.nook-find-highlight');
                if (firstHighlight) {
                    firstHighlight.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    firstHighlight.style.backgroundColor = 'orange';
                }

                return { matchCount: matchCount, currentIndex: matchCount > 0 ? 1 : 0 };
            })();
            """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("Find JavaScript error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            print("Find JavaScript result: \(String(describing: result))")

            if let dict = result as? [String: Any],
                let matchCount = dict["matchCount"] as? Int,
                let currentIndex = dict["currentIndex"] as? Int
            {
                print("Find found \(matchCount) matches, current index: \(currentIndex)")
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                print("Find result parsing failed, returning 0 matches")
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }

    func findNextInPage(completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let browserManager = browserManager,
            let activeWindowId = browserManager.windowRegistry?.activeWindow?.id
        {
            targetWebView = browserManager.getWebView(for: self.id, in: activeWindowId)
        } else {
            targetWebView = _webView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "Tab", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
            return
        }

        let script = """
            (function() {
                var highlights = document.querySelectorAll('.nook-find-highlight');
                if (highlights.length === 0) {
                    return { matchCount: 0, currentIndex: 0 };
                }

                // Find current active highlight
                var currentActive = document.querySelector('.nook-find-highlight.active');
                var currentIndex = 0;

                if (currentActive) {
                    // Remove active class from current
                    currentActive.classList.remove('active');
                    currentActive.style.backgroundColor = 'yellow';

                    // Find next highlight
                    var nextIndex = Array.from(highlights).indexOf(currentActive) + 1;
                    if (nextIndex >= highlights.length) {
                        nextIndex = 0; // Wrap to beginning
                    }
                    currentIndex = nextIndex + 1;
                } else {
                    // No active highlight, make first one active
                    currentIndex = 1;
                }

                // Set new active highlight
                var activeIndex = currentIndex - 1;
                if (activeIndex >= 0 && activeIndex < highlights.length) {
                    var activeHighlight = highlights[activeIndex];
                    activeHighlight.classList.add('active');
                    activeHighlight.style.backgroundColor = 'orange';
                    activeHighlight.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }

                return { matchCount: highlights.length, currentIndex: currentIndex };
            })();
            """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let dict = result as? [String: Any],
                let matchCount = dict["matchCount"] as? Int,
                let currentIndex = dict["currentIndex"] as? Int
            {
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }

    func findPreviousInPage(completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let browserManager = browserManager,
            let activeWindowId = browserManager.windowRegistry?.activeWindow?.id
        {
            targetWebView = browserManager.getWebView(for: self.id, in: activeWindowId)
        } else {
            targetWebView = _webView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "Tab", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
            return
        }

        let script = """
            (function() {
                var highlights = document.querySelectorAll('.nook-find-highlight');
                if (highlights.length === 0) {
                    return { matchCount: 0, currentIndex: 0 };
                }

                // Find current active highlight
                var currentActive = document.querySelector('.nook-find-highlight.active');
                var currentIndex = 0;

                if (currentActive) {
                    // Remove active class from current
                    currentActive.classList.remove('active');
                    currentActive.style.backgroundColor = 'yellow';

                    // Find previous highlight
                    var prevIndex = Array.from(highlights).indexOf(currentActive) - 1;
                    if (prevIndex < 0) {
                        prevIndex = highlights.length - 1; // Wrap to end
                    }
                    currentIndex = prevIndex + 1;
                } else {
                    // No active highlight, make last one active
                    currentIndex = highlights.length;
                }

                // Set new active highlight
                var activeIndex = currentIndex - 1;
                if (activeIndex >= 0 && activeIndex < highlights.length) {
                    var activeHighlight = highlights[activeIndex];
                    activeHighlight.classList.add('active');
                    activeHighlight.style.backgroundColor = 'orange';
                    activeHighlight.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }

                return { matchCount: highlights.length, currentIndex: currentIndex };
            })();
            """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let dict = result as? [String: Any],
                let matchCount = dict["matchCount"] as? Int,
                let currentIndex = dict["currentIndex"] as? Int
            {
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }

    func clearFindInPage() {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let browserManager = browserManager,
            let activeWindowId = browserManager.windowRegistry?.activeWindow?.id
        {
            targetWebView = browserManager.getWebView(for: self.id, in: activeWindowId)
        } else {
            targetWebView = _webView
        }

        guard let webView = targetWebView else { return }

        let script = """
            (function() {
                var highlights = document.querySelectorAll('.nook-find-highlight');
                highlights.forEach(function(el) {
                    var parent = el.parentNode;
                    parent.replaceChild(document.createTextNode(el.textContent), el);
                    parent.normalize();
                });
            })();
            """

        webView.evaluateJavaScript(script) { _, _ in }
    }
}

// MARK: - Hashable & Equatable
extension Tab {
    public static func == (lhs: Tab, rhs: Tab) -> Bool {
        return lhs.id == rhs.id
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        return id.hashValue
    }
}

extension Tab {
    func deliverContextMenuPayload(_ payload: WebContextMenuPayload?) {
        print("🔽 [Tab] deliverContextMenuPayload called, payload exists: \(payload != nil)")
        pendingContextMenuPayload = payload
        if let webView = _webView as? FocusableWKWebView {
            print("🔽 [Tab] Calling webView.contextMenuPayloadDidUpdate")
            webView.contextMenuPayloadDidUpdate(payload)
        } else {
            print("🔽 [Tab] WARNING: _webView is nil or not FocusableWKWebView")
        }
    }
}

// MARK: - NSColor Extension
extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else { return nil }

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
