//
//  MiniWindowWebView.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import WebKit

/// Keeps the page's fixed content clear of the window's glass toolbar while the
/// page itself scrolls underneath it. Synced in `layout()` so it survives resize,
/// full screen and toolbar changes without an observer.
final class TitlebarInsetWebView: WKWebView {
    override func layout() {
        super.layout()
        // After adopt this view lives in a browser window, which has no toolbar to clear.
        guard let window = window as? MiniBrowserWindow, bounds.height > 0 else {
            if obscuredContentInsets.top != 0 { obscuredContentInsets = NSEdgeInsetsZero }
            return
        }
        // How far this view reaches up under the titlebar and toolbar. WebKit throws on
        // negative insets or insets taller than the view, both possible mid-layout.
        let overlap = convert(bounds, to: nil).maxY - window.contentLayoutRect.maxY
        let inset = min(max(0, overlap), bounds.height - 1)
        if obscuredContentInsets.top != inset {
            obscuredContentInsets = NSEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)
        }
    }
}

struct MiniWindowWebView: NSViewRepresentable {
    @ObservedObject var session: MiniWindowSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration: WKWebViewConfiguration
        if let profile = session.profile {
            configuration = BrowserConfiguration.shared.webViewConfiguration(for: profile)
        } else {
            configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration()
        }

        let webView = TitlebarInsetWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        context.coordinator.installAuthDetectionScript(on: webView)
        context.coordinator.loadInitialURLIfNeeded(on: webView)
        session.webView = webView

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.loadInitialURLIfNeeded(on: nsView)
    }

    // MARK: - Coordinator
    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var session: MiniWindowSession
        private var didLoadInitialURL = false

        /// Weak reference to the webView so we can clean up message handlers in deinit
        private weak var installedWebView: WKWebView?

        init(session: MiniWindowSession) {
            self.session = session
        }

        deinit {
            // MEMORY LEAK FIX: Remove the script message handler that holds a strong
            // reference to this Coordinator. Without this, the WKUserContentController
            // retains the Coordinator forever.
            let webView = installedWebView
            Task { @MainActor in
                webView?.configuration.userContentController
                    .removeScriptMessageHandler(forName: "authCompletion")
            }
        }

        func installAuthDetectionScript(on webView: WKWebView) {
            // Add message handler for authentication completion
            installedWebView = webView
            webView.configuration.userContentController.add(self, name: "authCompletion")
            
            // Inject a simpler, less intrusive JavaScript to detect authentication completion
            let authDetectionScript = """
                (function() {
                    // Simple function to check for auth completion
                    function checkAuthCompletion() {
                        try {
                            const url = window.location.href;
                            const search = window.location.search;
                            const hash = window.location.hash;
                            
                            // Check for common OAuth success patterns
                            if (search.match(/(code=|access_token=|id_token=|oauth_token=|oauth_verifier=|session_state=|samlresponse=|relaystate=|ticket=|assertion=|authuser=)/i) ||
                                hash.match(/(access_token=|id_token=|oauth_token=|session_state=)/i)) {
                                
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.authCompletion) {
                                    window.webkit.messageHandlers.authCompletion.postMessage({
                                        success: true,
                                        url: url
                                    });
                                }
                                return;
                            }
                            
                            // Check for common OAuth error patterns
                            if (search.match(/(error=|denied|cancelled|abort|failed|unauthorized|access_denied|invalid_request|unsupported_response_type|invalid_scope|server_error|temporarily_unavailable)/i) ||
                                hash.match(/(error=|denied|cancelled|abort)/i)) {
                                
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.authCompletion) {
                                    window.webkit.messageHandlers.authCompletion.postMessage({
                                        success: false,
                                        url: url
                                    });
                                }
                                return;
                            }
                        } catch (e) {
                            // Silently ignore errors to avoid interfering with the page
                            console.log('Auth detection error:', e);
                        }
                    }
                    
                    // Run check when page loads
                    if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', checkAuthCompletion);
                    } else {
                        checkAuthCompletion();
                    }
                    
                    // Also check on hash changes (common in OAuth flows)
                    window.addEventListener('hashchange', checkAuthCompletion);
                    
                })();
            """
            
            let script = WKUserScript(source: authDetectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(script)
        }

        func loadInitialURLIfNeeded(on webView: WKWebView) {
            guard didLoadInitialURL == false else { return }
            didLoadInitialURL = true
            let request = URLRequest(url: session.currentURL)
            webView.load(request)
        }
        
        func checkForOAuthCompletion(url: URL) {
            // Skip if already completed
            guard !session.isAuthComplete else { return }
            
            // Check if this URL indicates OAuth completion
            let urlString = url.absoluteString.lowercased()
            let query = url.query?.lowercased() ?? ""
            let fragment = url.fragment?.lowercased() ?? ""
            
            // Common OAuth success indicators
            let successIndicators = [
                "code=", "access_token=", "id_token=", "oauth_token=", "oauth_verifier=",
                "session_state=", "samlresponse=", "relaystate=", "ticket=", "assertion=",
                "authuser="
            ]
            
            // Common OAuth error indicators
            let errorIndicators = [
                "error=", "denied", "cancelled", "abort", "failed", "unauthorized",
                "access_denied", "invalid_request", "unsupported_response_type",
                "invalid_scope", "server_error", "temporarily_unavailable"
            ]
            
            // Check for success in URL, query, or fragment
            if successIndicators.contains(where: { 
                urlString.contains($0) || query.contains($0) || fragment.contains($0) 
            }) {
                session.completeAuth(success: true, finalURL: url)
                return
            }
            
            // Check for error in URL, query, or fragment
            if errorIndicators.contains(where: { 
                urlString.contains($0) || query.contains($0) || fragment.contains($0) 
            }) {
                session.completeAuth(success: false, finalURL: url)
                return
            }
            
            // Check for redirect back to original domain (common OAuth pattern)
            if let host = url.host?.lowercased(),
               !host.contains("google.com") && !host.contains("microsoft.com") && 
               !host.contains("apple.com") && !host.contains("github.com") &&
               !host.contains("auth0.com") && !host.contains("okta.com") &&
               !host.contains("facebook.com") && !host.contains("twitter.com") &&
               !host.contains("discord.com") {
                // This might be a redirect back to the original app
                session.completeAuth(success: true, finalURL: url)
            }
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "authCompletion",
                  let body = message.body as? [String: Any] else { return }
            
            let success = body["success"] as? Bool ?? false
            let shouldClose = body["shouldClose"] as? Bool ?? false
            let urlString = body["url"] as? String
            
            
            let finalURL = urlString.flatMap { URL(string: $0) }
            session.completeAuth(success: success, finalURL: finalURL)
            
            // If the site expects the window to close, we could close it automatically
            // but for now, let's let the user decide when to close/adopt the window
            if shouldClose {
            }
        }
    }
}

