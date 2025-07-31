//
//  Tab.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import FaviconFinder
import SwiftUI
import WebKit

@Observable
public class Tab: NSObject, Identifiable {
    public let id = UUID()
    var url: URL
    var name: String
    var favicon: SwiftUI.Image
    var spaceId: UUID?

    // MARK: - Loading State
    enum LoadingState {
        case idle
        case didStartProvisionalNavigation
        case didCommit
        case didFinish
        case didFail(Error)
        case didFailProvisionalNavigation(Error)

        var isLoading: Bool {
            switch self {
            case .idle, .didFinish, .didFail, .didFailProvisionalNavigation:
                return false
            case .didStartProvisionalNavigation, .didCommit:
                return true
            }
        }

        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .didStartProvisionalNavigation:
                return "Loading started"
            case .didCommit:
                return "Content loading"
            case .didFinish:
                return "Loading finished"
            case .didFail(let error):
                return "Loading failed: \(error.localizedDescription)"
            case .didFailProvisionalNavigation(let error):
                return "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    var loadingState: LoadingState = .idle

    var canGoBack: Bool = false
    var canGoForward: Bool = false

    // Store the WebView instance to preserve state
    private var _webView: WKWebView?
    var webView: WKWebView {
        if _webView == nil {
            setupWebView()
        }
        return _webView!
    }

    weak var browserManager: BrowserManager?

    // Computed property to check if this is the current tab
    var isCurrentTab: Bool {
        return browserManager?.tabManager.currentTab?.id == id
    }

    // Computed property for backwards compatibility
    var isLoading: Bool {
        return loadingState.isLoading
    }

    // MARK: - Initializers
    init(
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        browserManager: BrowserManager? = nil
    ) {
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.browserManager = browserManager
        super.init()

        // Fetch real favicon asynchronously
        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
        }
    }

