//
//  Tab.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import AVFoundation
import CoreAudio
import FaviconFinder
import Foundation
import SwiftUI
import WebKit

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
    public let id: UUID
    var url: URL
    var name: String
    var favicon: SwiftUI.Image
    var spaceId: UUID?
    var index: Int

    // MARK: - Favicon Cache
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

    var isCurrentTab: Bool {
        return browserManager?.tabManager.currentTab?.id == id
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
        let configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration
        
        // Debug: Check what data store this WebView will use
        print("[Tab] Creating WebView with data store ID: \(configuration.websiteDataStore.identifier?.uuidString ?? "default")")
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

        _webView = WKWebView(frame: .zero, configuration: configuration)
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
        
        // Add handlers
        _webView?.configuration.userContentController.add(self, name: "linkHover")
        _webView?.configuration.userContentController.add(self, name: "commandHover")
        _webView?.configuration.userContentController.add(self, name: "commandClick")
        _webView?.configuration.userContentController.add(self, name: "pipStateChange")
        _webView?.configuration.userContentController.add(self, name: "mediaStateChange_\(id.uuidString)")
        _webView?.configuration.userContentController.add(self, name: "backgroundColor_\(id.uuidString)")

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
        loadURL(url)
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
                    if (window.__pulseAudioContexts) {
                        window.__pulseAudioContexts.forEach(ctx => ctx.close());
                        delete window.__pulseAudioContexts;
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
            if let containerView = browserManager?.compositorContainerView {
                for subview in containerView.subviews {
                    if subview === webView {
                        subview.removeFromSuperview()
                        print("Tab removed from compositor: \(name)")
                    }
                }
            }
            
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
        browserManager?.compositorManager.updateTabVisibility(currentTabId: browserManager?.tabManager.currentTab?.id)

        // 13. STOP NATIVE AUDIO MONITORING
        stopNativeAudioMonitoring()
        
        // 14. REMOVE THEME COLOR OBSERVER
        if let webView = _webView {
            removeThemeColorObserver(from: webView)
        }
        
        // 15. REMOVE FROM TAB MANAGER
        browserManager?.tabManager.removeTab(self.id)
        
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
            window.__pulseCurrentURL = window.location.href;
            
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
                    if (window.location.href !== window.__pulseCurrentURL) {
                        window.__pulseCurrentURL = window.location.href;
                        resetSoundTracking();
                    }
                }, 0);
            };
            
            history.replaceState = function(...args) {
                originalReplaceState.apply(history, args);
                setTimeout(() => {
                    if (window.location.href !== window.__pulseCurrentURL) {
                        window.__pulseCurrentURL = window.location.href;
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
                            if (window.__pulseLastDecodedBytes === undefined) {
                                window.__pulseLastDecodedBytes = {};
                            }
                            const lastBytes = window.__pulseLastDecodedBytes[audio.src] || 0;
                            if (decodedBytes > lastBytes && audio.currentTime > 0) {
                                drmAudioPlaying = true;
                            }
                            window.__pulseLastDecodedBytes[audio.src] = decodedBytes;
                        }
                        
                        // Check if current time is progressing (for DRM content)
                        if (!window.__pulseLastCurrentTime) window.__pulseLastCurrentTime = {};
                        const lastTime = window.__pulseLastCurrentTime[audio.src] || 0;
                        if (audio.currentTime > lastTime + 0.1 && audio.readyState >= 2) {
                            drmAudioPlaying = true;
                        }
                        window.__pulseLastCurrentTime[audio.src] = audio.currentTime;
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
                            if (!window.__pulseLastVideoBytes) window.__pulseLastVideoBytes = {};
                            const lastAudioBytes = window.__pulseLastVideoBytes[video.src + '_audio'] || 0;
                            const lastVideoBytes = window.__pulseLastVideoBytes[video.src + '_video'] || 0;
                            
                            if ((audioBytes > lastAudioBytes || videoBytes > lastVideoBytes) && video.currentTime > 0) {
                                drmVideoPlaying = true;
                            }
                            window.__pulseLastVideoBytes[video.src + '_audio'] = audioBytes;
                            window.__pulseLastVideoBytes[video.src + '_video'] = videoBytes;
                        }
                        
                        // Check if current time is progressing
                        if (!window.__pulseLastVideoCurrentTime) window.__pulseLastVideoCurrentTime = {};
                        const lastTime = window.__pulseLastVideoCurrentTime[video.src] || 0;
                        if (video.currentTime > lastTime + 0.1 && video.readyState >= 2) {
                            drmVideoPlaying = true;
                        }
                        window.__pulseLastVideoCurrentTime[video.src] = video.currentTime;
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
                if (window.__pulseAudioContexts) {
                    window.__pulseAudioContexts.forEach(ctx => ctx.close());
                    delete window.__pulseAudioContexts;
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
        guard let webView = _webView else {
            // Store the desired state even if webView isn't loaded yet
            DispatchQueue.main.async { [weak self] in
                self?.isAudioMuted = muted
                print("🔇 [Tab] Mute state set to \(muted) (webView not loaded yet)")
            }
            return
        }
        
        // Set the mute state using MuteableWKWebView's muted property
        webView.isMuted = muted
        
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
    private func setupThemeColorObserver(for webView: WKWebView) {
        if #available(macOS 12.0, *) {
            webView.addObserver(self, forKeyPath: "themeColor", options: [.new, .initial], context: nil)
        }
    }
    
    private func removeThemeColorObserver(from webView: WKWebView) {
        if #available(macOS 12.0, *) {
            webView.removeObserver(self, forKeyPath: "themeColor")
        }
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
            
            document.addEventListener('mouseover', function(e) {
                var target = e.target;
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href) {
                        if (currentHoveredLink !== target.href) {
                            currentHoveredLink = target.href;
                            sendLinkHover(target.href);
                            if (isCommandPressed) {
                                sendCommandHover(target.href);
                            }
                        }
                        return;
                    }
                    target = target.parentElement;
                }
            }, true);
            
            document.addEventListener('mouseout', function(e) {
                var target = e.target;
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href) {
                        if (currentHoveredLink === target.href) {
                            // Add a small delay before clearing hover state
                            setTimeout(function() {
                                if (currentHoveredLink === target.href) {
                                    currentHoveredLink = null;
                                    sendLinkHover(null);
                                    sendCommandHover(null);
                                }
                            }, 100);
                        }
                        return;
                    }
                    target = target.parentElement;
                }
            }, true);
            
            document.addEventListener('click', function(e) {
                var target = e.target;
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href && e.metaKey) {
                        e.preventDefault();
                        e.stopPropagation();
                        
                        currentHoveredLink = target.href;
                        sendLinkHover(target.href);
                        if (isCommandPressed) {
                            sendCommandHover(target.href);
                        }
                        
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commandClick) {
                            window.webkit.messageHandlers.commandClick.postMessage(target.href);
                        }
                        return false;
                    }
                    target = target.parentElement;
                }
            }, true);
        })();
        """
        
        webView.evaluateJavaScript(linkHoverScript) { result, error in
            if let error = error {
                print("Error injecting link hover JavaScript: \(error.localizedDescription)")
            }
        }
    }
    
    private func injectDownloadJavaScript(to webView: WKWebView) {
        let downloadScript = """
        (function() {
            // Override click handlers for download links
            document.addEventListener('click', function(e) {
                var target = e.target;
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href) {
                        var href = target.href.toLowerCase();
                        var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                        
                        for (var i = 0; i < downloadExtensions.length; i++) {
                            if (href.indexOf('.' + downloadExtensions[i]) !== -1) {
                                // Force download by creating a new link
                                var link = document.createElement('a');
                                link.href = target.href;
                                link.download = target.download || target.href.split('/').pop();
                                link.style.display = 'none';
                                document.body.appendChild(link);
                                link.click();
                                document.body.removeChild(link);
                                e.preventDefault();
                                e.stopPropagation();
                                return false;
                            }
                        }
                    }
                    target = target.parentElement;
                }
            }, true);
            
            // Override window.open for download links
            var originalOpen = window.open;
            window.open = function(url, name, features) {
                if (url && typeof url === 'string') {
                    var lowerUrl = url.toLowerCase();
                    var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                    
                    for (var i = 0; i < downloadExtensions.length; i++) {
                        if (lowerUrl.indexOf('.' + downloadExtensions[i]) !== -1) {
                            // Force download instead of opening in new window
                            var link = document.createElement('a');
                            link.href = url;
                            link.download = url.split('/').pop();
                            link.style.display = 'none';
                            document.body.appendChild(link);
                            link.click();
                            document.body.removeChild(link);
                            return null;
                        }
                    }
                }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
        
        webView.evaluateJavaScript(downloadScript) { result, error in
            if let error = error {
                print("Error injecting download JavaScript: \(error.localizedDescription)")
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
        }

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String {
                print("📄 [Tab] Got title from JavaScript: '\(title)'")
                DispatchQueue.main.async {
                    self?.updateTitle(title)
                    
                    // Add to global history after title is updated
                    if let currentURL = webView.url {
                        self?.browserManager?.historyManager.addVisit(
                            url: currentURL,
                            title: title,
                            timestamp: Date(),
                            tabId: self?.id
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
        
        injectDownloadJavaScript(to: webView)
        injectLinkHoverJavaScript(to: webView)
        injectPiPStateListener(to: webView)
        injectMediaDetection(to: webView)
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
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            let pathExtension = url.pathExtension.lowercased()
            let downloadExtensions: Set<String> = [
                "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                "mp4", "avi", "mov", "wmv", "flv", "mkv",
                "mp3", "wav", "aac", "flac",
                "exe", "dmg", "pkg", "deb", "rpm",
                "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"
            ]
            
            if downloadExtensions.contains(pathExtension) {
                decisionHandler(.download)
                return
            }
        }
        
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let mime = navigationResponse.response.mimeType?.lowercased() {
            let forceDownloadMIMEs: Set<String> = [
                // Images
                "image/jpeg",
                "image/png",
                "image/gif",
                "image/bmp",
                "image/tiff",
                "image/webp",
                // Archives
                "application/zip",
                "application/x-zip-compressed",
                "application/x-rar-compressed",
                "application/x-7z-compressed",
                "application/x-tar",
                "application/gzip",
                "application/x-gzip",
                // Documents
                "application/pdf",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/vnd.ms-powerpoint",
                "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                // Media
                "video/mp4",
                "video/avi",
                "video/quicktime",
                "video/x-msvideo",
                "audio/mpeg",
                "audio/wav",
                "audio/aac",
                // Executables
                "application/x-executable",
                "application/x-dosexec",
                "application/x-msdownload",
                // Generic binary
                "application/octet-stream",
                "application/binary",
            ]
            
            if forceDownloadMIMEs.contains(mime) {
                decisionHandler(.download)
                return
            }
        }
        
        // Also check URL path for common file extensions
        if let url = navigationResponse.response.url {
            let pathExtension = url.pathExtension.lowercased()
            let downloadExtensions: Set<String> = [
                "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                "mp4", "avi", "mov", "wmv", "flv", "mkv",
                "mp3", "wav", "aac", "flac",
                "exe", "dmg", "pkg", "deb", "rpm",
                "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"
            ]
            
            if downloadExtensions.contains(pathExtension) {
                decisionHandler(.download)
                return
            }
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
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
        print("Download started from navigationAction: \(originalURL.absoluteString)")
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationResponse.response.url ?? URL(string: "https://example.com")!
        let suggestedFilename = navigationResponse.response.url?.lastPathComponent ?? "download"
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
        print("Download started from navigationResponse: \(originalURL.absoluteString)")
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
        
        default:
            break
        }
    }
    
    private func handleCommandClick(url: URL) {
        // Create a new tab with the URL and focus it
        browserManager?.tabManager.createNewTab(url: url.absoluteString, in: browserManager?.tabManager.currentSpace)
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
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
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
