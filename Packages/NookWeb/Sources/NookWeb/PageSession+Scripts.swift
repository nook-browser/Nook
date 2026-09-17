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
        ["linkHover", "commandHover", "commandClick", "pipStateChange",
         "mediaStateChange_\(itemID.uuidString)", "backgroundColor_\(itemID.uuidString)",
         "historyStateDidChange", "NookIdentity", "nookShortcutDetect",
         "nookAdBlocker", "nookSponsorBlock"]
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
        switch message.name {
        case "linkHover":
            let href = message.body as? String
            self.onLinkHover?(href)

        case "commandHover":
            let href = message.body as? String
            self.onCommandHover?(href)

        case "commandClick":
            if let href = message.body as? String, let url = URL(string: href) {
                self.handleCommandClick(url: url)
            }

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
            if let href = message.body as? String, let url = URL(string: href) {
                if self.url.absoluteString != url.absoluteString {
                    self.url = url
                    // NOTE: Do NOT call syncTabAcrossWindows here. SPA navigations
                    // (pushState/replaceState/popstate) happen inside the webview — the
                    // content is already at the correct state. Calling syncTab would see a
                    // URL mismatch (webView.url lags behind the JS-driven URL change) and
                    // force webView.load(), causing a full page reload that breaks SPA
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

        case "NookIdentity":
            handleOAuthRequest(message: message)
            
        case "nookShortcutDetect":
            handleShortcutDetection(message: message)

        case "nookAdBlocker":
            // Native ad skip — evaluateJavaScript from the app process is invisible
            // to YouTube's anti-adblock detection (no extension can do this)
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String,
               type == "ad-playing"
            {
                message.webView?.evaluateJavaScript("""
                    (function() {
                        var v = document.querySelector('#movie_player video');
                        if (v && isFinite(v.duration) && v.duration > 0) {
                            v.currentTime = v.duration;
                        }
                        var skip = document.querySelector(
                            '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, ' +
                            '.ytp-ad-skip-button-container button, button[id^="skip-button"], ' +
                            '.ytp-ad-overlay-close-button'
                        );
                        if (skip) skip.click();
                        var overlay = document.querySelector('.ytp-ad-overlay-container, .ytp-ad-image-overlay');
                        if (overlay) overlay.style.setProperty('display', 'none', 'important');
                    })()
                    """)
            }

        case "nookSponsorBlock":
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String
            {
                switch type {
                case "video-changed":
                    if let videoID = body["videoID"] as? String {
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
                    if let uuid = body["uuid"] as? String {
                        controller?.sponsorBlock.reportViewedSegment(uuid: uuid)
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

    /// Command-click opens the link in a background tab of the window showing this page. A
    /// private page's links stay in its private window.
    func handleCommandClick(url: URL) {
        guard let controller, let window = controller.window(for: self) else { return }
        controller.open(url: url, in: window, placement: .background)
    }

    func handleOAuthRequest(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
            let urlString = dict["url"] as? String,
            let url = URL(string: urlString)
        else {
            return
        }
        let interactive = dict["interactive"] as? Bool ?? true
        let prefersEphemeral = dict["prefersEphemeral"] as? Bool ?? false
        let providedScheme = (dict["callbackScheme"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let rawRequestId = (dict["requestId"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let requestId = (rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString)


        guard let delegate = controller?.sessionDelegate else {
            finishIdentityFlow(requestId: requestId, with: .failure(.unableToStart))
            return
        }

        let identityRequest = IdentityRequest(
            requestId: requestId,
            url: url,
            interactive: interactive,
            prefersEphemeralSession: prefersEphemeral,
            explicitCallbackScheme: providedScheme?.isEmpty == true ? nil : providedScheme
        )

        delegate.beginIdentityFlow(identityRequest, from: self)
    }

    public func finishIdentityFlow(
        requestId: String,
        with result: IdentityFlowResult
    ) {
        guard let webView else {
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

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return
        }

        let script =
            "window.__nookCompleteIdentityFlow && window.__nookCompleteIdentityFlow(\(jsonString));"
        webView.evaluateJavaScript(script) { _, error in
            if let error {
            }
        }
    }
}
