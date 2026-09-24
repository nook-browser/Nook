// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+UIDelegate.swift
//  Nook
//
//  Popups, OAuth windows, JavaScript panels, file upload and full screen for a PageSession.
//

import SwiftUI
import WebKit
import NookBlocker
import NookSettings
import NookTweaks
extension PageSession {
    func isLikelyOAuthOrExternalWindow(url: URL, windowFeatures: WKWindowFeatures) -> Bool {
        if OAuthDetector.isLikelyOAuthPopupURL(url) { return true }

        // If the popup has explicit dimensions AND is cross-origin, it's likely a sign-in window.
        // Same-origin popups with dimensions (e.g. log viewers, help windows) should open normally.
        if let width = windowFeatures.width, let height = windowFeatures.height,
            width.doubleValue > 0 && height.doubleValue > 0
        {
            let currentHost = self.url.host?.lowercased()
            let popupHost = url.host?.lowercased()
            if currentHost != popupHost {
                return true
            }
        }

        return false
    }

    // MARK: - Peek Detection

    /// Option always peeks. Otherwise only a favorite or pinned tab peeks, for a link to another
    /// site, so the page it keeps in the sidebar stays put; a regular tab opens a new tab.
    func shouldRedirectToPeek(url: URL) -> Bool {
        if isOptionKeyDown { return true }
        guard controller?.isSynced(itemID) == true, let from = self.url.host, let to = url.host else { return false }
        return !Self.isSameSite(from, to)
    }

    // No public suffix list: hosts match when one equals or contains the other, so a page on a
    // bare shared suffix (github.io) would match its subdomains, and sibling subdomains
    // (mail.google.com, docs.google.com) count as different sites. Use a PSL if that proves wrong.
    public static func isSameSite(_ lhs: String?, _ rhs: String?) -> Bool {
        func bare(_ host: String?) -> String {
            let host = host?.lowercased() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let a = bare(lhs), b = bare(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

}

// MARK: - WKUIDelegate
extension PageSession: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let delegate = controller?.sessionDelegate else { return nil }
        let url = navigationAction.request.url
        // Extensions manage their own auth flows, and never get Peek.
        let sourceScheme = navigationAction.sourceFrame.request.url?.scheme?.lowercased() ?? ""
        let isFromExtension = sourceScheme == "webkit-extension" || sourceScheme == "safari-web-extension"

        // WebKit's configuration shares the opener's userContentController. Handlers are keyed
        // by name, so registering the popup's on it would reroute the opener's messages to the
        // popup, and closing the popup would strip them from the opener. Give the popup its own
        // controller; WebKit only requires the configuration's related web view to match.
        func popupConfiguration() -> WKWebViewConfiguration {
            configuration.userContentController = BrowserConfiguration.shared.freshUserContentController()
            return configuration
        }

        // A sign-in popup shows in a mini window as a real popup, so `window.opener` carries the
        // result back to this page the way the site expects.
        if !isFromExtension, let url, isLikelyOAuthOrExternalWindow(url: url, windowFeatures: windowFeatures) {
            guard let popup = controller?.openDetachedPopup(configuration: popupConfiguration(), url: url, opener: self)
            else { return nil }
            delegate.presentPopupWindow(popup)
            return popup.webView
        }

        // Air Traffic Control: route popup URLs to designated spaces.
        if let url, controller?.siteRouting.applyRoute(url: url, from: self) == true {
            return nil
        }

        // Peek and mini window pages follow the link in place rather than open a tab behind them.
        if isDetached {
            if url != nil { webView.load(navigationAction.request) }
            return nil
        }

        if !isFromExtension, let url, shouldRedirectToPeek(url: url) {
            // Trigger Peek after returning control to WebKit to avoid runloop-mode issues
            RunLoop.current.perform { [weak self] in
                guard let self else { return }
                self.controller?.sessionDelegate?.presentPeek(url: url, from: self)
            }
            return nil
        }

        guard let newWebView = controller?.webViews?.makeWebView(configuration: popupConfiguration()) else { return nil }

        // A session owns the popup's view; a private page's popup stays in its private window.
        guard let controller,
              controller.adoptPopup(
                webView: newWebView,
                url: navigationAction.request.url,
                opener: self) != nil
        else { return nil }

        return newWebView
    }

    // MARK: - OAuth Helpers

    /// Checks if a URL indicates OAuth completion and handles the flow
    func checkOAuthCompletion(url: URL) {
        guard isOAuthFlow, let parentItemID = oauthParentItemID else { return }
        
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
           (isSuccess || isError || !OAuthDetector.isLikelyOAuthURL(url)) {
            
            
            // Reselect and reload the opener, then close this sign-in page.
            DispatchQueue.main.async { [weak self] in
                guard let self, let controller = self.controller,
                      let parent = controller.session(for: parentItemID) else { return }
                if let window = controller.window(for: parent) {
                    controller.select(parentItemID, in: window)
                }
                parent.activeWebView.reload()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.controller?.close(self.itemID)
            }
        }
    }

    /// Counts a dialog. From the second one since the last main-frame commit the presenter offers
    /// to stop them, so `while(1) alert()` cannot hold the window.
    private func nextDialogSuppressor() -> (() -> Void)? {
        jsDialogCount += 1
        guard jsDialogCount > 1 else { return nil }
        return { [weak self] in self?.jsDialogsSuppressed = true }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard !jsDialogsSuppressed, let alerts = controller?.alerts else { return completionHandler() }
        alerts.presentAlert(
            message: message, host: frame.securityOrigin.host, over: webView,
            onSuppress: nextDialogSuppressor(), completion: completionHandler)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard !jsDialogsSuppressed, let alerts = controller?.alerts else { return completionHandler(false) }
        alerts.presentConfirm(
            message: message, host: frame.securityOrigin.host, over: webView,
            onSuppress: nextDialogSuppressor(), completion: completionHandler)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard !jsDialogsSuppressed, let alerts = controller?.alerts else { return completionHandler(nil) }
        alerts.presentPrompt(
            prompt: prompt, defaultText: defaultText, host: frame.securityOrigin.host, over: webView,
            onSuppress: nextDialogSuppressor(), completion: completionHandler)
    }

    /// A popup that finished (a sign-in window) closes itself; only detached pages act on it.
    public func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }

