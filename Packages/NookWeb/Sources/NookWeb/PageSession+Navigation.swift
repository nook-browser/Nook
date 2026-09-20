// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PageSession+Navigation.swift
//  Nook
//
//  Navigation delegate, downloads and find in page for a PageSession.
//

import OSLog
import SwiftUI
import WebKit
import NookBlocker
import NookTweaks
// MARK: - WKNavigationDelegate
extension PageSession: WKNavigationDelegate {

    // MARK: - Loading Start
    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        loadingState = .didStartProvisionalNavigation
        controller?.tabEvents?.tabPropertiesChanged(self, properties: [.loading])

        if let newURL = webView.url {
            // Only reset for actual URL changes, not just reloads
            if newURL.absoluteString != self.url.absoluteString {
                hasAudioContent = false
                hasPlayingAudio = false
                // Note: isAudioMuted is preserved to maintain user's mute preference
                // Reset sampled domain to force resampling on new page
                if let newDomain = extractDomain(from: newURL),
                   newDomain != lastSampledDomain {
                    lastSampledDomain = nil
                    lastTopBarDomain = nil
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
        loadingState = .didCommit
        controller?.tabEvents?.tabPropertiesChanged(self, properties: [.loading])
        // A new page gets its dialogs back.
        jsDialogCount = 0
        jsDialogsSuppressed = false

        if let newURL = webView.url {
            self.url = newURL
            controller?.pageCommitted(itemID: itemID, url: newURL)
            controller?.sessionDelegate?.navigateAcrossWindows(itemID, to: newURL)
            // Update website shortcut detector with new URL
            controller?.sessionDelegate?.shortcutDetectorDidNavigate(to: newURL)
            // Grant extension access to the committed URL. This is critical for
            // server-side redirects (e.g. appstoreconnect.apple.com → idmsa.apple.com)
            // where decidePolicyFor only granted access to the initial URL, not the
            // redirect target. Without this, content scripts can't inject on the
            // redirected page and chrome.tabs.query() won't return the URL.
            controller?.tabEvents?.grantAccess(to: newURL)
            controller?.tabEvents?.tabPropertiesChanged(self, properties: [.URL])
        }
    }

    // MARK: - Loading Success
    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        loadingState = .didFinish
        controller?.tabEvents?.tabPropertiesChanged(self, properties: [.loading])

        if let newURL = webView.url {
            self.url = newURL
            // Grant extension access to the final URL after all redirects.
            // decidePolicyFor only grants access to the initial navigation URL;
            // server-side redirects land here with a different URL that needs
            // its own grant for content scripts and chrome.tabs.query().
            controller?.tabEvents?.grantAccess(to: newURL)
            controller?.tabEvents?.tabPropertiesChanged(self, properties: [.URL])

            // Wake MV3 background workers so they can process the new page
            // (autofill detection, badge count updates, etc.)
            controller?.tabEvents?.wakeBackgroundWorkers()

            // Extension diagnostics: check content scripts, background worker, and messaging
            #if DEBUG
            controller?.tabEvents?.diagnose(for: webView, url: newURL)
            #endif
            // The final URL after redirects.
            controller?.pageCommitted(itemID: itemID, url: newURL)
            controller?.sessionDelegate?.navigateAcrossWindows(itemID, to: newURL)

            // Load saved zoom level for the new domain
            controller?.sessionDelegate?.loadZoom(for: self.itemID)

            // CHROME WEB STORE INTEGRATION: Inject script after navigation
            injectWebStoreScriptIfNeeded(for: newURL, in: webView)

        }

        // CRITICAL: Update navigation state after back/forward navigation
        updateNavigationStateEnhanced(source: "didFinish")

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            // evaluateJavaScript completion runs on main thread; no dispatch needed
            if let title = result as? String {
                self?.updateTitle(title)

                // Add to profile-aware history after title is updated
                if let currentURL = webView.url {
                    let profile = self?.profile
                    let profileId = profile?.id ?? self?.controller?.sessionDelegate?.currentProfile?.id
                    let isEphemeral = profile?.isEphemeral ?? false
                    self?.controller?.history?.addVisit(
                        url: currentURL,
                        title: title,
                        timestamp: Date(),
                        tabId: self?.id,
                        profileId: profileId,
                        isEphemeral: isEphemeral
                    )
                }
            }
        }

        // Fetch favicon after page loads
        if let currentURL = webView.url {
            Task { @MainActor in
                await self.fetchAndSetFavicon(for: currentURL)
            }
        }

        injectPageObservers(into: webView)
        updateNavigationStateEnhanced(source: "didCommit")

        // Trigger background color extraction after page fully loads
        // Wait a bit for rendering to complete
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
        loadingState = .didFail(error)

        // Set error favicon on navigation failure
        Task { @MainActor in
            self.favicon = Image(systemName: "exclamationmark.triangle")
        }

        updateNavigationStateEnhanced(source: "didFail")
    }

