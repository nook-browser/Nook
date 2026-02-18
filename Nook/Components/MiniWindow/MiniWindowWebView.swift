//
//  MiniWindowWebView.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import WebKit

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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        context.coordinator.installProgressObservation(on: webView)
        context.coordinator.installThemeColorExtraction(on: webView)
        context.coordinator.installAuthDetectionScript(on: webView)
        context.coordinator.loadInitialURLIfNeeded(on: webView)

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
        private var progressObservation: NSKeyValueObservation?
        private var didLoadInitialURL = false

        init(session: MiniWindowSession) {
            self.session = session
        }

        func installProgressObservation(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let progress = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.session.updateProgress(progress)
                }
            }
        }

        private func extractThemeColor(from webView: WKWebView) {
            webView.evaluateJavaScript(WKWebView.themeColorExtractionScript) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    print("🎨 [MiniWindow] Failed to evaluate theme color script: \(error.localizedDescription)")
                }

                var hexString = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if hexString?.isEmpty == true { hexString = nil }

                DispatchQueue.main.async {
                    self.session.updateToolbarColor(hexString: hexString)
                }
            }
        }
        
        private func topRightPixelRect(for webView: WKWebView) -> CGRect? {
            let bounds = webView.bounds
            guard bounds.width >= 1, bounds.height >= 1 else { return nil }
            
            // Sample the top-rightmost pixel
            let sampleX = bounds.maxX - 1
            let sampleY: CGFloat
            if webView.isFlipped {
                // In flipped coordinates, minY is at the top
                sampleY = bounds.minY
            } else {
                // In non-flipped coordinates, maxY is at the top
                sampleY = bounds.maxY - 1
            }
            
            return CGRect(x: sampleX, y: sampleY, width: 1, height: 1)
        }
        
        private func extractToolbarColor(from webView: WKWebView) {
            guard let sampleRect = topRightPixelRect(for: webView) else {
                return
            }
            
            let configuration = WKSnapshotConfiguration()
            configuration.rect = sampleRect
            configuration.afterScreenUpdates = true
            configuration.snapshotWidth = 1
            
            webView.takeSnapshot(with: configuration) { [weak self] image, error in
                guard let self = self else { return }
                
                if let color = image?.singlePixelColor {
                    DispatchQueue.main.async {
                        self.session.updateToolbarColor(fromPixelColor: color)
                    }
                }
            }
        }
        
        func installThemeColorExtraction(on webView: WKWebView) {
            // Use shared theme color extraction script
            let script = WKUserScript(
                source: WKWebView.themeColorExtractionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(script)
        }

        func installAuthDetectionScript(on webView: WKWebView) {
            // Add message handler for authentication completion
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
            print("🔐 [MiniWindow] Loading URL: \(session.currentURL.absoluteString)")
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
                print("🔐 [MiniWindow] OAuth success detected: \(url.absoluteString)")
                session.completeAuth(success: true, finalURL: url)
                return
            }
            
            // Check for error in URL, query, or fragment
            if errorIndicators.contains(where: { 
                urlString.contains($0) || query.contains($0) || fragment.contains($0) 
            }) {
                print("🔐 [MiniWindow] OAuth error detected: \(url.absoluteString)")
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
                print("🔐 [MiniWindow] Possible OAuth redirect detected: \(url.absoluteString)")
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
            
            print("🔐 [MiniWindow] JavaScript auth completion detected: success=\(success), shouldClose=\(shouldClose), url=\(urlString ?? "nil")")
            
            let finalURL = urlString.flatMap { URL(string: $0) }
            session.completeAuth(success: success, finalURL: finalURL)
            
            // If the site expects the window to close, we could close it automatically
            // but for now, let's let the user decide when to close/adopt the window
            if shouldClose {
                print("🔐 [MiniWindow] Site requested window close, but keeping window open for user control")
            }
        }
    }
}

// MARK: - WKNavigationDelegate
@MainActor
extension MiniWindowWebView.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("🔐 [MiniWindow] Navigation started: \(webView.url?.absoluteString ?? "nil")")
        session.updateLoading(isLoading: true)
        session.updateNavigationState(url: webView.url, title: nil)
        session.updateToolbarColor(hexString: nil)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        session.updateLoading(isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🔐 [MiniWindow] Navigation finished: \(webView.url?.absoluteString ?? "nil")")
        session.updateLoading(isLoading: false)
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

        extractThemeColor(from: webView)
        
        // Extract top-right pixel color for toolbar (lightweight - only if URL changed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak webView] in
            guard let self = self, let webView = webView else { return }
            self.extractToolbarColor(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("🔐 [MiniWindow] Navigation failed: \(error.localizedDescription)")
        session.updateLoading(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("🔐 [MiniWindow] Provisional navigation failed: \(error.localizedDescription)")
        session.updateLoading(isLoading: false)
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
    @available(macOS 10.15, *)
    func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [MiniWindowWebView] Entering full-screen for video")
        
        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [MiniWindowWebView] No window found for full-screen")
            completionHandler(false, NSError(domain: "MiniWindowWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }
        
        // Enter full-screen mode
        window.toggleFullScreen(nil)
        
        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
    }
    
    @available(macOS 10.15, *)
    func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [MiniWindowWebView] Exiting full-screen for video")
        
        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [MiniWindowWebView] No window found for exiting full-screen")
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
    @available(macOS 13.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCaptureAuthorization type: WKMediaCaptureType,
        for origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        print("🔐 [MiniWindow] Media capture authorization requested for type: \(type.rawValue) from origin: \(origin)")

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
                    print("📁 [MiniWindowWebView] Open panel sheet completed with response: \(response)")
                    if response == .OK {
                        print("📁 [MiniWindowWebView] User selected files: \(openPanel.urls.map { $0.lastPathComponent })")
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [MiniWindowWebView] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            } else {
                // Fall back to modal presentation
                openPanel.begin { response in
                    print("📁 [MiniWindowWebView] Open panel modal completed with response: \(response)")
                    if response == .OK {
                        print("📁 [MiniWindowWebView] User selected files: \(openPanel.urls.map { $0.lastPathComponent })")
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [MiniWindowWebView] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            }
        }
    }
}

// Note: We intentionally avoid previewing the live WKWebView here to keep Previews
// fast and stable. Use the preview on MiniBrowserWindowView instead.
