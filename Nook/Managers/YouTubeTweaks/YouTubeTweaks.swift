//
//  YouTubeTweaks.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import Foundation
import NookSettings
import OSLog
import WebKit

private let ytLog = Logger(subsystem: "com.baingurley.nook", category: "YouTubeTweaks")

/// The selectors each hideable home shelf is matched by. The enum itself lives in NookSettings.
extension YouTubeHomeSection {
    fileprivate static let shorts = "ytm-shorts-lockup-view-model, ytm-shorts-lockup-view-model-v2"
    fileprivate static let postItems = "ytd-post-renderer, ytd-backstage-post-thread-renderer"
    fileprivate static let gameItems = "ytd-mini-game-card-view-model, ytd-game-card-renderer"

    fileprivate var selector: String {
        switch self {
        case .posts:
            return "ytd-rich-section-renderer:has(\(Self.postItems))"
        case .playables:
            return "ytd-rich-section-renderer:has(\(Self.gameItems))"
        case .otherShelves:
            // Shorts, posts, and playables keep their own toggles.
            return "ytd-rich-section-renderer:has(ytd-rich-shelf-renderer):not(:has(\(Self.shorts), \(Self.postItems), \(Self.gameItems)))"
        case .surveys:
            return "ytd-rich-section-renderer:has(ytd-inline-survey-renderer, ytd-statement-banner-renderer, ytd-brand-video-shelf-renderer)"
        case .filterChips:
            return "ytd-feed-filter-chip-bar-renderer"
        }
    }
}

@MainActor
enum YouTubeTweaks {
    static let videosPerRowRange = 3...8

    private static let marker = "// Nook YouTube Tweaks"
    private static let world = WKContentWorld.world(name: "NookYouTubeTweaks")

    private static let script: String? = {
        guard let url = Bundle.main.url(forResource: "youtube-tweaks", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            ytLog.warning("Failed to load youtube-tweaks.js from bundle")
            return nil
        }
        return source
    }()

    private static let shortsSelectors = [
        "ytd-rich-section-renderer:has(\(YouTubeHomeSection.shorts))",  // home shelf
        "grid-shelf-view-model:has(\(YouTubeHomeSection.shorts))",  // search shelf
        "ytd-reel-shelf-renderer",
        "ytd-rich-item-renderer:has(a[href^=\"/shorts/\"])",  // subscriptions feed
        "ytd-video-renderer:has(a[href^=\"/shorts/\"])",  // search results
        "yt-lockup-view-model:has(a[href^=\"/shorts/\"])",  // watch page sidebar
        "ytd-guide-entry-renderer:has(a[href^=\"/shorts\"])",
        "ytd-mini-guide-entry-renderer:has(a[href^=\"/shorts\"])",
        "yt-tab-shape[tab-title=\"Shorts\"]",  // channel tab; English UI only
    ]

    /// Main-frame navigation hook, next to SponsorBlock's. Settings apply from the next page load.
    static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let host = url.host?.lowercased()
        let source = (host == "www.youtube.com" || host == "youtube.com") ? userScriptSource(settings) : nil

        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts() (Release-only trap).
        let all = ucc.userScripts
        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) }
        let current = all.first { $0.source.hasPrefix(marker) }?.source
        guard current != source else { return }

        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        if let source {
            ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
    }

    private static func userScriptSource(_ settings: NookSettingsService) -> String? {
        guard let script else { return nil }
        let css = css(for: settings)
        guard !css.isEmpty || settings.youTubeFrameThumbnails || settings.youTubeNoHoverPreview else { return nil }

        let config: [String: Any] = [
            "css": css,
            "frameThumbnails": settings.youTubeFrameThumbnails,
            "noHoverPreview": settings.youTubeNoHoverPreview,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: .sortedKeys),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return "\(marker)\n\(script)(\(json));"
    }

    /// One rule per selector: an unknown selector in a list would drop the whole rule.
    private static func css(for settings: NookSettingsService) -> String {
        var hidden: [String] = []
        if settings.youTubeHideShorts { hidden += shortsSelectors }
        hidden += settings.youTubeHiddenHomeSections
            .compactMap(YouTubeHomeSection.init(rawValue:))
            .map { "ytd-browse[page-subtype=\"home\"] \($0.selector)" }

        var rules = hidden.map { "\($0) { display: none !important; }" }
        if settings.youTubeHiddenHomeSections.contains(YouTubeHomeSection.filterChips.rawValue) {
            // The masthead backdrop stays sized for the chip bar and would cover the first row.
            rules.append("ytd-app:has(ytd-browse[page-subtype=\"home\"]:not([hidden])) #frosted-glass.with-chipbar { height: var(--ytd-masthead-height, 56px) !important; }")
        }

        let perRow = settings.youTubeVideosPerRow
        if videosPerRowRange.contains(perRow) {
            // Grids on home, subscriptions, and channel pages. YouTube sets these inline from window width.
            rules.append("ytd-rich-grid-renderer { --ytd-rich-grid-items-per-row: \(perRow) !important; --ytd-rich-grid-posts-per-row: \(perRow) !important; }")
        }
        if settings.youTubeNoHoverPreview {
            // Backstop if a preview starts anyway.
            rules.append("ytd-video-preview { display: none !important; }")
        }
        if settings.youTubeFrameThumbnails {
            // Frames are 4:3 with letterboxing; cover crops them back to the 16:9 picture.
            rules.append("img[data-nook-frame] { width: 100% !important; height: 100% !important; object-fit: cover !important; }")
        }
        return rules.joined(separator: "\n")
    }
}
