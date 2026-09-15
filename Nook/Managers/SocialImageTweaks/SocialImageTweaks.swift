//
//  SocialImageTweaks.swift
//  Nook
//
//  Created by Claude on 15/09/2026.
//

import Foundation
import OSLog
import WebKit

private let socialLog = Logger(subsystem: "com.baingurley.nook", category: "SocialImageTweaks")

/// Download button over photos and videos on Instagram, Facebook, and VSCO. The isolated script picks the
/// largest srcset candidate, or asks a page-world script for the MP4 in React's data; the app saves it
/// through the same WKDownload path as the image context menu.
@MainActor
enum SocialImageTweaks {
    private static let marker = "// Nook Social Image Download"
    private static let world = WKContentWorld.world(name: "NookSocialImageTweaks")
    private static let handlerName = "nookSocialImageDownload"
    private static let siteDomains = ["instagram.com", "facebook.com", "vsco.co"]
    private static let imageDomains = ["cdninstagram.com", "fbcdn.net", "vsco.co"]

    private static let script = bundled("social-image-download")
    /// Page world: reads video URLs from React props, which the isolated world cannot see.
    private static let pageScript = bundled("social-video-source")

    private static func bundled(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            socialLog.warning("Failed to load \(name, privacy: .public).js from bundle")
            return nil
        }
        return "\(marker)\n\(source)"
    }

    /// Main-frame navigation hook, next to YouTubeTweaks. The script checks the hostname itself, so once
    /// installed it stays for the tab's life: leaving and returning to these sites rebuilds nothing.
    static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let installed = all.contains { $0.source.hasPrefix(marker) }

        if settings.socialImageDownload {
            guard !installed, let script, let pageScript, matches(url.host, siteDomains) else { return }
            ucc.add(Handler.shared, contentWorld: world, name: handlerName)
            ucc.addUserScript(WKUserScript(source: pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
            ucc.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        } else if installed {
            let others = all.filter { !$0.source.hasPrefix(marker) }
            ucc.removeAllUserScripts()
            others.forEach { ucc.addUserScript($0) }
            ucc.removeScriptMessageHandler(forName: handlerName, contentWorld: world)
        }
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
