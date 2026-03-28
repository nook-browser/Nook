//
//  SponsorBlockManager.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import CryptoKit
import Foundation
import OSLog
import WebKit

private let sbLog = Logger(subsystem: "com.baingurley.nook", category: "SponsorBlock")

@MainActor
final class SponsorBlockManager {

    weak var browserManager: BrowserManager?

    // MARK: - Constants

    private static let baseURL = "https://sponsor.ajay.app/api"
    private static let scriptMarker = "// Nook SponsorBlock"

    private static let youTubeDomains: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "tv.youtube.com", "youtu.be",
        "youtube-nocookie.com",
    ]

    // MARK: - State

    private var segmentCache: [String: CachedSegments] = [:]
    private let cacheTTL: TimeInterval = 3600  // 1 hour
    private var sponsorBlockScript: String?

    private struct CachedSegments {
        let segments: [SponsorBlockSegment]
        let fetchedAt: Date
    }

    // MARK: - Init

    init() {
        loadScript()
    }

    private func loadScript() {
        guard let path = Bundle.main.path(forResource: "youtube-sponsorblock", ofType: "js"),
              let source = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            sbLog.warning("Failed to load youtube-sponsorblock.js from bundle")
            return
        }
        sponsorBlockScript = source
        sbLog.info("Loaded SponsorBlock script (\(source.count) chars)")
    }

    // MARK: - Script Injection

    func injectScriptIfNeeded(for url: URL, in webView: WKWebView) {
        guard let settings = browserManager?.nookSettings,
              settings.sponsorBlockEnabled else { return }
        guard isYouTubeDomain(url.host ?? "") else { return }
        guard let script = sponsorBlockScript else { return }

        let ucc = webView.configuration.userContentController

        let marker = Self.scriptMarker
        let remaining = ucc.userScripts.filter { !$0.source.hasPrefix(marker) }
        if remaining.count != ucc.userScripts.count {
            ucc.removeAllUserScripts()
            remaining.forEach { ucc.addUserScript($0) }
        }

        let markedSource = "\(marker)\n\(script)"
        let userScript = WKUserScript(
            source: markedSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        ucc.addUserScript(userScript)

        sbLog.info("Injected SponsorBlock script for \(url.host ?? "unknown", privacy: .public)")
    }

    // MARK: - API

    /// Fetch segments using the privacy-preserving hash prefix endpoint.
    /// Only fetches categories that are not disabled.
    func fetchSegments(for videoID: String) async -> [SponsorBlockSegment] {
        // Check cache
        if let cached = segmentCache[videoID],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL
        {
            sbLog.info("Cache hit for \(videoID, privacy: .public): \(cached.segments.count) segments")
            return cached.segments
        }

        guard let settings = browserManager?.nookSettings,
              settings.sponsorBlockEnabled else { return [] }

        // Get categories that are not disabled
        let enabledCategories = Set(
            settings.sponsorBlockCategoryOptions
                .filter { $0.value != SponsorBlockSkipOption.disabled.rawValue }
                .keys
        )
        guard !enabledCategories.isEmpty else { return [] }

        let hashPrefix = sha256Prefix(videoID, length: 4)
        let fullHash = sha256Full(videoID)

        let categoriesJSON = "[\(enabledCategories.map { "\"\($0)\"" }.joined(separator: ","))]"
        let encodedCategories = categoriesJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? categoriesJSON

        guard let url = URL(string: "\(Self.baseURL)/skipSegments/\(hashPrefix)?categories=\(encodedCategories)") else {
            sbLog.error("Failed to build SponsorBlock API URL")
            return []
        }

        sbLog.info("Fetching segments for hash prefix \(hashPrefix, privacy: .public)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            if httpResponse.statusCode == 404 {
                segmentCache[videoID] = CachedSegments(segments: [], fetchedAt: Date())
                sbLog.info("No segments found for \(videoID, privacy: .public)")
                return []
            }

            guard httpResponse.statusCode == 200 else {
                sbLog.warning("SponsorBlock API returned \(httpResponse.statusCode)")
                return []
            }

            let hashResponses = try JSONDecoder().decode([SponsorBlockHashResponse].self, from: data)

            guard let videoResponse = hashResponses.first(where: { $0.hash == fullHash }) else {
                segmentCache[videoID] = CachedSegments(segments: [], fetchedAt: Date())
                sbLog.info("No hash match for \(videoID, privacy: .public)")
                return []
            }

            let segments = videoResponse.segments.filter { seg in
                enabledCategories.contains(seg.category)
                    && (seg.actionType == "skip" || seg.actionType == "mute")
            }.sorted { $0.startTime < $1.startTime }

            segmentCache[videoID] = CachedSegments(segments: segments, fetchedAt: Date())
            sbLog.info("Fetched \(segments.count) segments for \(videoID, privacy: .public)")
            return segments

        } catch {
            sbLog.error("SponsorBlock API error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Deliver segments and per-category options to the webview.
    func deliverSegments(_ segments: [SponsorBlockSegment], to webView: WKWebView) {
        guard let segData = try? JSONEncoder().encode(segments),
              let segJSON = String(data: segData, encoding: .utf8)
        else {
            sbLog.error("Failed to encode segments as JSON")
            return
        }

        // Pass category options so JS knows which are auto vs manual
        let categoryOptions = browserManager?.nookSettings?.sponsorBlockCategoryOptions ?? [:]
        guard let optData = try? JSONEncoder().encode(categoryOptions),
              let optJSON = String(data: optData, encoding: .utf8)
        else {
            sbLog.error("Failed to encode category options as JSON")
            return
        }

        let js = "window.__nookSponsorBlock?.receiveSegments(\(segJSON), \(optJSON))"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                sbLog.warning("Failed to deliver segments: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Report a viewed segment to SponsorBlock (telemetry to support community data).
    func reportViewedSegment(uuid: String) {
        guard let url = URL(string: "\(Self.baseURL)/viewedVideoSponsorTime?UUID=\(uuid)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        Task.detached {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - Helpers

    func isYouTubeDomain(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if Self.youTubeDomains.contains(lowered) { return true }
        let parts = lowered.split(separator: ".", maxSplits: 1)
        if parts.count == 2 {
            return Self.youTubeDomains.contains(String(parts[1]))
        }
        return false
    }

    private func sha256Prefix(_ input: String, length: Int) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        let hexString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hexString.prefix(length))
    }

    private func sha256Full(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
