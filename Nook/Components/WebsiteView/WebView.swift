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
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

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
                // Grant read access to the containing directory for local resources
                let readAccessURL = url.deletingLastPathComponent()
                webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
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
        print("Started loading: \(webView.url?.absoluteString ?? "")")
        if let url = webView.url?.absoluteString {
            onURLChange?(url)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("Content started loading: \(webView.url?.absoluteString ?? "")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Finished loading: \(webView.url?.absoluteString ?? "")")

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
        print("Navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print("Provisional navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
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
        let alert = NSAlert()
        alert.messageText = "JavaScript Alert"
        alert.informativeText = message
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
        let alert = NSAlert()
        alert.messageText = "JavaScript Confirm"
        alert.informativeText = message
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
        let alert = NSAlert()
        alert.messageText = "JavaScript Prompt"
        alert.informativeText = prompt
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
        print("🎬 [WebView] Entering full-screen for video")
        
        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [WebView] No window found for full-screen")
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
                    print("📁 [WebView] Open panel sheet completed with response: \(response)")
                    if response == .OK {
                        print("📁 [WebView] User selected files: \(openPanel.urls.map { $0.lastPathComponent })")
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [WebView] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            } else {
                // Fall back to modal presentation
                openPanel.begin { response in
                    print("📁 [WebView] Open panel modal completed with response: \(response)")
                    if response == .OK {
                        print("📁 [WebView] User selected files: \(openPanel.urls.map { $0.lastPathComponent })")
                        completionHandler(openPanel.urls)
                    } else {
                        print("📁 [WebView] User cancelled file selection")
                        completionHandler(nil)
                    }
                }
            }
        }
    }

    }
