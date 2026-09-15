//
//  PageSession+Bridges.swift
//  Nook
//
//  PageSession overloads of collaborator APIs that still take `Tab`. Each overload keeps the
//  label the owning track keeps when it retypes its method from `Tab` to `PageSession`; that
//  track deletes the matching entry here (the duplicate declaration will not compile). Bodies
//  use only the collaborators' internal API, so some cover less than the `Tab` originals; the
//  gaps are noted per entry. The file is empty and deleted by task Z.
//

import AppKit
import WebKit

// MARK: - ContentBlockerManager (T3)

extension ContentBlockerManager {
    /// Same exemptions as the `Tab` version: disabled, temporarily disabled, allowed domain, OAuth.
    private func isExempt(_ session: PageSession, host: String?) -> Bool {
        !isEnabled || isTemporarilyDisabled(tabId: session.itemID) || isDomainAllowed(host) || session.isOAuthFlow
    }

    func strippedTrackingParams(for url: URL, tab session: PageSession) -> URL? {
        guard !isExempt(session, host: url.host) else { return nil }
        return trackingParamStripper.strip(url)
    }

    /// Resets the blocked count and swaps the main-frame config script. Gap: rule lists are not
    /// removed from an exempt page's view (the exemption table is private to the manager).
    func setupContentBlockerScripts(for url: URL, in webView: WKWebView, tab session: PageSession) {
        guard isEnabled else { return }
        let exempt = isExempt(session, host: url.host)
        session.blockedRequestCount = 0
        let script = exempt ? nil : advancedRulesEngine.configUserScript(for: url)
        let ucc = webView.configuration.userContentController
        let marker = AdvancedRulesEngine.configScriptMarker
        // Evaluate the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let others = all.filter { !$0.source.hasPrefix(marker) }
        guard others.count != all.count || script != nil else { return }
        ucc.removeAllUserScripts()
        if let script { ucc.addUserScript(script) }
        others.forEach { ucc.addUserScript($0) }
    }
}

// MARK: - AuthenticationManager (T3)

extension AuthenticationManager {
    /// Gap: no basic-auth prompt and no private-network certificate override; returns false so
    /// the session falls back to default handling.
    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for session: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        false
    }

    /// Runs the identity flow in the mini window and reports the result to the page.
    func beginIdentityFlow(_ request: IdentityRequest, from session: PageSession) {
        guard request.interactive else {
            session.finishIdentityFlow(requestId: request.requestId, with: .failure(.interactionRequired))
            return
        }
        guard let manager = session.browserManager else {
            session.finishIdentityFlow(requestId: request.requestId, with: .failure(.fallbackUnavailable))
            return
        }
        manager.externalMiniWindowManager.present(url: request.url) { [weak session] success, finalURL in
            Task { @MainActor in
                guard let session else { return }
                guard success, let finalURL else {
                    session.finishIdentityFlow(requestId: request.requestId, with: .failure(.fallbackCancelled))
                    return
                }
                session.finishIdentityFlow(requestId: request.requestId, with: .success(finalURL))
                session.activeWebView.reload()
            }
        }
    }
}

// MARK: - PeekManager (T5)

extension PeekManager {
    func presentExternalURL(_ url: URL, from session: PageSession?) {
        guard browserManager != nil else { return }
        if currentSession?.currentURL == url {
            dismissPeek()
            return
        }
        let peek = PeekSession(
            targetURL: url,
            sourceTabId: session?.itemID,
            sourceURL: session?.url,
            windowId: windowRegistry?.activeWindow?.id ?? UUID(),
            sourceProfileId: session?.profile?.id
        )
        currentSession = peek
        webView = createWebView()
        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates.
        RunLoop.current.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.isActive = true
                NotificationCenter.default.post(name: .peekDidActivate, object: self)
            }
        }
    }
}

// MARK: - SiteRoutingManager (T5)

extension SiteRoutingManager {
    /// Opens `url` in the rule's target space of the window showing `session`.
    func applyRoute(url: URL, from session: PageSession?) -> Bool {
        guard let browserManager, session?.isPrivate != true else { return false }
        let tabs = browserManager.tabs
        guard let window = session.flatMap({ tabs.window(for: $0) }) ?? browserManager.windowRegistry?.activeWindow,
              !window.isIncognito,
              let rule = resolve(url: url),
              tabs.space(rule.targetSpaceId) != nil,
              window.spaceID != rule.targetSpaceId
        else { return false }
        Task { @MainActor in
            tabs.setSpace(rule.targetSpaceId, in: window)
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: rule.targetSpaceId))
        }
        return true
    }
}

// MARK: - PiPManager (T3)

extension PiPManager {
    func requestPiP(for session: PageSession, webView: WKWebView? = nil) {
        guard let webView = webView ?? session.assignedWebView else { return }
        let script = """
        (function() {
            const video = document.querySelector('video');
            if (!video) return { success: false, error: 'No video found' };
            try {
                if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
                    const currentMode = video.webkitPresentationMode || 'inline';
                    const newMode = (currentMode === 'picture-in-picture') ? 'inline' : 'picture-in-picture';
                    video.webkitSetPresentationMode(newMode);
                    return { success: true, mode: newMode };
                }
                if (document.pictureInPictureEnabled && video.requestPictureInPicture) {
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                        return { success: true, mode: 'inline' };
                    }
                    video.requestPictureInPicture().catch(function() {});
                    return { success: true, mode: 'picture-in-picture' };
                }
                return { success: false, error: 'PiP not supported on this page' };
            } catch (error) {
                return { success: false, error: error.message };
            }
        })();
        """
        webView.evaluateJavaScript(script) { [weak session] result, _ in
            guard let session, let dict = result as? [String: Any],
                  dict["success"] as? Bool == true, let mode = dict["mode"] as? String else { return }
            session.hasPiPActive = mode == "picture-in-picture"
        }
    }

    func isPiPActive(for session: PageSession) -> Bool {
        session.hasPiPActive
    }
}

// MARK: - WebViewCoordinator (T3)

extension WebViewCoordinator {
    /// Gap: the pool dictionary is private, so entries are cleaned and detached but stay listed
    /// until the window closes.
    func removeAllWebViews(for session: PageSession) {
        for webView in getAllWebViews(for: session.itemID) {
            session.cleanupClone(webView)
            removeWebViewFromContainers(webView)
        }
    }
}