    public init(
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil
    ) {
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.browserManager = nil
        super.init()

        // Fetch real favicon asynchronously
        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
        }
    }

    // MARK: - Controls
    func goBack() {
        guard canGoBack else { return }
        _webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        _webView?.goForward()
    }

    func refresh() {
        loadingState = .didStartProvisionalNavigation
        _webView?.reload()
    }

    func stop() {
        _webView?.stopLoading()
        loadingState = .idle
    }

    private func updateNavigationState() {
        guard let webView = _webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    // MARK: - WebView Setup
    private func setupWebView() {
        // Use the shared configuration for cookie/session sharing
        let configuration = BrowserConfiguration.shared.webViewConfiguration

        _webView = WKWebView(frame: .zero, configuration: configuration)
        _webView?.navigationDelegate = self
        _webView?.uiDelegate = self
        _webView?.allowsBackForwardNavigationGestures = true
        _webView?.allowsMagnification = true

        // Use the most recent Chrome user agent that matches current versions
        _webView?.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        
        // Additional properties to better mimic real browser
        _webView?.setValue(false, forKey: "drawsBackground")
        
        // Set additional realistic browser properties
        if let webView = _webView {
            // Enable inspection for debugging (remove in production)
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }
            
            // Configure additional settings
            webView.allowsLinkPreview = true
            webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
            webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        }
        
        print("Created WebView for tab: \(name)")
        loadURL(url)
    }

    // MARK: - Tab Actions
    func closeTab() {
        print("Closing tab: \(self.name)")

        // Stop any media playback and clean up WebView
        _webView?.stopLoading()
        _webView?.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(el => el.pause());",
            completionHandler: nil
        )
        _webView?.navigationDelegate = nil
        _webView?.uiDelegate = nil
        _webView = nil

        loadingState = .idle

        browserManager?.tabManager.removeTab(self.id)
    }

    func loadURL(_ newURL: URL) {
        self.url = newURL
        loadingState = .didStartProvisionalNavigation
        let request = URLRequest(url: newURL)
        webView.load(request)

        // Fetch favicon for new URL
        Task { @MainActor in
            await fetchAndSetFavicon(for: newURL)
        }
    }

    func loadURL(_ urlString: String) {
        guard let newURL = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL)
    }

    // MARK: - Tab State Management
    func activate() {
        browserManager?.tabManager.setActiveTab(self)
    }

    func pause() {
        // Pause media when tab becomes inactive
        _webView?.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(el => el.pause());",
            completionHandler: nil
        )
    }

    func updateTitle(_ title: String) {
        self.name = title.isEmpty ? url.host ?? "New Tab" : title
    }

    // MARK: - Favicon Logic
    private func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        // Skip favicon fetching for non-web schemes
        guard url.scheme == "http" || url.scheme == "https", let host = url.host
        else {
            await MainActor.run {
                self.favicon = defaultFavicon
            }
            return
        }

        do {
            let favicon = try await FaviconFinder(url: url)
                .fetchFaviconURLs()
                .download()
                .largest()

            if let faviconImage = favicon.image {
                let nsImage = faviconImage.image
                let swiftUIImage = SwiftUI.Image(nsImage: nsImage)

                await MainActor.run {
                    self.favicon = swiftUIImage
                }
            } else {
                await MainActor.run {
                    self.favicon = defaultFavicon
                }
            }
        } catch {
            print(
                "Error fetching favicon for \(url): \(error.localizedDescription)"
            )
            await MainActor.run {
                self.favicon = defaultFavicon
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension Tab: WKNavigationDelegate {

    // MARK: - Loading Start
    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        loadingState = .didStartProvisionalNavigation
        print(
            "🟡 Loading started for: \(webView.url?.absoluteString ?? "unknown URL")"
        )

        if let newURL = webView.url {
            self.url = newURL
        }
    }

    // MARK: - Content Committed
    public func webView(
        _ webView: WKWebView,
        didCommit navigation: WKNavigation!
    ) {
        loadingState = .didCommit
        print(
            "🔄 Content committed for: \(webView.url?.absoluteString ?? "unknown URL")"
        )

        if let newURL = webView.url {
            self.url = newURL
        }
    }

    // MARK: - Loading Success
    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        loadingState = .didFinish
        print(
            "✅ Loading finished for: \(webView.url?.absoluteString ?? "unknown URL")"
        )

        if let newURL = webView.url {
            self.url = newURL
        }

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String {
                DispatchQueue.main.async {
                    self?.updateTitle(title)
                }
            }
        }

        // Fetch favicon after page loads
        if let currentURL = webView.url {
            Task { @MainActor in
                await self.fetchAndSetFavicon(for: currentURL)
            }
        }

        updateNavigationState()
    }

    // MARK: - Loading Failed (after content started loading)
    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingState = .didFail(error)
        print(
            "❌ Navigation failed for: \(webView.url?.absoluteString ?? "unknown URL")"
        )
        print("Error: \(error.localizedDescription)")

        // Set error favicon on navigation failure
        Task { @MainActor in
            self.favicon = Image(systemName: "exclamationmark.triangle")
        }

        updateNavigationState()
    }

    // MARK: - Loading Failed (before content started loading)
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingState = .didFailProvisionalNavigation(error)
        print(
            "🚫 Provisional navigation failed for: \(webView.url?.absoluteString ?? "unknown URL")"
        )
        print("Error: \(error.localizedDescription)")

        // Set connection error favicon
        Task { @MainActor in
            self.favicon = Image(systemName: "wifi.exclamationmark")
        }

        updateNavigationState()
    }
    
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Allow all responses
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate
extension Tab: WKUIDelegate {
    public func webView(
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
        alert.runModal()
        completionHandler()
    }
}

// MARK: - Hashable & Equatable
extension Tab {
    public static func == (lhs: Tab, rhs: Tab) -> Bool {
        return lhs.id == rhs.id
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        return id.hashValue
    }
}
