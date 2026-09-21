// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Scripts.swift
//  Nook
//
//  Script message handlers and injected page scripts for a PageSession.
//

import SwiftUI
import WebKit
import NookTweaks

extension PageSession {
    /// Script message handler names this session registers on each of its web views.
    var messageHandlerNames: [String] {
        ["linkHover", "commandHover", "pipStateChange",
         "mediaStateChange_\(itemID.uuidString)", "backgroundColor_\(itemID.uuidString)",
         "historyStateDidChange", "nookShortcutDetect",
         "nookSponsorBlock"]
    }

    /// Per-document observers. Each script guards against a second install in the same document.
    func injectPageObservers(into webView: WKWebView) {
        injectLinkHoverJavaScript(to: webView)
        injectPiPStateListener(to: webView)
        injectMediaDetection(to: webView)
        injectHistoryStateObserver(into: webView)
        injectShortcutDetection(to: webView)
    }

    func injectMediaDetection(to webView: WKWebView) {
        let mediaDetectionScript = """
            (function() {
                if (window.__nookMediaDetectionInstalled) return;
                window.__nookMediaDetectionInstalled = true;
                const handlerName = 'mediaStateChange_\(itemID.uuidString)';
                const media = new Set(document.querySelectorAll('audio, video'));
                let pendingCheck = null;
                let lastState = null;
                const host = location.hostname;
                const streamingSelector = host.endsWith('spotify.com')
                    ? '[data-testid="control-button-playpause"]'
                    : host.endsWith('soundcloud.com') ? '.playControl'
                    : host === 'music.apple.com' ? '.web-chrome-playback-controls' : null;
                let streamingControl = null;
                const controlObserver = new MutationObserver(scheduleCheck);

                function refreshStreamingControl() {
                    if (!streamingSelector || streamingControl?.isConnected) return;
                    controlObserver.disconnect();
                    streamingControl = document.querySelector(streamingSelector);
                    if (streamingControl) controlObserver.observe(streamingControl, {
                        attributes: true, childList: true, subtree: true,
                        attributeFilter: ['aria-label', 'class']
                    });
                }
                function scheduleCheck() {
                    if (pendingCheck !== null) return;
                    pendingCheck = setTimeout(checkMediaState, 50);
                }
                function checkMediaState() {
                    pendingCheck = null;
                    refreshStreamingControl();
                    let hasPlayingAudio = false;
                    let hasPlayingVideo = false;
                    let hasVideoContent = false;
                    for (const element of media) {
                        if (!element.isConnected) { media.delete(element); continue; }
                        const isVideo = element.tagName === 'VIDEO';
                        hasVideoContent ||= isVideo;
                        const playing = !element.paused && !element.ended && element.readyState >= 2;
                        hasPlayingVideo ||= isVideo && playing;
                        hasPlayingAudio ||= playing && !element.muted && element.volume > 0;
                    }
                    // Some streaming services use Web Audio instead of a DOM media element.
                    if (streamingControl) {
                        const label = streamingControl.getAttribute('aria-label') || '';
                        hasPlayingAudio ||= label.toLowerCase().includes('pause') ||
                            streamingControl.classList.contains('playing') ||
                            !!streamingControl.querySelector('button[aria-label*="pause"], button[aria-label*="Pause"]');
                    }
                    const state = {hasAudioContent: hasPlayingAudio, hasPlayingAudio,
                        hasVideoContent, hasPlayingVideo};
                    const serialized = JSON.stringify(state);
                    if (serialized !== lastState) {
                        lastState = serialized;
                        window.webkit?.messageHandlers?.[handlerName]?.postMessage(state);
                    }
                }
                // Media events do not bubble, so observe in the capture phase. This also
                // tracks media created after injection without per-element listeners.
                ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata',
                 'loadeddata', 'canplay', 'volumechange', 'encrypted', 'webkitneedkey'].forEach(type => {
                    document.addEventListener(type, event => {
                        if (event.target.matches?.('audio, video')) media.add(event.target);
                        scheduleCheck();
                    }, true);
                });
                const observer = new MutationObserver(mutations => {
                    let changed = false;
                    for (const mutation of mutations) {
                        for (const node of mutation.addedNodes) {
                            if (node.nodeType !== 1) continue;
                            if (node.matches('audio, video')) { media.add(node); changed = true; }
                            node.querySelectorAll('audio, video').forEach(element => {
                                media.add(element); changed = true;
                            });
                        }
                        if (mutation.removedNodes.length && media.size) {
                            for (const element of media) {
                                if (!element.isConnected) { media.delete(element); changed = true; }
                            }
                        }
                    }
                    if (streamingSelector && !streamingControl?.isConnected) changed = true;
                    if (changed) scheduleCheck();
                });
                observer.observe(document.documentElement, {childList: true, subtree: true});
                document.addEventListener('visibilitychange', scheduleCheck);
                window.addEventListener('pageshow', scheduleCheck);
                checkMediaState();
            })();
            """

        webView.evaluateJavaScript(mediaDetectionScript) { result, error in
            if let error = error {
            } else {
            }
        }
    }