    // MARK: - Web Process Crash Recovery
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        // Reset crash counter if last crash was more than 30 seconds ago (new crash burst)
        if now.timeIntervalSince(lastWebProcessCrashDate) > 30 {
            webProcessCrashCount = 0
        }
        webProcessCrashCount += 1
        lastWebProcessCrashDate = now

        Self.log.error("WebContent process terminated for item \(self.itemID.uuidString, privacy: .public) (crash #\(self.webProcessCrashCount) in window)")
        loadingState = .idle

        // No window shows this tab: unload instead of respawning a process in the background
        // (often the system reclaiming memory). Selecting the tab restores its saved URL.
        if controller?.webViews != nil, webView === primaryWebView {
            var views = controller?.webViews?.allWebViews(for: itemID) ?? []
            views.append(webView)
            if views.allSatisfy({ $0.window == nil }) {
                controller?.unload(itemID)
                return
            }
        }

        // Hard stop after 4 crashes in a 30-second window — the system is in a bad state
        // (e.g., XPC services unavailable after sleep/wake) and retrying is making it worse.
        // Leave the view without a process; Reload (or unloading the tab) tries again.
        // Loading about:blank here would overwrite and persist the tab's real URL.
        guard webProcessCrashCount <= 4 else {
            Self.log.error("Giving up on item \(self.itemID.uuidString, privacy: .public) after \(self.webProcessCrashCount) consecutive crashes")
            return
        }

