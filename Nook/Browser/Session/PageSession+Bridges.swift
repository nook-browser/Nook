//
//  PageSession+Bridges.swift
//  Nook
//
//  PageSession overloads of collaborator APIs that still take `Tab`. Each overload keeps the
//  label the owning track keeps when it retypes its method from `Tab` to `PageSession`; that
//  track deletes the matching entry here (the duplicate declaration will not compile). Bodies
//  use only the collaborators' internal API, so some cover less than the `Tab` originals; the
//  gaps are noted per entry. The file is empty and deleted by task Z.
//

import AppKit
import WebKit

// MARK: - PeekManager (T5)

extension PeekManager {
    func presentExternalURL(_ url: URL, from session: PageSession?) {
        guard browserManager != nil else { return }
        if currentSession?.currentURL == url {
            dismissPeek()
            return
        }
        let peek = PeekSession(
            targetURL: url,
            sourceTabId: session?.itemID,
            sourceURL: session?.url,
            windowId: windowRegistry?.activeWindow?.id ?? UUID(),
            sourceProfileId: session?.profile?.id
        )
        currentSession = peek
        webView = createWebView()
        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates.
        RunLoop.current.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.isActive = true
                NotificationCenter.default.post(name: .peekDidActivate, object: self)
            }
        }
    }
}

// MARK: - SiteRoutingManager (T5)

extension SiteRoutingManager {
    /// Opens `url` in the rule's target space of the window showing `session`.
    func applyRoute(url: URL, from session: PageSession?) -> Bool {
        guard let browserManager, session?.isPrivate != true else { return false }
        let tabs = browserManager.tabs
        guard let window = session.flatMap({ tabs.window(for: $0) }) ?? browserManager.windowRegistry?.activeWindow,
              !window.isIncognito,
              let rule = resolve(url: url),
              tabs.space(rule.targetSpaceId) != nil,
              window.spaceID != rule.targetSpaceId
        else { return false }
        Task { @MainActor in
            tabs.setSpace(rule.targetSpaceId, in: window)
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: rule.targetSpaceId))
        }
        return true
    }
}
