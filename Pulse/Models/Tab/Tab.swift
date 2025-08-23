//
//  Tab.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
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
    @Published var hasAudioContent: Bool = false {  // Track if tab has any audio content (playing or paused)
        didSet {
            print("🔊 [Tab] hasAudioContent changed from \(oldValue) to \(hasAudioContent) for tab: \(name)")
        }
    }
    

    
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

        // Stop any media playback and clean up WebView
        _webView?.stopLoading()
        _webView?.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(el => el.pause());",
            completionHandler: nil
        )
        
        // Clean up all message handlers
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mediaStateChange_\(id.uuidString)")
        
        // Clean up media detection tracking for this tab
        let cleanupScript = """
        (() => {
            const tabId = '\(id.uuidString)';
            if (window.__pulseMediaDetectionInstalled && window.__pulseMediaDetectionInstalled[tabId]) {
                delete window.__pulseMediaDetectionInstalled[tabId];
            }
        })();
        """
        _webView?.evaluateJavaScript(cleanupScript, completionHandler: nil)
        
        _webView?.navigationDelegate = nil
        _webView?.uiDelegate = nil
        _webView = nil

        hasPlayingVideo = false
        hasPiPActive = false
        PiPManager.shared.stopPiP(for: self)

        loadingState = .idle

        browserManager?.tabManager.removeTab(self.id)
    }
    
    deinit {
        // Ensure cleanup when tab is deallocated
        // Note: We can't access main actor-isolated properties in deinit
        // The cleanup will happen in closeTab() method instead
    }

    func loadURL(_ newURL: URL) {
        self.url = newURL
        loadingState = .didStartProvisionalNavigation
        
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
    

    
    func requestPictureInPicture() {
        PiPManager.shared.requestPiP(for: self)
    }
    
    // MARK: - Simple Media Detection
    func checkMediaState() {
        guard let webView = _webView, isCurrentTab else { return }
        
        // Simple, reliable media detection
        let mediaCheckScript = """
        (() => {
            const audios = document.querySelectorAll('audio');
            const videos = document.querySelectorAll('video');
            
            // Check for any audio elements that are ready to play
            const hasAudioElements = Array.from(audios).some(audio => 
                audio.readyState >= 2 // HAVE_CURRENT_DATA or higher
            );
            
            // Check for videos with audio (not muted, has volume)
            const hasVideoWithAudio = Array.from(videos).some(video => 
                video.readyState >= 2 && !video.muted && video.volume > 0
            );
            
            const hasAudioContent = hasAudioElements || hasVideoWithAudio;
            
            // Check for currently playing media
            const hasPlayingAudio = Array.from(audios).some(audio => 
                !audio.paused && !audio.ended && audio.readyState >= 2
            );
            
            const hasPlayingVideoWithAudio = Array.from(videos).some(video => 
                !video.paused && !video.ended && video.readyState >= 2 && 
                !video.muted && video.volume > 0
            );
            
            return {
                hasAudioContent: hasAudioContent,
                hasPlayingAudio: hasPlayingAudio || hasPlayingVideoWithAudio,
                hasVideoContent: videos.length > 0,
                hasPlayingVideo: Array.from(videos).some(video => 
                    !video.paused && !video.ended && video.readyState >= 2
                )
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
                    
                    print("🎵 [Media Check] Audio content: \(self?.hasAudioContent ?? false)")
                }
            }
        }
    }
    
    private func injectMediaDetection(to webView: WKWebView) {
        let mediaDetectionScript = """
        (function() {
            const handlerName = 'mediaStateChange_\(id.uuidString)';
            
            function checkMediaState() {
                const audios = document.querySelectorAll('audio');
                const videos = document.querySelectorAll('video');
                
                const hasAudioElements = Array.from(audios).some(audio => 
                    audio.readyState >= 2
                );
                
                const hasVideoWithAudio = Array.from(videos).some(video => 
                    video.readyState >= 2 && !video.muted && video.volume > 0
                );
                
                const hasAudioContent = hasAudioElements || hasVideoWithAudio;
                const hasPlayingAudio = Array.from(audios).some(audio => 
                    !audio.paused && !audio.ended && audio.readyState >= 2
                );
                const hasPlayingVideoWithAudio = Array.from(videos).some(video => 
                    !video.paused && !video.ended && video.readyState >= 2 && 
                    !video.muted && video.volume > 0
                );
                
                window.webkit.messageHandlers[handlerName].postMessage({
                    hasAudioContent: hasAudioContent,
                    hasPlayingAudio: hasPlayingAudio || hasPlayingVideoWithAudio,
                    hasVideoContent: videos.length > 0,
                    hasPlayingVideo: Array.from(videos).some(video => 
                        !video.paused && !video.ended && video.readyState >= 2
                    )
                });
            }
            
            document.addEventListener('click', function() {
                setTimeout(checkMediaState, 100);
            }, true);
            
            const observer = new MutationObserver(function(mutations) {
                let hasNewMedia = false;
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) {
                            if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO' ||
                                node.querySelector && (node.querySelector('video') || node.querySelector('audio'))) {
                                hasNewMedia = true;
                            }
                        }
                    });
                });
                if (hasNewMedia) {
                    setTimeout(checkMediaState, 200);
                }
            });
            observer.observe(document.body, { childList: true, subtree: true });
            
            function addMediaListeners(element) {
                ['play', 'pause', 'ended', 'loadedmetadata', 'canplay', 'volumechange'].forEach(event => {
                    element.addEventListener(event, function() {
                        setTimeout(checkMediaState, 50);
                    });
                });
            }
            
            document.querySelectorAll('video, audio').forEach(addMediaListeners);
            
            const mediaObserver = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) {
                            if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') {
                                addMediaListeners(node);
                            } else if (node.querySelector) {
                                node.querySelectorAll('video, audio').forEach(addMediaListeners);
                            }
                        }
                    });
                });
            });
            mediaObserver.observe(document.body, { childList: true, subtree: true });
            
            setTimeout(checkMediaState, 500);
        })();
        """
        
        webView.evaluateJavaScript(mediaDetectionScript) { result, error in
            if let error = error {
                print("[Media Detection] Error: \(error.localizedDescription)")
            } else {
                print("[Media Detection] Comprehensive detection injected successfully")
            }
        }
    }
    
    func unloadWebView() {
        print("🔄 [Tab] Unloading webview for: \(name)")
        pause()
        
        // Remove from compositor if it exists
        _webView?.removeFromSuperview()
        
        // Clean up all message handlers
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandHover")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "commandClick")
        _webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pipStateChange")
        
        // Clear the webview reference (this will trigger reload when accessed)
        _webView = nil
        
        // Reset loading state
        loadingState = .idle
    }
    
    func loadWebViewIfNeeded() {
        if _webView == nil {
            print("🔄 [Tab] Loading webview for: \(name)")
            setupWebView()
        }
    }
    


    
    func toggleMute() {
        let muteScript = """
        (() => {
            const mediaElements = document.querySelectorAll('video, audio');
            const hasUnmutedMedia = Array.from(mediaElements).some(el => !el.muted && el.volume > 0);
            const targetMutedState = hasUnmutedMedia;
            
            mediaElements.forEach(el => {
                el.muted = targetMutedState;
                if (targetMutedState) {
                    el.volume = 0;
                } else {
                    el.volume = el.volume || 1.0;
                }
            });
            
            return targetMutedState;
        })();
        """
        
        _webView?.evaluateJavaScript(muteScript) { [weak self] result, error in
            if let muted = result as? Bool {
                DispatchQueue.main.async {
                    self?.isAudioMuted = muted
                }
            }
        }
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
            
            window.addEventListener('message', function(event) {
                if (event.data && event.data.type === 'PULSE_MUTE_CONTROL') {
                    const shouldMute = event.data.muted;
                    const mediaElements = document.querySelectorAll('video, audio');
                    mediaElements.forEach(media => {
                        media.muted = shouldMute;
                        if (shouldMute) {
                            media.volume = 0;
                        } else {
                            media.volume = media.volume || 1.0;
                        }
                    });
                    
                    if (window.__pulseAudioContexts) {
                        for (let context of window.__pulseAudioContexts) {
                            if (shouldMute && context.state === 'running') {
                                context.suspend().catch(e => console.log('[Iframe Mute] Context suspend error:', e));
                            } else if (!shouldMute && context.state === 'suspended') {
                                context.resume().catch(e => console.log('[Iframe Mute] Context resume error:', e));
                            }
                        }
                    }
                }
            });
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
        checkMediaState()
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
        checkMediaState()
        updateNavigationState()
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
                    self.isAudioMuted = dict["isAudioMuted"] ?? false
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