// MARK: - WKNavigationDelegate
@MainActor
extension MiniWindowWebView.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session.updateNavigationState(url: webView.url, title: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session.updateNavigationState(url: webView.url, title: nil)
        
        // Check if this is an OAuth completion URL
        if let url = webView.url {
            checkForOAuthCompletion(url: url)
        }
        
        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self else { return }
            if let title = result as? String {
                DispatchQueue.main.async {
                    self.session.updateNavigationState(url: nil, title: title)
                }
            }
        }
    }
}

// MARK: - WKUIDelegate
@MainActor
extension MiniWindowWebView.Coordinator: WKUIDelegate {
    func webView(
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
    
    // MARK: - Full-Screen Video Support
    func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        
        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(false, NSError(domain: "MiniWindowWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }
        
        // Enter full-screen mode
        window.toggleFullScreen(nil)
        
        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
    }
    
    func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        
        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(false, NSError(domain: "MiniWindowWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for exiting full-screen"]))
            return
        }
        
        // Exit full-screen mode
        window.toggleFullScreen(nil)

        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
    }

    // MARK: - Media Capture Permission

    /// Handle requests for media capture authorization (camera/microphone).
    /// This is used for OAuth providers that may require getUserMedia during auth flows.
    func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {

        let knownOAuthDomains = [
            "accounts.google.com", "login.microsoftonline.com", "github.com",
            "appleid.apple.com", "auth0.com", "okta.com", "auth.cloudflare.com"
        ]
        let isKnownOAuth = knownOAuthDomains.contains { origin.host.contains($0) }
        decisionHandler(isKnownOAuth ? .grant : .deny)
    }

    // MARK: - File Upload Support
    func webView(
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
}

// Note: We intentionally avoid previewing the live WKWebView here to keep Previews
// fast and stable. Use the preview on MiniBrowserWindowView instead.
