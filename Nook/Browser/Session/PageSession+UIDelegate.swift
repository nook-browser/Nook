//
//  PageSession+UIDelegate.swift
//  Nook
//
//  Popups, OAuth windows, JavaScript panels, file upload and full screen for a PageSession.
//

import AppKit
import SwiftUI
import WebKit
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

    func shouldRedirectToPeek(url: URL) -> Bool {
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
extension PageSession: WKUIDelegate {
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
            
            // Reselect and reload the opener once the sign-in window succeeds.
            let parentItemID = itemID
            bm.externalMiniWindowManager.present(url: url) { [weak self] success, _ in
                guard success else { return }
                DispatchQueue.main.async {
                    guard let self, let controller = self.controller,
                          let parent = controller.session(for: parentItemID) else { return }
                    if let window = controller.window(for: parent) {
                        controller.select(parentItemID, in: window)
                    }
                    parent.activeWebView.reload()
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

        // Air Traffic Control — route popup URLs to designated spaces
        if let url = navigationAction.request.url,
           browserManager?.siteRoutingManager.applyRoute(url: url, from: self) == true {
            return nil
        }

        // WebKit's configuration shares the opener's userContentController. Handlers are keyed
        // by name, so registering the popup's on it would reroute the opener's messages to the
        // popup, and closing the popup would strip them from the opener. Give the popup its own
        // controller; WebKit only requires the configuration's related web view to match.
        configuration.userContentController = BrowserConfiguration.shared.freshUserContentController()
        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)

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
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in
                completionHandler()
            }
        } else {
            completionHandler()
        }
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
        if let window = webView.window {
            alert.beginSheetModal(for: window) { result in
                completionHandler(result == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(false)
        }
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

        if let window = webView.window {
            alert.beginSheetModal(for: window) { result in
                completionHandler(result == .alertFirstButtonReturn ? textField.stringValue : nil)
            }
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
                    if response == .OK {
                        completionHandler(openPanel.urls)
                    } else {
                        completionHandler(nil)
                    }
                }
            } else {
                // Fall back to modal presentation
                openPanel.begin { response in
                    if response == .OK {
                        completionHandler(openPanel.urls)
                    } else {
                        completionHandler(nil)
                    }
                }
            }
        }
    }

    // MARK: - Full-Screen Video Support
    public func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {

        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(
                false,
                NSError(
                    domain: "PageSession", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }


        // Enter full-screen mode
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }

        // Call completion handler immediately - WebKit will handle the actual full-screen transition
        completionHandler(true, nil)
    }

    public func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {

        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(
                false,
                NSError(
                    domain: "PageSession", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No window available for exiting full-screen"
                    ]))
            return
        }


        // Exit full-screen mode
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
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

        decisionHandler(.grant)
    }
}
