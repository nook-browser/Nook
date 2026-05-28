import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let urlString: String
    var onTitleChange: ((String) -> Void)? = nil
    var onURLChange: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        // Reuse the shared browser configuration so extensions can inject consistently
        let configuration = BrowserConfiguration.shared.webViewConfiguration

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        
        // Enable web inspector for debugging
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

        context.coordinator.onTitleChange = onTitleChange
        context.coordinator.onURLChange = onURLChange

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: urlString) else { return }

        if webView.url != url {
            if url.isFileURL {
                // Grant read access only to the specific file for security
                webView.loadFileURL(url, allowingReadAccessTo: url)
            } else {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 30.0
                webView.load(request)
            }
        }

        context.coordinator.onTitleChange = onTitleChange
        context.coordinator.onURLChange = onURLChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

// MARK: - Coordinator
extension WebView {
    class Coordinator: NSObject {
        var onTitleChange: ((String) -> Void)?
        var onURLChange: ((String) -> Void)?
    }
}

// MARK: - WKNavigationDelegate
extension WebView.Coordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        if let url = webView.url?.absoluteString {
            onURLChange?(url)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String, !title.isEmpty {
                DispatchQueue.main.async {
                    self?.onTitleChange?(title)
                }
            }
        }

        if let url = webView.url?.absoluteString {
            onURLChange?(url)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        let allowedSchemes: Set<String> = ["http", "https", "about", "blob", "data", "webkit-extension", "safari-web-extension"]

        if scheme.isEmpty || allowedSchemes.contains(scheme) {
            decisionHandler(.allow)
        } else if scheme == "javascript" {
            // Block javascript: URLs to prevent XSS
            decisionHandler(.cancel)
        } else {
            // For other schemes (mailto:, tel:, app-specific), let macOS handle them
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate
extension WebView.Coordinator: WKUIDelegate {
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

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let domain = frame.securityOrigin.host
        let truncatedMessage = message.count > 500 ? String(message.prefix(500)) + "..." : message
        let alert = NSAlert()
        alert.messageText = "JavaScript Alert from \(domain)"
        alert.informativeText = truncatedMessage
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let domain = frame.securityOrigin.host
        let truncatedMessage = message.count > 500 ? String(message.prefix(500)) + "..." : message
        let alert = NSAlert()
        alert.messageText = "JavaScript Confirm from \(domain)"
        alert.informativeText = truncatedMessage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let domain = frame.securityOrigin.host
        let truncatedMessage = prompt.count > 500 ? String(prompt.prefix(500)) + "..." : prompt
        let alert = NSAlert()
        alert.messageText = "JavaScript Prompt from \(domain)"
        alert.informativeText = truncatedMessage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 300, height: 24)
        )
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completionHandler(textField.stringValue)
        } else {
            completionHandler(nil)
        }
    }
    
    // MARK: - Full-Screen Video Support
    @available(macOS 10.15, *)
    func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(false, NSError(domain: "WebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
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

        // Get the window containing this webView
        guard let window = webView.window else {
            completionHandler(false, NSError(domain: "WebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for exiting full-screen"]))
            return
        }

        // Exit full-screen mode
        window.toggleFullScreen(nil)

        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
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
