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
        
        let downloadScript = WKUserScript(
            source: """
            (function() {
                // Override click handlers for download links
                document.addEventListener('click', function(e) {
                    var target = e.target;
                    while (target && target !== document) {
                        if (target.tagName === 'A' && target.href) {
                            var href = target.href.toLowerCase();
                            var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                            
                            for (var i = 0; i < downloadExtensions.length; i++) {
                                if (href.indexOf('.' + downloadExtensions[i]) !== -1) {
                                    // Force download by creating a new link
                                    var link = document.createElement('a');
                                    link.href = target.href;
                                    link.download = target.download || target.href.split('/').pop();
                                    link.style.display = 'none';
                                    document.body.appendChild(link);
                                    link.click();
                                    document.body.removeChild(link);
                                    e.preventDefault();
                                    e.stopPropagation();
                                    return false;
                                }
                            }
                        }
                        target = target.parentElement;
                    }
                }, true);
                
                // Override window.open for download links
                var originalOpen = window.open;
                window.open = function(url, name, features) {
                    if (url && typeof url === 'string') {
                        var lowerUrl = url.toLowerCase();
                        var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                        
                        for (var i = 0; i < downloadExtensions.length; i++) {
                            if (lowerUrl.indexOf('.' + downloadExtensions[i]) !== -1) {
                                // Force download instead of opening in new window
                                var link = document.createElement('a');
                                link.href = url;
                                link.download = url.split('/').pop();
                                link.style.display = 'none';
                                document.body.appendChild(link);
                                link.click();
                                document.body.removeChild(link);
                                return null;
                            }
                        }
                    }
                    return originalOpen.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(downloadScript)

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
            // Inject content-script loader per webview (handles matches/runAt)
            injectContentScriptLoader(to: webView)
            // Inject storage.onChanged sink so native can broadcast changes
            injectStorageChangeSink(to: webView)
            
            injectDownloadJavaScript(to: webView)
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
    
    // MARK: - JavaScript Injection
    private func injectDownloadJavaScript(to webView: WKWebView) {
        let downloadScript = """
        (function() {
            // Override click handlers for download links
            document.addEventListener('click', function(e) {
                var target = e.target;
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href) {
                        var href = target.href.toLowerCase();
                        var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                        
                        for (var i = 0; i < downloadExtensions.length; i++) {
                            if (href.indexOf('.' + downloadExtensions[i]) !== -1) {
                                // Force download by creating a new link
                                var link = document.createElement('a');
                                link.href = target.href;
                                link.download = target.download || target.href.split('/').pop();
                                link.style.display = 'none';
                                document.body.appendChild(link);
                                link.click();
                                document.body.removeChild(link);
                                e.preventDefault();
                                e.stopPropagation();
                                return false;
                            }
                        }
                    }
                    target = target.parentElement;
                }
            }, true);
            
            // Override window.open for download links
            var originalOpen = window.open;
            window.open = function(url, name, features) {
                if (url && typeof url === 'string') {
                    var lowerUrl = url.toLowerCase();
                    var downloadExtensions = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'doc', 'docx', 'mp4', 'mp3', 'exe', 'dmg'];
                    
                    for (var i = 0; i < downloadExtensions.length; i++) {
                        if (lowerUrl.indexOf('.' + downloadExtensions[i]) !== -1) {
                            // Force download instead of opening in new window
                            var link = document.createElement('a');
                            link.href = url;
                            link.download = url.split('/').pop();
                            link.style.display = 'none';
                            document.body.appendChild(link);
                            link.click();
                            document.body.removeChild(link);
                            return null;
                        }
                    }
                }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
        
        webView.evaluateJavaScript(downloadScript) { result, error in
            if let error = error {
                print("Error injecting download JavaScript: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Content Script Injection
    private func injectContentScriptLoader(to webView: WKWebView) {
        guard let extMgr = browserManager?.extensionManager else { return }
        let registry = buildContentScriptRegistry(from: extMgr.installedExtensions)
        guard let registryJSONData = try? JSONSerialization.data(withJSONObject: registry, options: []),
              let registryJSON = String(data: registryJSONData, encoding: .utf8) else { return }

        let loader = #"""
        (function(){
          try {
            const REG = __REGISTRY__;
            const url = location.href;
            const isTop = (window.top === window);
            function toRegex(pat){
              if (pat === '<all_urls>') return /^https?:\/\/.+/;
              const m = pat.match(/^(\*|http|https|file|ftp):\/\/([^\/]+)(\/.*)$/);
              if (!m) return /^$/;
              let [, scheme, host, path] = m;
              let sch = scheme === '*' ? '(https?|file|ftp)' : scheme.replace(/[-/\\^$*+?.()|[\]{}]/g,'\\$&');
              let h = host === '*' ? '[^/]+' : host.replace(/\./g,'\\.').replace(/^\*\./,'([^/.]+\\.)?').replace(/^\*$/,'[^/]+');
              let p = path.replace(/\./g,'\\.').replace(/\*/g,'.*');
              return new RegExp('^' + sch + '://' + h + p + '$');
            }
            function matches(list){ return (list||[]).some(p => toRegex(p).test(url)); }
            function excludes(list){ return (list||[]).some(p => toRegex(p).test(url)); }
            function permitted(hosts){ if (!hosts || hosts.length===0) return true; return hosts.some(p => toRegex(p).test(url)); }
            async function injectJS(src, extId){
              try {
                const u = 'chrome-extension://' + extId + '/' + src.replace(/^\//,'');
                const s = document.createElement('script'); s.src = u; s.async = false; s.defer = false;
                s.addEventListener('error', async ()=>{ try { const res = await fetch(u); if (res.ok) { const code = await res.text(); const s2 = document.createElement('script'); s2.textContent = code; (document.documentElement||document.head||document.body).appendChild(s2); } } catch(e){} });
                (document.documentElement||document.head||document.body).appendChild(s);
              } catch(e) { console.log('CS injectJS error', src, e); }
            }
            async function injectCSS(href, extId){
              try {
                const u = 'chrome-extension://' + extId + '/' + href.replace(/^\//,'');
                const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = u;
                l.addEventListener('error', async ()=>{ try { const res = await fetch(u); if (res.ok) { const css = await res.text(); const st = document.createElement('style'); st.textContent = css; (document.documentElement||document.head||document.body).appendChild(st); } } catch(e){} });
                (document.documentElement||document.head||document.body).appendChild(l);
              } catch(e) { console.log('CS injectCSS error', href, e); }
            }
            function runPhase(phase){
              (REG.items||[]).forEach(item => {
                try {
                  if (phase !== (item.runAt||'document_idle')) return;
                  if (!isTop && !item.allFrames) return;
                  if (!matches(item.matches)) return;
                  if (excludes(item.excludeMatches)) return;
                  if (!permitted(item.hosts)) return;
                  (item.css||[]).forEach(href => injectCSS(href, item.extId));
                  (item.js||[]).forEach(src => injectJS(src, item.extId));
                } catch(e){ console.log('CS inject item error', e); }
              });
            }
            // document_start
            runPhase('document_start');
            // document_end
            document.addEventListener('DOMContentLoaded', function(){ runPhase('document_end'); }, { once:true });
            // document_idle
            window.addEventListener('load', function(){ setTimeout(function(){ runPhase('document_idle'); }, 200); }, { once:true });
          } catch(e) { console.log('CS loader error', e); }
        })();
        """#.replacingOccurrences(of: "__REGISTRY__", with: registryJSON)

        let userScript = WKUserScript(source: loader, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    private func injectStorageChangeSink(to webView: WKWebView) {
        let script = """
        (function(){
          try {
            window.chrome = window.chrome || {};
            window.chrome.storage = window.chrome.storage || {};
            if (!window.chrome.storage.onChanged) {
              const listeners = [];
              window.chrome.storage.onChanged = {
                addListener(fn){ if (typeof fn==='function') listeners.push(fn); },
                removeListener(fn){ const i=listeners.indexOf(fn); if (i>=0) listeners.splice(i,1); },
                hasListener(fn){ return listeners.includes(fn); },
                hasListeners(){ return listeners.length>0; }
              };
              window.__pulseStorageChanged = function(payload, area){ try { listeners.forEach(fn => { try { fn(payload, area||'local'); } catch(e){} }); } catch(e){} };
            }
          } catch(e) { }
        })();
        """
        let user = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(user)
    }

    private func buildContentScriptRegistry(from exts: [InstalledExtension]) -> [String: Any] {
        var items: [[String: Any]] = []
        for ext in exts where ext.isEnabled {
            if let csArr = ext.manifest["content_scripts"] as? [[String: Any]] {
                let grantedHosts = browserManager?.extensionManager?.getGrantedHostPermissions(for: ext.id) ?? []
                for cs in csArr {
                    let matches = cs["matches"] as? [String] ?? []
                    let exclude = cs["exclude_matches"] as? [String] ?? []
                    let allFrames = cs["all_frames"] as? Bool ?? false
                    let runAt = (cs["run_at"] as? String) ?? "document_idle"
                    let js = cs["js"] as? [String] ?? []
                    let css = cs["css"] as? [String] ?? []
                    items.append([
                        "extId": ext.id,
                        "matches": matches,
                        "excludeMatches": exclude,
                        "allFrames": allFrames,
                        "runAt": runAt,
                        "js": js,
                        "css": css,
                        "hosts": grantedHosts
                    ])
                }
            }
        }
        return ["items": items]
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

        if let newURL = webView.url {
            self.url = newURL
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
        
        injectDownloadJavaScript(to: webView)

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
