//
//  SocialImageTweaks.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import Foundation
import NookSettings
import OSLog
import WebKit

private let socialLog = Logger(subsystem: "com.baingurley.nook", category: "SocialImageTweaks")

/// Download button over photos and videos on Instagram, Facebook, and VSCO, each with its own setting. The
/// isolated script picks the largest srcset candidate, or asks a page-world script for the MP4 in React's
/// data; the app saves it through the same WKDownload path as the image context menu.
@MainActor
enum SocialImageTweaks {
    private static let marker = "// Nook Social Image Download"
    private static let pageMarker = "// Nook Social Video Source"
    private static let world = WKContentWorld.world(name: "NookSocialImageTweaks")
    private static let handlerName = "nookSocialImageDownload"
    private static let imageDomains = ["cdninstagram.com", "fbcdn.net", "vsco.co"]

    private static let script = source("social-image-download")
    /// Page world: reads video URLs from React props, which the isolated world cannot see.
    private static let pageScript = source("social-video-source")

    private static func source(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            socialLog.warning("Failed to load \(name, privacy: .public).js from bundle")
            return nil
        }
        return source
    }

    private static func enabledDomains(_ settings: NookSettingsService) -> [String] {
        var domains: [String] = []
        if settings.instagramDownload { domains.append("instagram.com") }
        if settings.facebookDownload { domains.append("facebook.com") }
        if settings.vscoDownload { domains.append("vsco.co") }
        return domains
    }

    /// Main-frame navigation hook, next to YouTubeTweaks. Installed on the first visit to an enabled site and
    /// rebuilt only when the enabled sites change; the scripts check the hostname themselves.
    static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let domains = enabledDomains(settings)
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let current = all.first { $0.source.hasPrefix(marker) }?.source
        guard current != nil || matches(url.host, domains) else { return }

        var wanted: String?
        if let script, !domains.isEmpty {
            let pattern = "(^|\\.)(" + domains.map { $0.replacingOccurrences(of: ".", with: "\\.") }.joined(separator: "|") + ")$"
            wanted = "\(marker)\nconst NOOK_DOWNLOAD_SITES = \(jsString(pattern));\n\(script)"
        }
        guard wanted != current else { return }

        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) && !$0.source.hasPrefix(pageMarker) }
        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        ucc.removeScriptMessageHandler(forName: handlerName, contentWorld: world)
        guard let wanted else { return }
        ucc.add(Handler.shared, contentWorld: world, name: handlerName)
        if let pageScript, domains.contains(where: { $0 != "vsco.co" }) {
            ucc.addUserScript(WKUserScript(source: "\(pageMarker)\n\(pageScript)", injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        ucc.addUserScript(WKUserScript(source: wanted, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
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
                  SocialImageTweaks.matches(url.host, SocialImageTweaks.imageDomains),
                  let webView = message.webView as? FocusableWKWebView
            else { return }
            socialLog.debug("Downloading \(url.absoluteString, privacy: .public) (\(body["note"] as? String ?? "image", privacy: .public))")
            webView.downloadImage(from: url)
        }
    }
}
