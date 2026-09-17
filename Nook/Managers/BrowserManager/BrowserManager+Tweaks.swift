//
//  BrowserManager+Tweaks.swift
//  Nook
//
//  Created by Claude on 17/09/2026.
//
//  The app side of NookTweaks' two seams: window and space work for Air Traffic
//  Control, and the download path for the social media download button.
//

import Foundation
import OSLog
import WebKit
import NookTabsCore
import NookTweaks
import NookWeb

private let tweaksLog = Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")

extension BrowserManager: SiteRoutingHost {
    func route(url: URL, toSpace spaceID: UUID, from page: AnyObject?) -> Bool {
        let session = page as? PageSession
        guard session?.isPrivate != true else { return false }
        guard let window = session.flatMap({ tabs.window(for: $0) }) ?? windowRegistry?.activeWindow,
              !window.isIncognito
        else { return false }

        guard tabs.space(spaceID) != nil else {
            tweaksLog.debug("Route skipped: target space \(spaceID) no longer exists")
            return false
        }
        guard window.spaceID != spaceID else { return false }

        // Deferred: callers are WebKit policy callbacks. Selecting the new tab shows its space.
        Task { @MainActor [tabs] in
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: spaceID))
        }
        return true
    }

    func liveSpaceIDs() -> Set<UUID> {
        Set(tabs.orderedSpaces.map(\.id))
    }
}

extension BrowserManager: MediaDownloading {
    func downloadImage(at url: URL, from webView: WKWebView) {
        (webView as? FocusableWKWebView)?.downloadImage(from: url)
    }
}
