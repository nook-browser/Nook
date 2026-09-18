// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserModel+Seams.swift
//  NookiOS
//
//  The package seams, phone edition: one web view per session, no windows to cross, no Peek,
//  PiP, zoom, shortcuts, extensions or Chrome Web Store. Alerts are UIAlertControllers.
//

import Combine
import UIKit
import WebKit
import NookBlocker
import NookTweaks
import NookWeb

// MARK: - ContentBlockerHost

extension BrowserModel: ContentBlockerHost {
    var blockablePages: [any BlockablePage] { tabs.sessions }

    func blockablePage(for webView: WKWebView) -> (any BlockablePage)? { tabs.session(for: webView) }

    var sharedUserContentController: WKUserContentController {
        BrowserConfiguration.shared.webViewConfiguration.userContentController
    }

    func onNewUserContentController(_ handler: @escaping @MainActor (WKUserContentController) -> Void) {
        BrowserConfiguration.shared.contentRuleListApplicator = { controller in
            MainActor.assumeIsolated { handler(controller) }
        }
    }
}

// MARK: - SiteRoutingHost, MediaDownloading

extension BrowserModel: SiteRoutingHost {
    func route(url: URL, toSpace spaceID: UUID, from page: AnyObject?) -> Bool {
        guard (page as? PageSession)?.isPrivate != true, tabs.space(spaceID) != nil,
              window.spaceID != spaceID else { return false }
        // Deferred: callers are WebKit policy callbacks.
        Task { @MainActor [tabs, window] in
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: spaceID))
        }
        return true
    }

    func liveSpaceIDs() -> Set<UUID> { Set(tabs.orderedSpaces.map(\.id)) }
}

extension BrowserModel: MediaDownloading {
    // ponytail: saving to Photos or Files arrives with downloads in the second plan.
    func downloadImage(at url: URL, from webView: WKWebView) {}
}

// MARK: - WebViewProvider

extension BrowserModel: WebViewProvider {
    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        NookWebView(frame: .zero, configuration: configuration)
    }

    func webView(for itemID: UUID, in windowID: UUID) -> WKWebView? { tabs.session(for: itemID)?.webView }

    func allWebViews(for itemID: UUID) -> [WKWebView] { tabs.session(for: itemID)?.webView.map { [$0] } ?? [] }

    func releaseWebViews(for session: PageSession) { session.webView?.removeFromSuperview() }

    func removeFromContainers(_ webView: WKWebView) { webView.removeFromSuperview() }
}

// MARK: - PageSessionDelegate

extension BrowserModel: PageSessionDelegate {
    var currentProfile: Profile? { currentProfileValue }

    var currentProfilePublisher: AnyPublisher<Profile?, Never> { $currentProfileValue.eraseToAnyPublisher() }

    func navigateAcrossWindows(_ itemID: UUID, to url: URL) {}

    func windowSpaceChanged(_ window: BrowserWindowState) {
        currentProfileValue = window.spaceID.flatMap { tabs.profile(forSpace: $0) }
    }

    func addDownload(_ download: WKDownload, originalURL: URL, suggestedFilename: String) {
        // WKDownload.delegate is weak, so the array is what keeps it alive.
        let handler = IOSDownload { [weak self] finished in
            self?.downloads.removeAll { $0 === finished }
        }
        downloads.append(handler)
        download.delegate = handler
    }

    func toggleFullScreen(for webView: WKWebView) -> Bool { false }

    func presentPeek(url: URL, from session: PageSession) { session.navigate(to: url.absoluteString) }

    func presentSignInWindow(url: URL, completion: @escaping (Bool) -> Void) { completion(false) }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge, for session: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool { false }

    func beginIdentityFlow(_ request: IdentityRequest, from session: PageSession) {}
    func loadZoom(for itemID: UUID) {}
    func cleanupZoom(for itemID: UUID) {}
    func setMuteState(_ muted: Bool, for itemID: UUID) {}
    func requestPictureInPicture(for session: PageSession, webView: WKWebView?) {}
    func isPictureInPictureActive(for session: PageSession) -> Bool { false }
    func configureShortcutDetection(in webView: WKWebView) {}
    func shortcutDetectorDidNavigate(to url: URL) {}
    func updateDetectedShortcuts(for url: String, shortcuts: Set<String>) {}
    func installWebStoreScript(in webView: WKWebView) -> AnyObject? { nil }
    func removeWebStoreHandler(from controller: WKUserContentController) {}
}

// MARK: - AlertPresenter

extension BrowserModel: AlertPresenter {
    private func present(_ alert: UIAlertController, over webView: WKWebView, cancel: @escaping () -> Void) {
        guard let root = webView.window?.rootViewController else { return cancel() }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
    }

    func presentAlert(message: String, over webView: WKWebView, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion() })
        present(alert, over: webView, cancel: completion)
    }

    func presentConfirm(message: String, over webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        present(alert, over: webView) { completion(false) }
    }

    func presentPrompt(
        prompt: String, defaultText: String?, over webView: WKWebView,
        completion: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completion(alert?.textFields?.first?.text)
        })
        present(alert, over: webView) { completion(nil) }
    }

    func presentOpenPanel(
        allowsMultipleSelection: Bool, allowsDirectories: Bool, over webView: WKWebView,
        completion: @escaping ([URL]?) -> Void
    ) {
        completion(nil)   // ponytail: UIDocumentPickerViewController arrives with downloads
    }
}
