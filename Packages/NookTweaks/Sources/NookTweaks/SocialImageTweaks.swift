// Licensed under GPL-3.0. See LICENSE.
//
//  SocialImageTweaks.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import Foundation
import NookBlocker
import NookSettings
import OSLog
import WebKit

private let socialLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "SocialImageTweaks")

/// Download button over photos and videos on the domains the user lists in Settings. The isolated script
/// picks the largest srcset candidate, or asks a page-world script for the MP4 in React's data (Facebook
/// and Instagram); the app saves it through the same WKDownload path as the image context menu.
@MainActor
public enum SocialImageTweaks {
    /// Set by the app; saves through the same WKDownload path as the image context menu.
    public static weak var downloader: MediaDownloading?

    private static let marker = "// Nook Social Image Download"
    private static let pageMarker = "// Nook Social Video Source"
    private static let world = WKContentWorld.world(name: "NookSocialImageTweaks")
    private static let handlerName = "nookSocialImageDownload"

    private static let script = source("social-image-download")
    /// Page world: reads video URLs from React props, which the isolated world cannot see.
    private static let pageScript = source("social-video-source")

    private static func source(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            socialLog.warning("Failed to load \(name, privacy: .public).js from NookTweaks")
            return nil
        }
        return source
    }

    private static func enabledDomains(_ settings: NookSettingsService) -> [String] {
        settings.mediaDownloadSites
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Main-frame navigation hook, next to YouTubeTweaks. Installed on the first visit to an enabled site and
    /// rebuilt only when the enabled sites change; the scripts check the hostname themselves.
    public static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let domains = enabledDomains(settings)
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let current = all.first { $0.source.hasPrefix(marker) }?.source
        guard current != nil || matches(url.host, domains) else { return }

        var wanted: String?
        if let script, !domains.isEmpty {
            wanted = "\(marker)\nconst NOOK_DOWNLOAD_SITES = \(jsArray(domains));\n\(script)"
        }
        guard wanted != current else { return }

        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) && !$0.source.hasPrefix(pageMarker) }
        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        ucc.removeScriptMessageHandler(forName: handlerName, contentWorld: world)
        guard let wanted else { return }
        ucc.add(Handler.shared, contentWorld: world, name: handlerName)
        if let pageScript {
            ucc.addUserScript(WKUserScript(source: "\(pageMarker)\n\(pageScript)", injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        ucc.addUserScript(WKUserScript(source: wanted, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
    }

    private static func jsArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func matches(_ host: String?, _ domains: [String]) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private final class Handler: NSObject, WKScriptMessageHandler {
        static let shared = Handler()

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any],
                  let string = body["url"] as? String,
                  let url = URL(string: string),
                  url.scheme == "https",
                  let webView = message.webView
            else { return }
            socialLog.debug("Downloading from \(url.host ?? "", privacy: .public) (\(body["note"] as? String ?? "image", privacy: .public))")
            SocialImageTweaks.downloader?.downloadImage(at: url, from: webView)
        }
    }
}
