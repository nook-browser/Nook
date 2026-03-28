//
//  MediaControlsManager.swift
//  Nook
//
//  Created by apelreflex on 13/10/2025.
//

import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class MediaControlsManager {
    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?
    weak var windowRegistry: WindowRegistry?

    /// Cached active media tab to avoid iterating all tabs on every query.
    /// Set when media is found playing; cleared when the tab stops playing or is deallocated.
    private weak var _cachedActiveMediaTab: Tab?

    /// List of media host domains that support media controls
    /// Add new domains here to expand support to other platforms
    private let mediaHosts: [String] = [
        "youtube.com",
        "youtu.be"
        // Future: Add more platforms like "vimeo.com", "twitch.tv", etc.
    ]

    init(browserManager: BrowserManager? = nil, windowState: BrowserWindowState? = nil) {
        self.browserManager = browserManager
        self.windowState = windowState
    }

    // MARK: - Media Tab Detection

    /// Check if any tab has actively playing media from supported hosts
    func hasActiveMediaTab() -> Bool {
        guard browserManager != nil else { return false }
        return findActiveMediaTab() != nil
    }

    /// Find the first tab with actively playing media (prioritize tabs with playing media).
    /// Uses a cached weak reference to avoid iterating all tabs when possible.
    func findActiveMediaTab() -> Tab? {
        // Fast path: check if the cached tab is still actively playing media
        if let cached = _cachedActiveMediaTab,
           isMediaHostURL(cached.url),
           (cached.hasPlayingAudio || cached.hasPlayingVideo) {
            return cached
        }

        // Cache miss or stale — fall back to full search
        _cachedActiveMediaTab = nil

        guard let browserManager = browserManager else {
            return nil
        }
        let allTabs = browserManager.tabManager.allTabs()

        for tab in allTabs {
            let isMediaHost = isMediaHostURL(tab.url)
            let hasAudio = tab.hasPlayingAudio
            let hasVideo = tab.hasPlayingVideo

            if isMediaHost && (hasAudio || hasVideo) {
                _cachedActiveMediaTab = tab
                return tab
            }
        }

        return nil
    }

    /// Refresh a tab's title by reading document.title directly from the webview.
    /// Ensures the tab name stays in sync even if KVO misses a YouTube SPA title change.
    func refreshTitle(for tab: Tab) async {
        let webViews = resolveWebViews(for: tab)
        for webView in webViews {
            if let title = try? await webView.evaluateJavaScript("document.title") as? String,
               !title.isEmpty, title != tab.name {
                tab.updateTitle(title)
                break
            }
        }
    }

    /// Check if a URL is from a supported media host
    private func isMediaHostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return mediaHosts.contains(where: { host.contains($0) })
    }

    private func resolveWebViews(for tab: Tab) -> [WKWebView] {
        var webViews: [WKWebView] = []

        if let browserManager = browserManager {
            if let windowId = windowState?.id,
               let windowWebView = browserManager.getWebView(for: tab.id, in: windowId) {
                webViews.append(windowWebView)
            }

            if let coordinator = browserManager.webViewCoordinator {
                let additional = coordinator.getAllWebViews(for: tab.id)
                for candidate in additional where !webViews.contains(where: { $0 === candidate }) {
                    webViews.append(candidate)
                }
            }
        }

        // Use assignedWebView as fallback to avoid triggering lazy initialization
        // Media controls only work on tabs that are currently displayed
        if webViews.isEmpty, let fallback = tab.assignedWebView {
            webViews.append(fallback)
        }

        return webViews
    }

    @discardableResult
    private func executeMediaScript(for tab: Tab, script: String, description: String) async -> (handled: Bool, payload: Any?) {
        let webViews = resolveWebViews(for: tab)
        var handled = false
        var payload: Any?

        for webView in webViews {
            do {
                let result = try await webView.evaluateJavaScript(script)

                if let dict = result as? [String: Any],
                   let didHandle = dict["handled"] as? Bool {
                    if didHandle {
                        handled = true
                        payload = dict
                        break
                    }
                    continue
                }

                if let boolResult = result as? Bool {
                    handled = boolResult
                    if boolResult {
                        payload = boolResult
                        break
                    }
                } else if result != nil {
                    handled = true
                    payload = result
                    break
                }
            } catch {
            }
        }

        return (handled, payload)
    }

    // MARK: - Media Controls

    /// Toggle play/pause on media player
    func playPause(tab explicitTab: Tab? = nil) async -> Bool? {
        guard let tab = explicitTab ?? findActiveMediaTab() else { return nil }

        let script = """
        (function() {
            const video = document.querySelector('video');
            if (video) {
                if (video.paused) {
                    video.play();
                } else {
                    video.pause();
                }
                return { handled: true, isPlaying: !video.paused, mediaType: 'video' };
            }
            const audio = document.querySelector('audio');
            if (audio) {
                if (audio.paused) {
                    audio.play();
                } else {
                    audio.pause();
                }
                return { handled: true, isPlaying: !audio.paused, mediaType: 'audio' };
            }
            return { handled: false, isPlaying: false };
        })();
        """

        let result = await executeMediaScript(for: tab, script: script, description: "toggle play/pause")
        var playbackState: Bool?

        if result.handled,
           let info = result.payload as? [String: Any],
           let playing = info["isPlaying"] as? Bool {
            let mediaType = (info["mediaType"] as? String)?.lowercased()

            if mediaType == "video" {
                tab.hasPlayingVideo = playing
                tab.hasPlayingAudio = playing
            } else if mediaType == "audio" {
                tab.hasPlayingAudio = playing
                if !playing {
                    tab.hasPlayingVideo = false
                }
            } else {
                tab.hasPlayingAudio = playing
                tab.hasPlayingVideo = playing
            }

            playbackState = playing
        }

        return playbackState
    }

    /// Skip to next video
    func next(tab explicitTab: Tab? = nil) async {
        guard let tab = explicitTab ?? findActiveMediaTab() else { return }

        let script = """
        (function() {
            const nextButton = document.querySelector('.ytp-next-button');
            if (nextButton) {
                nextButton.click();
                return { handled: true };
            }

            const mediaElement = document.querySelector('video, audio');
            if (mediaElement) {
                const event = new KeyboardEvent('keydown', {
                    key: 'N',
                    shiftKey: true,
                    bubbles: true
                });
                document.dispatchEvent(event);
                return { handled: true };
            }

            return { handled: false };
        })();
        """

        _ = await executeMediaScript(for: tab, script: script, description: "skip to next")

        // YouTube takes time to navigate after clicking next — refresh title after a delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        await refreshTitle(for: tab)
    }

    /// Skip to previous video
    func previous(tab explicitTab: Tab? = nil) async {
        guard let tab = explicitTab ?? findActiveMediaTab() else { return }

        let script = """
        (function() {
            const prevButton = document.querySelector('.ytp-prev-button');
            if (prevButton) {
                prevButton.click();
                return { handled: true };
            }

            const mediaElement = document.querySelector('video, audio');
            if (mediaElement) {
                const event = new KeyboardEvent('keydown', {
                    key: 'P',
                    shiftKey: true,
                    bubbles: true
                });
                document.dispatchEvent(event);
                return { handled: true };
            }

            return { handled: false };
        })();
        """

        _ = await executeMediaScript(for: tab, script: script, description: "skip to previous")

        // YouTube takes time to navigate after clicking previous — refresh title after a delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        await refreshTitle(for: tab)
    }

    /// Toggle mute state
    func toggleMute(tab explicitTab: Tab? = nil) async -> Bool? {
        guard let tab = explicitTab ?? findActiveMediaTab() else { return nil }

        let newMutedState = !(tab.isAudioMuted)
        tab.setMuted(newMutedState)

        if let browserManager = browserManager,
           let windowId = windowState?.id,
           windowRegistry?.activeWindow?.id != windowId {
            browserManager.setMuteState(newMutedState, for: tab.id, originatingWindowId: windowId)
        }

        return newMutedState
    }

    /// Get current playback state
    func isPlaying(tab explicitTab: Tab? = nil) async -> Bool {
        guard let tab = explicitTab ?? findActiveMediaTab() else { return false }

        let script = """
        (function() {
            const video = document.querySelector('video');
            if (video) {
                return { handled: true, isPlaying: !video.paused };
            }
            const audio = document.querySelector('audio');
            if (audio) {
                return { handled: true, isPlaying: !audio.paused };
            }
            return { handled: false, isPlaying: false };
        })();
        """

        for webView in resolveWebViews(for: tab) {
            do {
                let result = try await webView.evaluateJavaScript(script)

                if let dict = result as? [String: Any],
                   let handled = dict["handled"] as? Bool,
                   handled {
                    return (dict["isPlaying"] as? Bool) ?? false
                }

                if let boolResult = result as? Bool {
                    return boolResult
                }
            } catch {
            }
        }

        return false
    }
}
