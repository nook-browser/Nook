//
//  PageSessionDelegate.swift
//  NookWeb
//
//  Everything a live page needs from the app around it: downloads, Peek, sign-in windows,
//  zoom, mute, picture-in-picture, cross-window navigation, website keyboard shortcuts,
//  the Chrome Web Store handler and the space's data store.
//

import Combine
import WebKit

/// A request from a page's `chrome.identity`-style sign-in flow.
public struct IdentityRequest {
    public let requestId: String
    public let url: URL
    public let interactive: Bool
    public let prefersEphemeralSession: Bool
    public let explicitCallbackScheme: String?

    public init(
        requestId: String, url: URL, interactive: Bool,
        prefersEphemeralSession: Bool, explicitCallbackScheme: String?
    ) {
        self.requestId = requestId
        self.url = url
        self.interactive = interactive
        self.prefersEphemeralSession = prefersEphemeralSession
        self.explicitCallbackScheme = explicitCallbackScheme
    }
}

public enum IdentityFailure: Equatable {
    case interactionRequired
    case missingCallbackHandler
    case unableToStart
    case fallbackUnavailable
    case fallbackCancelled
    case underlying(String)

    public var code: String {
        switch self {
        case .interactionRequired: return "interaction_required"
        case .missingCallbackHandler: return "missing_callback_handler"
        case .unableToStart: return "unable_to_start"
        case .fallbackUnavailable: return "fallback_unavailable"
        case .fallbackCancelled: return "fallback_cancelled"
        case .underlying: return "error"
        }
    }

    public var message: String {
        switch self {
        case .interactionRequired:
            return "User interaction is required to complete this authentication flow."
        case .missingCallbackHandler:
            return "Could not determine an appropriate callback handler for this authentication flow."
        case .unableToStart:
            return "The authentication session could not be started."
        case .fallbackUnavailable:
            return "Unable to present a fallback authentication window."
        case .fallbackCancelled:
            return "Authentication window was closed before completion."
        case .underlying(let message):
            return message
        }
    }
}

public enum IdentityFlowResult {
    case success(URL)
    case cancelled
    case failure(IdentityFailure)
}

@MainActor
public protocol PageSessionDelegate: AnyObject {
    // MARK: Profile

    /// The active window's space data store, used while a session has none of its own yet.
    var currentProfile: Profile? { get }
    /// Fires when the active space changes, so a session waiting for a data store can build its view.
    var currentProfilePublisher: AnyPublisher<Profile?, Never> { get }

    // MARK: Windows

    /// Keeps other windows showing the same page on the same URL.
    func navigateAcrossWindows(_ itemID: UUID, to url: URL)
    /// The window moved to another space: cookies, cache and history follow it.
    func windowSpaceChanged(_ window: BrowserWindowState)

    // MARK: Downloads and panels

    func addDownload(_ download: WKDownload, originalURL: URL, suggestedFilename: String)
    /// Enters or leaves full screen for the window showing `webView`. Returns false when
    /// `webView` has no window, so the caller can fail its completion handler.
    func toggleFullScreen(for webView: WKWebView) -> Bool

    // MARK: Peek and sign-in

    func presentPeek(url: URL, from session: PageSession)
    /// A mini window for an OAuth or sign-in popup; the handler runs when it closes.
    func presentSignInWindow(url: URL, completion: @escaping (Bool) -> Void)
    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for session: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool
    func beginIdentityFlow(_ request: IdentityRequest, from session: PageSession)

    // MARK: Per-page chrome

    func loadZoom(for itemID: UUID)
    func cleanupZoom(for itemID: UUID)
    func setMuteState(_ muted: Bool, for itemID: UUID)
    func requestPictureInPicture(for session: PageSession, webView: WKWebView?)
    func isPictureInPictureActive(for session: PageSession) -> Bool

    // MARK: Website keyboard shortcuts

    func configureShortcutDetection(in webView: WKWebView)
    func shortcutDetectorDidNavigate(to url: URL)
    func updateDetectedShortcuts(for url: String, shortcuts: Set<String>)

    // MARK: Chrome Web Store

    /// Installs the "Add to Nook" handler and script on a store page. Returns the handler to
    /// retain for the life of the page, or nil when the URL is not a store page.
    func installWebStoreScript(in webView: WKWebView) -> AnyObject?
    func removeWebStoreHandler(from controller: WKUserContentController)
}