    // MARK: - JavaScript Injection
    func injectLinkHoverJavaScript(to webView: WKWebView) {
        let linkHoverScript = """
            (function() {
                if (window.__nookLinkHoverInstalled) return;
                window.__nookLinkHoverInstalled = true;
                let currentHoveredLink = null;
                let isCommandPressed = false;
                let lastCommandLink = null;

                function reportHover(href, commandPressed) {
                    const commandLink = commandPressed ? href : null;
                    if (href !== currentHoveredLink) {
                        currentHoveredLink = href;
                        window.webkit?.messageHandlers?.linkHover?.postMessage(href);
                    }
                    if (commandLink !== lastCommandLink) {
                        lastCommandLink = commandLink;
                        window.webkit?.messageHandlers?.commandHover?.postMessage(commandLink);
                    }
                    isCommandPressed = commandPressed;
                }
                function linkAt(target) {
                    return target?.closest?.('a[href]')?.href || null;
                }
                // Capture delegation handles dynamic links without scanning the DOM.
                document.addEventListener('mouseover', e => {
                    const link = e.composedPath().find(node => node.matches?.('a[href]'));
                    reportHover(link?.href || null, e.metaKey);
                }, {capture: true, passive: true});
                document.addEventListener('mouseout', e => {
                    reportHover(linkAt(e.relatedTarget), e.metaKey);
                }, {capture: true, passive: true});
                document.addEventListener('keydown', e => reportHover(currentHoveredLink, e.metaKey));
                document.addEventListener('keyup', e => reportHover(currentHoveredLink, e.metaKey));
                window.addEventListener('blur', () => reportHover(null, false));
            })();
            """

        webView.evaluateJavaScript(linkHoverScript) { result, error in
            if let error = error {
            }
        }
    }

    func injectHistoryStateObserver(into webView: WKWebView) {
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
            }
        }
    }

    func injectPiPStateListener(to webView: WKWebView) {
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
            } else {
            }
        }
    }
    
    func injectShortcutDetection(to webView: WKWebView) {
        controller?.sessionDelegate?.configureShortcutDetection(in: webView)
    }

    // MARK: - Chrome Web Store Integration

    /// Inject the Web Store "Add to Nook" script after navigation completes on a store page.
    /// Script and message handler both live in an isolated content world, so page scripts
    /// on any site (including the store itself) cannot call the install handler.
    func injectWebStoreScriptIfNeeded(for url: URL, in webView: WKWebView) {
        webStoreHandler = controller?.sessionDelegate?.installWebStoreScript(in: webView)
    }
}