        // Delay reload with exponential backoff. Immediately reloading spawns a new web process
        // into the same broken XPC state, causing a tight crash loop. The delay gives launchservicesd
        // and other XPC services time to finish restarting after a system wake.
        let delay = Double(webProcessCrashCount) * 2.0 // 2s, 4s, 6s, 8s
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
            // Skip views released or unloaded while waiting.
            guard let self, let webView, (webView.navigationDelegate as AnyObject?) === self else { return }
            // reload() does nothing when the crash happened before any page committed.
            if webView.backForwardList.currentItem == nil || webView.reload() == nil {
                PageSession.loadPage(self.url, in: webView)
            }
        }
    }

    // MARK: - Loading Failed (before content started loading)
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingState = .didFailProvisionalNavigation(error)

        // didStartProvisionalNavigation moved `url` to the attempted URL. A navigation that
        // never commits (download response, Stop, network error) must not become the URL
        // that is persisted and restored; the view still shows the committed page. When a
        // newer navigation superseded this one, isLoading is still true and that one owns `url`.
        if !webView.isLoading, let committed = webView.url, committed != url {
            url = committed
            controller?.tabEvents?.tabPropertiesChanged(self, properties: [.URL])
            controller?.pageCommitted(itemID: itemID, url: committed)
        }

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
        if controller?.sessionDelegate?.handleAuthenticationChallenge(
            challenge,
            for: self,
            completionHandler: completionHandler
        ) == true {
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
            // $removeparam: restart the navigation without tracking parameters
            if navigationAction.navigationType != .backForward,
               (navigationAction.request.httpMethod ?? "GET") == "GET",
               let stripped = controller?.blocker.strippedTrackingParams(for: url, tab: self)
            {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: stripped))
                return
            }

            // Grant extension access to this URL BEFORE navigation starts
            // so content scripts can inject at document_start
            controller?.tabEvents?.grantAccess(to: url)

            // Setup content blocker scripts before navigation starts
            controller?.blocker.setupContentBlockerScripts(for: url, in: webView, tab: self)

            // Inject SponsorBlock script (independent of content blocker)
            controller?.sponsorBlock.injectScriptIfNeeded(for: url, in: webView)
            if let settings = controller?.settings {
                YouTubeTweaks.apply(for: url, in: webView, settings: settings)
                SocialImageTweaks.apply(for: url, in: webView, settings: settings)
                FacebookTweaks.apply(for: url, in: webView, settings: settings)
            }
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
                self.controller?.sessionDelegate?.presentPeek(url: url, from: self)
            }
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        // Air Traffic Control — route cross-domain navigations to designated spaces.
        // Main frame only: an embedded iframe must not open tabs in another space.
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url {
            var currentHost = self.url.host?.lowercased() ?? ""
            if currentHost.hasPrefix("www.") { currentHost = String(currentHost.dropFirst(4)) }
            var destHost = url.host?.lowercased() ?? ""
            if destHost.hasPrefix("www.") { destHost = String(destHost.dropFirst(4)) }
            if !currentHost.isEmpty && !destHost.isEmpty && currentHost != destHost,
               controller?.siteRouting.applyRoute(url: url, from: self) == true {
                decisionHandler(.cancel)
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


        controller?.sessionDelegate?.addDownload(
            download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationResponse.response.url ?? URL(string: "https://example.com")!
        let suggestedFilename = navigationResponse.response.url?.lastPathComponent ?? "download"


        controller?.sessionDelegate?.addDownload(
            download, originalURL: originalURL, suggestedFilename: suggestedFilename)
    }
}

// MARK: - Find in Page
extension PageSession {
    public typealias FindResult = Result<(matchCount: Int, currentIndex: Int), Error>
    public typealias FindCompletion = @Sendable (FindResult) -> Void

    public func findInPage(_ text: String, completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let activeWindowId = controller?.windowRegistry.activeWindow?.id,
            let found = controller?.webViews?.webView(for: self.itemID, in: activeWindowId)
        {
            targetWebView = found
        } else {
            targetWebView = primaryWebView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "PageSession", code: -1,
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

        // Use JavaScript to search and highlight text. The query arrives as the
        // `searchText` argument, never as part of the script source.
        let script = """
            return (function() {
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

                var matchCount = 0;

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

                // Search and highlight. DOM calls only: page text must never be
                // parsed as HTML.
                var escaped = searchText.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                textNodes.forEach(function(textNode) {
                    var regex = new RegExp(escaped, 'gi');
                    var ranges = [];
                    var m;
                    while ((m = regex.exec(textNode.data)) !== null) {
                        ranges.push([m.index, m[0].length]);
                    }
                    matchCount += ranges.length;

                    // Split from the end so earlier offsets stay valid
                    for (var i = ranges.length - 1; i >= 0; i--) {
                        var match = textNode.splitText(ranges[i][0]);
                        match.splitText(ranges[i][1]);
                        var span = document.createElement('span');
                        span.className = 'nook-find-highlight';
                        span.style.backgroundColor = 'yellow';
                        span.style.color = 'black';
                        match.parentNode.replaceChild(span, match);
                        span.appendChild(match);
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

        webView.callAsyncJavaScript(script, arguments: ["searchText": text], in: nil, in: .page) { result in
            let value: Any
            switch result {
            case .success(let v): value = v
            case .failure(let error):
                completion(.failure(error))
                return
            }

            if let dict = value as? [String: Any],
                let matchCount = dict["matchCount"] as? Int,
                let currentIndex = dict["currentIndex"] as? Int
            {
                completion(.success((matchCount: matchCount, currentIndex: currentIndex)))
            } else {
                completion(.success((matchCount: 0, currentIndex: 0)))
            }
        }
    }

    public func findNextInPage(completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let activeWindowId = controller?.windowRegistry.activeWindow?.id,
            let found = controller?.webViews?.webView(for: self.itemID, in: activeWindowId)
        {
            targetWebView = found
        } else {
            targetWebView = primaryWebView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "PageSession", code: -1,
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

    public func findPreviousInPage(completion: @escaping FindCompletion) {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let activeWindowId = controller?.windowRegistry.activeWindow?.id,
            let found = controller?.webViews?.webView(for: self.itemID, in: activeWindowId)
        {
            targetWebView = found
        } else {
            targetWebView = primaryWebView
        }

        guard let webView = targetWebView else {
            completion(
                .failure(
                    NSError(
                        domain: "PageSession", code: -1,
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

    public func clearFindInPage() {
        // Use the WebView that's actually visible in the current window
        let targetWebView: WKWebView?
        if let activeWindowId = controller?.windowRegistry.activeWindow?.id,
            let found = controller?.webViews?.webView(for: self.itemID, in: activeWindowId)
        {
            targetWebView = found
        } else {
            targetWebView = primaryWebView
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