    // MARK: - File Upload Support
    public func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {

        guard let alerts = controller?.alerts else { return completionHandler(nil) }
        alerts.presentOpenPanel(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories,
            over: webView,
            completion: completionHandler)
    }

    // MARK: - Full-Screen Video Support
    public func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {

        guard controller?.sessionDelegate?.toggleFullScreen(for: webView) == true else {
            completionHandler(
                false,
                NSError(
                    domain: "PageSession", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }
        // Call completion handler immediately - WebKit will handle the actual full-screen transition
        completionHandler(true, nil)
    }

    public func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {

        guard controller?.sessionDelegate?.toggleFullScreen(for: webView) == true else {
            completionHandler(
                false,
                NSError(
                    domain: "PageSession", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No window available for exiting full-screen"
                    ]))
            return
        }
        // Call completion handler immediately - WebKit will handle the actual full-screen transition
        completionHandler(true, nil)
    }

    // MARK: - Media Capture Authorization

    /// Handle requests for camera/microphone capture authorization
    public func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {

        // A stored answer for this host short-circuits the prompt; otherwise WebKit asks, and a
        // page never gets capture on its own say-so.
        let needed: [SitePermission]
        switch type {
        case .camera: needed = [.camera]
        case .microphone: needed = [.microphone]
        case .cameraAndMicrophone: needed = [.camera, .microphone]
        @unknown default: needed = [.camera, .microphone]
        }
        guard let settings = controller?.settings else {
            decisionHandler(.prompt)
            return
        }
        let policies = needed.map { settings.permission($0, for: origin.host) }
        // A combined request needs every part allowed, and one block denies the whole thing.
        if policies.contains(.block) {
            decisionHandler(.deny)
        } else if policies.allSatisfy({ $0 == .allow }) {
            decisionHandler(.grant)
        } else {
            decisionHandler(.prompt)
        }
    }
}