// MARK: - WKScriptMessageHandler
extension PageSession: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        // WKScriptMessageHandler callbacks run on main thread; no dispatch needed

        // These handlers live in the page world, so any frame can post to them. Every script
        // that feeds them runs in the main frame only; media state is the exception, since a
        // player can sit in a subframe.
        guard message.frameInfo.isMainFrame || message.name.hasPrefix("mediaStateChange_") else { return }

        switch message.name {
        case "linkHover":
            let href = message.body as? String
            self.onLinkHover?(href)

        case "commandHover":
            let href = message.body as? String
            self.onCommandHover?(href)

        case "pipStateChange":
            if let dict = message.body as? [String: Any], let active = dict["active"] as? Bool {
                self.hasPiPActive = active
            }

        case let name where name.hasPrefix("mediaStateChange_"):
            if let dict = message.body as? [String: Bool] {
                // Only set @Published properties when values actually change.
                // @Published fires objectWillChange on every set (even same value),
                // which causes cascading SwiftUI re-renders and video black flashes.
                let newPlayingVideo = dict["hasPlayingVideo"] ?? false
                let newVideoContent = dict["hasVideoContent"] ?? false
                let newAudioContent = dict["hasAudioContent"] ?? false
                let newPlayingAudio = dict["hasPlayingAudio"] ?? false

                if self.hasPlayingVideo != newPlayingVideo { self.hasPlayingVideo = newPlayingVideo }
                if self.hasVideoContent != newVideoContent { self.hasVideoContent = newVideoContent }
                if self.hasAudioContent != newAudioContent { self.hasAudioContent = newAudioContent }
                if self.hasPlayingAudio != newPlayingAudio { self.hasPlayingAudio = newPlayingAudio }
            }

        case let name where name.hasPrefix("backgroundColor_"):
            if let dict = message.body as? [String: String],
                let colorHex = dict["backgroundColor"]
            {
                self.pageBackgroundColor = PlatformColor.fromHex(colorHex)
                if let webView = self.primaryWebView, let color = PlatformColor.fromHex(colorHex) {
                    webView.underPageBackgroundColor = color
                    // Update sampled domain after successful extraction
                    if let currentURL = webView.url,
                       let currentDomain = self.extractDomain(from: currentURL) {
                        self.lastSampledDomain = currentDomain
                    }
                }
            }

        case "historyStateDidChange":
            // The message is only a signal. The address comes from WebKit, never from the body:
            // a page could otherwise put any URL, lock icon included, in the URL bar. WebKit
            // has already updated webView.url for a same-document navigation by the time
            // the message arrives.
            if let url = message.webView?.url {
                if self.url.absoluteString != url.absoluteString {
                    self.url = url
                    // NOTE: Do NOT call syncTabAcrossWindows here. SPA navigations
                    // (pushState/replaceState/popstate) happen inside the webview — the
                    // content is already at the correct state. Calling syncTab would
                    // webView.load() every view of this item whose URL differs, a full
                    // page reload that breaks SPA
                    // back/forward (e.g., Facebook lightbox close via browser back).

                    // Fetch updated title after SPA navigation
                    message.webView?.evaluateJavaScript("document.title") { [weak self] result, _ in
                        // evaluateJavaScript completion runs on main thread
                        if let title = result as? String, !title.isEmpty {
                            self?.updateTitle(title)
                        }
                    }

                    // Fetch favicon for new URL
                    Task { @MainActor [weak self] in
                        await self?.fetchAndSetFavicon(for: url)
                    }

                    // The store coalesces writes, so SPA URL changes report directly.
                    controller?.pageCommitted(itemID: itemID, url: url)
                    controller?.tabEvents?.tabPropertiesChanged(self, properties: [.URL])
                }
            }

        case "nookShortcutDetect":
            handleShortcutDetection(message: message)

        case "nookSponsorBlock":
            // Only a YouTube page has a reason to ask for segments or report a skip.
            if let sponsorBlock = controller?.sponsorBlock,
               sponsorBlock.isYouTubeDomain(message.frameInfo.securityOrigin.host),
               let body = message.body as? [String: Any],
               let type = body["type"] as? String
            {
                switch type {
                case "video-changed":
                    if let videoID = body["videoID"] as? String,
                       videoID.range(of: "^[A-Za-z0-9_-]{11}\\z", options: .regularExpression) != nil {
                        Task { @MainActor [weak self] in
                            guard let webView = message.webView else { return }
                            let segments = await self?.controller?.sponsorBlock
                                .fetchSegments(for: videoID) ?? []
                            self?.controller?.sponsorBlock
                                .deliverSegments(segments, to: webView)
                        }
                    }
                case "segment-skipped":
                    // Telemetry: report viewed segment to SponsorBlock
                    if let uuid = body["uuid"] as? String,
                       uuid.range(of: "^[0-9a-f]{64,}\\z", options: .regularExpression) != nil {
                        sponsorBlock.reportViewedSegment(uuid: uuid, isPrivate: isPrivate)
                    }
                default:
                    break
                }
            }

        default:
            break
        }
    }
    
    func handleShortcutDetection(message: WKScriptMessage) {
        // Handle detected shortcuts from JS injection
        guard let shortcutsString = message.body as? String else { return }
        
        // Use the frame's webView URL for correct attribution, fallback to primaryWebView
        let currentURL = message.frameInfo.webView?.url?.absoluteString ?? primaryWebView?.url?.absoluteString
        guard let url = currentURL else { return }
        
        // Parse the comma-separated shortcuts
        let shortcuts = Set(shortcutsString.split(separator: ",").map { String($0) })
        
        // Update the detector with detected shortcuts for this URL
        controller?.sessionDelegate?.updateDetectedShortcuts(for: url, shortcuts: shortcuts)
    }
}
