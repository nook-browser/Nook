//
//  Tab.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import AVFoundation
import CoreAudio
import FaviconFinder
import Foundation
import Combine
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
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool = false

    // MARK: - Favicon Cache
    // Global favicon cache shared across profiles by design to increase hit rate
    // and reduce duplicate downloads. If per-profile isolation is required later,
    // this can be namespaced by profileId in the cache key.
    private static var faviconCache: [String: SwiftUI.Image] = [:]
    private static let faviconCacheQueue = DispatchQueue(label: "favicon.cache", attributes: .concurrent)
    private static let faviconCacheLock = NSLock()

    // MARK: - Loading State
    enum LoadingState {
        case idle
        case didStartProvisionalNavigation
        case didCommit
        case didFinish
        case didFail(Error)
        case didFailProvisionalNavigation(Error)

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

    var canGoBack: Bool = false
    var canGoForward: Bool = false
    
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
    
    // MARK: - Native Audio Monitoring
    private var audioDeviceListenerProc: AudioObjectPropertyListenerProc?
    private var isMonitoringNativeAudio = false
    private var lastAudioDeviceCheckTime: Date = Date()
    private var audioMonitoringTimer: Timer?
    private var hasAddedCoreAudioListener = false
    private var profileAwaitCancellable: AnyCancellable?
    

    
    // MARK: - Tab State
    var isUnloaded: Bool {
        return _webView == nil
    }

    private var _webView: WKWebView?
    var didNotifyOpenToExtensions: Bool = false
    var webView: WKWebView? {
        if _webView == nil {
            print("🔧 [Tab] First webView access, calling setupWebView() for: \(url.absoluteString)")
            setupWebView()
        }
        return _webView
    }
    
    var activeWebView: WKWebView {
        if _webView == nil {
            print("🔧 [Tab] First webView access, calling setupWebView() for: \(url.absoluteString)")
            setupWebView()
        }
        return _webView!
    }

    weak var browserManager: BrowserManager?
    
    // MARK: - Link Hover Callback
    var onLinkHover: ((String?) -> Void)? = nil
    var onCommandHover: ((String?) -> Void)? = nil

    private let themeColorObservedWebViews = NSHashTable<AnyObject>.weakObjects()

    var isCurrentTab: Bool {
        // This property is used in contexts where we don't have window state
        // For now, we'll keep it using the global current tab for backward compatibility
        return browserManager?.tabManager.currentTab?.id == id
    }
    
    var isActiveInSpace: Bool {
        guard let spaceId = self.spaceId,
              let browserManager = self.browserManager,
              let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) else {
            return isCurrentTab // Fallback to current tab for pinned tabs or if no space
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
        browserManager: BrowserManager? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.index = index
        self.browserManager = browserManager
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
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let resolvedProfile = resolveProfile()
        let configuration: WKWebViewConfiguration
        if let profile = resolvedProfile {
            configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(for: profile)
        } else {
            // Edge case: currentProfile not yet available. Delay creating WKWebView until it resolves.
            if profileAwaitCancellable == nil {
                print("[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile…")
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
        
        // Debug: Check what data store this WebView will use
        let profileInfo = resolvedProfile.map { "\($0.name) [\($0.id.uuidString)]" } ?? "nil"
        print("[Tab] Resolved profile: \(profileInfo)")
        let storeIdString: String = configuration.websiteDataStore.identifier?.uuidString ?? "default"
        print("[Tab] Creating WebView with data store ID: \(storeIdString)")
        print("[Tab] Data store is persistent: \(configuration.websiteDataStore.isPersistent)")
        
        // CRITICAL: Ensure the configuration has access to extension controller for ALL URLs
        // Extensions may load additional resources that also need access
        if #available(macOS 15.5, *) {
            print("🔍 [Tab] Checking extension controller setup...")
            print("   Configuration has controller: \(configuration.webExtensionController != nil)")
            print("   ExtensionManager has controller: \(ExtensionManager.shared.nativeController != nil)")
            
            if configuration.webExtensionController == nil {
                if let controller = ExtensionManager.shared.nativeController {
                    configuration.webExtensionController = controller
                    print("🔧 [Tab] Added extension controller to configuration for resource access")
                    print("   Controller contexts: \(controller.extensionContexts.count)")
                } else {
                    print("❌ [Tab] No extension controller available from ExtensionManager")
                }
            } else {
                print("✅ [Tab] Configuration already has extension controller")
                if let controller = configuration.webExtensionController {
                    print("   Controller contexts: \(controller.extensionContexts.count)")
                }
            }
        }

        _webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        if let fv = _webView as? FocusableWKWebView { fv.owningTab = self }
        _webView?.navigationDelegate = self
        _webView?.uiDelegate = self
        _webView?.allowsBackForwardNavigationGestures = true
        _webView?.allowsMagnification = true
        
        if let webView = _webView {
            setupThemeColorObserver(for: webView)
        }
        
        // Remove existing handlers first to prevent duplicates
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mediaStateChange_\(id.uuidString)")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "backgroundColor_\(id.uuidString)")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "historyStateDidChange")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "NookIdentity")
        
        // Add handlers
        _webView?.configuration.userContentController.add(self, name: "linkHover")
        _webView?.configuration.userContentController.add(self, name: "commandHover")
        _webView?.configuration.userContentController.add(self, name: "commandClick")
        _webView?.configuration.userContentController.add(self, name: "pipStateChange")
        _webView?.configuration.userContentController.add(self, name: "mediaStateChange_\(id.uuidString)")
        _webView?.configuration.userContentController.add(self, name: "backgroundColor_\(id.uuidString)")
        _webView?.configuration.userContentController.add(self, name: "historyStateDidChange")
        _webView?.configuration.userContentController.add(self, name: "NookIdentity")

        _webView?.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"

        _webView?.setValue(false, forKey: "drawsBackground")

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

        print("Created WebView for tab: \(name)")
        // Inform extensions that this tab's view is now open/available BEFORE loading,
        // so content scripts and messaging can resolve this tab during early document phases
        if #available(macOS 15.5, *), didNotifyOpenToExtensions == false {
            ExtensionManager.shared.notifyTabOpened(self)
            didNotifyOpenToExtensions = true
        }
        // For popup-hosting tabs, don't trigger an initial navigation. WebKit will
        // drive the load into this returned webView from createWebViewWith:.
        if !isPopupHost {
            loadURL(url)
        }
    }

    // Resolve the Profile for this tab via its space association, or fall back to currentProfile, then default profile
    func resolveProfile() -> Profile? {
        // Attempt to resolve via associated space
        if let sid = spaceId,
           let space = browserManager?.tabManager.spaces.first(where: { $0.id == sid }) {
            if let pid = space.profileId,
               let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid }) {
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

        // KILL TAB: Complete destruction of WKWebView and all associated processes
        if let webView = _webView {
            // 1. STOP EVERYTHING IMMEDIATELY
            webView.stopLoading()
            
            // 2. KILL ALL MEDIA AND PiP VIA JAVASCRIPT (including PiP destruction)
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
                    print("[Tab] Error during media/PiP kill: \(error.localizedDescription)")
                } else {
                    print("[Tab] Media and PiP successfully killed for: \(self.name)")
                }
            }
            
            // 4. REMOVE ALL MESSAGE HANDLERS
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaStateChange_\(id.uuidString)")
            
            // 5. CLEAR ALL DELEGATES
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            
            // 6. REMOVE FROM ALL VIEW HIERARCHIES
            webView.removeFromSuperview()
            
            // 7. FORCE REMOVE FROM COMPOSITOR
            browserManager?.removeWebViewFromContainers(webView)
            
            // 8. FORCE TERMINATE WEB CONTENT PROCESS
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
            
            // 9. ACCESS PROCESS POOL TO FORCE TERMINATION
            _ = webView.configuration.processPool
            
            // 10. CLEAR THE REFERENCE
            _webView = nil
        }

        // 11. RESET ALL STATE
        hasPlayingVideo = false
        hasVideoContent = false
        hasPlayingAudio = false
        hasAudioContent = false
        isAudioMuted = false
        hasPiPActive = false
        loadingState = .idle

        // 12. FORCE COMPOSITOR UPDATE
        // Note: This is called during tab loading, so we use the global current tab
        // The compositor will handle window-specific visibility in its update methods
        browserManager?.compositorManager.updateTabVisibility(currentTabId: browserManager?.tabManager.currentTab?.id)

        // 13. STOP NATIVE AUDIO MONITORING
        stopNativeAudioMonitoring()
        
        // 14. REMOVE THEME COLOR OBSERVER
        if let webView = _webView {
            removeThemeColorObserver(from: webView)
        }
        
        // 15. REMOVE FROM TAB MANAGER
        browserManager?.tabManager.removeTab(self.id)
        
        // Cancel any pending profile observation
        profileAwaitCancellable?.cancel()
        profileAwaitCancellable = nil
        
        print("Tab killed: \(name)")
    }
    

    
    deinit {
        // Ensure cleanup when tab is deallocated
        // Note: We can't access main actor-isolated properties in deinit
        // The cleanup will happen in closeTab() method instead
    }

    func loadURL(_ newURL: URL) {
        self.url = newURL
        loadingState = .didStartProvisionalNavigation
        
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
        let engine = browserManager?.settingsManager.searchEngine ?? .google
        let normalizedUrl = normalizeURL(input, provider: engine)
        
        guard let validURL = URL(string: normalizedUrl) else {
            print("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }
        
        print("🌐 [Tab] Navigating current tab to: \(normalizedUrl)")
        loadURL(validURL)
    }
    

    
    func requestPictureInPicture() {
        PiPManager.shared.requestPiP(for: self)
    }
    
    // MARK: - Simple Media Detection (mainly for manual checks)
    func checkMediaState() {
        guard let webView = _webView else { return }
        
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
        
        webView.evaluateJavaScript(mediaCheckScript) { [weak self] result, error in
            if let error = error {
                print("[Media Check] Error: \(error.localizedDescription)")
                return
            }
            
            if let state = result as? [String: Bool] {
                DispatchQueue.main.async {
                    self?.hasAudioContent = state["hasAudioContent"] ?? false
                    self?.hasPlayingAudio = state["hasPlayingAudio"] ?? false
                    self?.hasVideoContent = state["hasVideoContent"] ?? false
                    self?.hasPlayingVideo = state["hasPlayingVideo"] ?? false
                }
            }
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
        
        // Clean up message handlers
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaStateChange_\(id.uuidString)")
        
        // Remove from view hierarchy and clear delegates
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        // FORCE TERMINATE THE WEB CONTENT PROCESS
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { _ in }
        
        // Remove theme color observer before clearing webview reference
        if let webView = _webView {
            removeThemeColorObserver(from: webView)
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

        browserManager?.setMuteState(muted, for: id, originatingWindowId: browserManager?.activeWindowState?.id)

        // Update our internal state
        DispatchQueue.main.async { [weak self] in
            self?.isAudioMuted = muted
        }
    }
    
    // MARK: - Native Audio Monitoring
    private func startNativeAudioMonitoring() {
        guard !isMonitoringNativeAudio else { return }
        isMonitoringNativeAudio = true
        
        audioMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkNativeAudioActivity()
        }
        
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
            webView.addObserver(self, forKeyPath: "themeColor", options: [.new, .initial], context: nil)
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
    
    func cleanupCloneWebView(_ webView: WKWebView) {
        removeThemeColorObserver(from: webView)
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "linkHover")
        controller.removeScriptMessageHandler(forName: "commandHover")
        controller.removeScriptMessageHandler(forName: "commandClick")
        controller.removeScriptMessageHandler(forName: "pipStateChange")
        controller.removeScriptMessageHandler(forName: "mediaStateChange_\(id.uuidString)")
        controller.removeScriptMessageHandler(forName: "backgroundColor_\(id.uuidString)")
        controller.removeScriptMessageHandler(forName: "historyStateDidChange")
        controller.removeScriptMessageHandler(forName: "NookIdentity")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "themeColor", let webView = object as? WKWebView {
            updateBackgroundColor(from: webView)
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    private func updateBackgroundColor(from webView: WKWebView) {
        var newColor: NSColor? = nil
        
        if #available(macOS 12.0, *) {
            newColor = webView.themeColor
        }
        
        if let themeColor = newColor {
            DispatchQueue.main.async { [weak self] in
                self?.pageBackgroundColor = themeColor
                webView.underPageBackgroundColor = themeColor
            }
        } else {
            extractBackgroundColorWithJavaScript(from: webView)
        }
    }
    
    private func extractBackgroundColorWithJavaScript(from webView: WKWebView) {
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
                print("[Tab] Error injecting history observer JavaScript: \(error.localizedDescription)")
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
        self.name = title.isEmpty ? url.host ?? "New Tab" : title
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

                // Cache the favicon
                Self.cacheFavicon(swiftUIImage, for: cacheKey)
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
        return faviconCache[key]
    }

    static func cacheFavicon(_ favicon: SwiftUI.Image, for key: String) {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        
        faviconCache[key] = favicon
        
        // Limit cache size to prevent memory issues
        if faviconCache.count > 100 {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(faviconCache.keys.prefix(20))
            for key in keysToRemove {
                faviconCache.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Cache Management
    static func clearFaviconCache() {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        faviconCache.removeAll()
    }
    
    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        return (faviconCache.count, Array(faviconCache.keys))
    }
}

// MARK: - WKNavigationDelegate
extension Tab: WKNavigationDelegate {

    // MARK: - Loading Start
    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        print("🌐 [Tab] didStartProvisionalNavigation for: \(webView.url?.absoluteString ?? "unknown")")
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
                print("🔄 [Tab] Swift reset audio tracking for navigation to: \(newURL.absoluteString)")
            }
            self.url = newURL
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
            if #available(macOS 15.5, *) {
                ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.URL])
            }
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
            }
            browserManager?.syncTabAcrossWindows(self.id)
        }

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String {
                print("📄 [Tab] Got title from JavaScript: '\(title)'")
                DispatchQueue.main.async {
                    self?.updateTitle(title)
                    
                    // Add to profile-aware history after title is updated
                    if let currentURL = webView.url {
                        let profileId = self?.resolveProfile()?.id ?? self?.browserManager?.currentProfile?.id
                        self?.browserManager?.historyManager.addVisit(
                            url: currentURL,
                            title: title,
                            timestamp: Date(),
                            tabId: self?.id,
                            profileId: profileId
                        )
                    }
                }
            } else if let jsError = error {
                print("⚠️ [Tab] Failed to get document.title: \(jsError.localizedDescription)")
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
        updateNavigationState()
        
        // Trigger background color extraction
        updateBackgroundColor(from: webView)
        
        // Apply mute state using MuteableWKWebView if the tab was previously muted
        if isAudioMuted {
            setMuted(true)
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

        updateNavigationState()
    }

    // MARK: - Loading Failed (before content started loading)
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print("💥 [Tab] didFailProvisionalNavigation for: \(webView.url?.absoluteString ?? "unknown")")
        print("   Error: \(error.localizedDescription)")
        loadingState = .didFailProvisionalNavigation(error)

        // Set connection error favicon
        Task { @MainActor in
            self.favicon = Image(systemName: "wifi.exclamationmark")
        }

        updateNavigationState()
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
           navigationAction.targetFrame?.isMainFrame == true {
            browserManager?.maybeShowOAuthAssist(for: url, in: self)
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
           disposition.lowercased().contains("attachment") {
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
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
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
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }
    
    // MARK: - WKDownloadDelegate
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        print("🔽 [Tab] WKDownloadDelegate decideDestinationUsing called")
        // Handle download destination directly
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
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
    
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL, Bool) -> Void) {
        print("🔽 [Tab] WKDownloadDelegate decideDestinationUsing (macOS) called")
        // Handle download destination directly for macOS
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(FileManager.default.temporaryDirectory.appendingPathComponent("download"), false)
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
        completionHandler(dest, false) // false = don't allow overwrite
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
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
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
               let colorHex = dict["backgroundColor"] {
                DispatchQueue.main.async {
                    self.pageBackgroundColor = NSColor(hex: colorHex)
                    if let webView = self._webView, let color = NSColor(hex: colorHex) {
                        webView.underPageBackgroundColor = color
                    }
                }
            }
        
        case "historyStateDidChange":
            if let href = message.body as? String, let url = URL(string: href) {
                DispatchQueue.main.async {
                    if self.url.absoluteString != url.absoluteString {
                        self.url = url
                        self.browserManager?.syncTabAcrossWindows(self.id)
                    }
                }
            }

        case "NookIdentity":
            handleOAuthRequest(message: message)

        default:
            break
        }
    }
    
    private func handleCommandClick(url: URL) {
        // Create a new tab with the URL and focus it
        browserManager?.tabManager.createNewTab(url: url.absoluteString, in: browserManager?.tabManager.currentSpace)
    }
    
    private func handleOAuthRequest(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let urlString = dict["url"] as? String,
              let url = URL(string: urlString) else {
            print("❌ [Tab] Invalid OAuth request: missing or invalid URL")
            return
        }
        let interactive = dict["interactive"] as? Bool ?? true
        let prefersEphemeral = dict["prefersEphemeral"] as? Bool ?? false
        let providedScheme = (dict["callbackScheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRequestId = (dict["requestId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = (rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString)

        print("🔐 [Tab] OAuth request received: id=\(requestId) url=\(url.absoluteString) interactive=\(interactive) ephemeral=\(prefersEphemeral) scheme=\(providedScheme ?? "nil")")

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
            print("🔐 [Tab] Identity flow completed: id=\(requestId) status=\(status) url=\(urlDescription)")
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ [Tab] Failed to serialise identity payload for requestId=\(requestId)")
            return
        }

        let script = "window.__nookCompleteIdentityFlow && window.__nookCompleteIdentityFlow(\(jsonString));"
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
            "oauth", "auth", "login", "signin"
        ]
        
        // Check if host contains OAuth-related terms
        if oauthHosts.contains(where: { host.contains($0) }) {
            return true
        }
        
        // Check for OAuth paths and query parameters
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize") || 
           path.contains("/signin") || path.contains("/login") || path.contains("/callback") {
            return true
        }
        
        if query.contains("client_id=") || query.contains("redirect_uri=") || 
           query.contains("response_type=") || query.contains("scope=") {
            return true
        }
        
        // Check window features that suggest external/popup behavior
        if let width = windowFeatures.width, let height = windowFeatures.height,
           width.doubleValue > 0 && height.doubleValue > 0 {
            // If specific dimensions are set, it's likely a popup
            return true
        }
        
        // Note: WKWindowFeatures visibility properties are NSNumber? and don't directly map to enum values
        // We'll rely on URL patterns and dimensions for popup detection
        
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
        
        // Check if this is likely an OAuth popup or external window
        if let url = navigationAction.request.url,
           isLikelyOAuthOrExternalWindow(url: url, windowFeatures: windowFeatures) {
            print("🪟 [Tab] Popup detected, opening in miniwindow: \(url.absoluteString)")
            // Present in miniwindow with completion callback
            bm.externalMiniWindowManager.present(url: url) { [weak self] success, finalURL in
                self?.handleMiniWindowAuthCompletion(success: success, finalURL: finalURL)
            }
            return nil // Don't create a WebView, we're using the miniwindow
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
        if let fv = newWebView as? FocusableWKWebView {
            fv.owningTab = newTab
        }
        
        // Store the webView in the new tab
        newTab._webView = newWebView
        
        // Set up message handlers
        // Remove any existing handlers first to avoid duplicates
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaStateChange_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "backgroundColor_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "historyStateDidChange")
        newWebView.configuration.userContentController.removeScriptMessageHandler(forName: "NookIdentity")
        
        // Now add the handlers
        newWebView.configuration.userContentController.add(newTab, name: "linkHover")
        newWebView.configuration.userContentController.add(newTab, name: "commandHover")
        newWebView.configuration.userContentController.add(newTab, name: "commandClick")
        newWebView.configuration.userContentController.add(newTab, name: "pipStateChange")
        newWebView.configuration.userContentController.add(newTab, name: "mediaStateChange_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.add(newTab, name: "backgroundColor_\(newTab.id.uuidString)")
        newWebView.configuration.userContentController.add(newTab, name: "historyStateDidChange")
        newWebView.configuration.userContentController.add(newTab, name: "NookIdentity")
        
        // Set custom user agent
        newWebView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        
        // Configure preferences
        newWebView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        newWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // Load the URL if provided
        if let url = navigationAction.request.url, url.scheme != nil, url.absoluteString != "about:blank" {
            newTab.loadURL(url)
        }
        
        return newWebView
    }

    private func handleMiniWindowAuthCompletion(success: Bool, finalURL: URL?) {
        print("🪟 [Tab] Popup OAuth flow completed: success=\(success), finalURL=\(finalURL?.absoluteString ?? "nil")")

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
}

// MARK: - Find in Page
extension Tab {
    typealias FindResult = Result<(matchCount: Int, currentIndex: Int), Error>
    typealias FindCompletion = @Sendable (FindResult) -> Void
    
    func findInPage(_ text: String, completion: @escaping FindCompletion) {
        guard let webView = _webView else {
            completion(.failure(NSError(domain: "Tab", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
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
               let currentIndex = dict["currentIndex"] as? Int {
                print("Find found \(matchCount) matches, current index: \(currentIndex)")
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                print("Find result parsing failed, returning 0 matches")
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }
    
    func findNextInPage(completion: @escaping FindCompletion) {
        guard let webView = _webView else {
            completion(.failure(NSError(domain: "Tab", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
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
               let currentIndex = dict["currentIndex"] as? Int {
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }
    
    func findPreviousInPage(completion: @escaping FindCompletion) {
        guard let webView = _webView else {
            completion(.failure(NSError(domain: "Tab", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView not available"])))
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
               let currentIndex = dict["currentIndex"] as? Int {
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }
    
    func clearFindInPage() {
        guard let webView = _webView else { return }
        
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
