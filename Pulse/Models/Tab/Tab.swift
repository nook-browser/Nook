//
//  Tab.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import FaviconFinder
import Foundation
import SwiftUI
import WebKit

@MainActor
@Observable
public class Tab: NSObject, Identifiable {
    public let id: UUID
    var url: URL
    var name: String
    var favicon: SwiftUI.Image
    var spaceId: UUID?
    var index: Int

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

    private var _webView: WKWebView?
    var didNotifyOpenToExtensions: Bool = false
    var webView: WKWebView {
        if _webView == nil {
            setupWebView()
        }
        return _webView!
    }

    weak var browserManager: BrowserManager?

    var isCurrentTab: Bool {
        return browserManager?.tabManager.currentTab?.id == id
    }

    var isLoading: Bool {
        return loadingState.isLoading
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        browserManager: BrowserManager? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.index = index
        self.browserManager = browserManager
        super.init()

        Task { @MainActor in
            await fetchAndSetFavicon(for: url)
        }
    }

    public init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.spaceId = spaceId
        self.index = index
        self.browserManager = nil
        super.init()

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

        _webView?.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"

        _webView?.setValue(false, forKey: "drawsBackground")

        if let webView = _webView {
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }

            webView.allowsLinkPreview = true
            webView.configuration.preferences
                .isFraudulentWebsiteWarningEnabled = true
            webView.configuration.preferences
                .javaScriptCanOpenWindowsAutomatically = true
            // No ad-hoc page script injection here; rely on WKWebExtension
        }

        print("Created WebView for tab: \(name)")
        // Inform extensions that this tab's view is now open/available BEFORE loading,
        // so content scripts and messaging can resolve this tab during early document phases
        if #available(macOS 15.5, *), didNotifyOpenToExtensions == false {
            ExtensionManager.shared.notifyTabOpened(self)
            didNotifyOpenToExtensions = true
        }
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
    
    // No custom JavaScript injection

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
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.title])
        }
    }

    // MARK: - Favicon Logic
    private func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        // Skip favicon fetching for non-web schemes
        guard url.scheme == "http" || url.scheme == "https", url.host != nil
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
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

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
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

        if let newURL = webView.url {
            self.url = newURL
            if #available(macOS 15.5, *) {
                ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.URL])
            }
        }
    }

    // MARK: - Loading Success
    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        loadingState = .didFinish
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.loading])
        }

        if let newURL = webView.url {
            self.url = newURL
            if #available(macOS 15.5, *) {
                ExtensionManager.shared.notifyTabPropertiesChanged(self, properties: [.URL])
            }
        }

        webView.evaluateJavaScript("document.title") {
            [weak self] result, error in
            if let title = result as? String {
                DispatchQueue.main.async {
                    self?.updateTitle(title)
                    
                    // Add to global history after title is updated
                    if let currentURL = webView.url {
                        self?.browserManager?.historyManager.addVisit(
                            url: currentURL,
                            title: title,
                            timestamp: Date(),
                            tabId: self?.id
                        )
                    }
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
        if let url = navigationAction.request.url {
            let pathExtension = url.pathExtension.lowercased()
            let downloadExtensions: Set<String> = [
                "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                "mp4", "avi", "mov", "wmv", "flv", "mkv",
                "mp3", "wav", "aac", "flac",
                "exe", "dmg", "pkg", "deb", "rpm",
                "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"
            ]
            
            if downloadExtensions.contains(pathExtension) {
                decisionHandler(.download)
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
        if let mime = navigationResponse.response.mimeType?.lowercased() {
            let forceDownloadMIMEs: Set<String> = [
                // Images
                "image/jpeg",
                "image/png",
                "image/gif",
                "image/bmp",
                "image/tiff",
                "image/webp",
                // Archives
                "application/zip",
                "application/x-zip-compressed",
                "application/x-rar-compressed",
                "application/x-7z-compressed",
                "application/x-tar",
                "application/gzip",
                "application/x-gzip",
                // Documents
                "application/pdf",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/vnd.ms-powerpoint",
                "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                // Media
                "video/mp4",
                "video/avi",
                "video/quicktime",
                "video/x-msvideo",
                "audio/mpeg",
                "audio/wav",
                "audio/aac",
                // Executables
                "application/x-executable",
                "application/x-dosexec",
                "application/x-msdownload",
                // Generic binary
                "application/octet-stream",
                "application/binary",
            ]
            
            if forceDownloadMIMEs.contains(mime) {
                decisionHandler(.download)
                return
            }
        }
        
        // Also check URL path for common file extensions
        if let url = navigationResponse.response.url {
            let pathExtension = url.pathExtension.lowercased()
            let downloadExtensions: Set<String> = [
                "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                "mp4", "avi", "mov", "wmv", "flv", "mkv",
                "mp3", "wav", "aac", "flac",
                "exe", "dmg", "pkg", "deb", "rpm",
                "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"
            ]
            
            if downloadExtensions.contains(pathExtension) {
                decisionHandler(.download)
                return
            }
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
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
        print("Download started from navigationAction: \(originalURL.absoluteString)")
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let originalURL = navigationResponse.response.url ?? URL(string: "https://example.com")!
        let suggestedFilename = navigationResponse.response.url?.lastPathComponent ?? "download"
        
        _ = browserManager?.downloadManager.addDownload(download, originalURL: originalURL, suggestedFilename: suggestedFilename)
        print("Download started from navigationResponse: \(originalURL.absoluteString)")
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
