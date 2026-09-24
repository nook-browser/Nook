// Licensed under GPL-3.0. See LICENSE.
//
//  OAuthDetectorCheck.swift
//  Nook
//
//  Ordinary links must not look like sign-in popups, or they open in the mini window.
//  swiftc Sources/NookBlocker/OAuthDetector.swift Checks/OAuthDetectorCheck.swift -o /tmp/oauth && /tmp/oauth
//

import Foundation

@main
struct OAuthDetectorCheck {
    static func main() {
        let links = [
            "https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.foxnews.com%2Fpolitics&h=AT0x",
            "https://www.facebook.com/groups/123",
            "https://github.com/nook-browser/Nook/pull/400",
            "https://www.reddit.com/r/macapps/comments/abc",
            "https://x.com/someone/status/1",
            "https://www.notion.so/Team-Notes-abc123",
            "https://www.figma.com/file/abc/Design",
            "https://www.linkedin.com/in/someone",
        ]
        for link in links {
            precondition(!OAuthDetector.isLikelyOAuthPopupURL(URL(string: link)!), "ordinary link read as sign-in: \(link)")
        }

        let signIns = [
            "https://accounts.google.com/o/oauth2/v2/auth?client_id=1&redirect_uri=x&response_type=code",
            "https://www.facebook.com/v19.0/dialog/oauth?client_id=1&redirect_uri=https%3A%2F%2Fexample.com",
            "https://github.com/login/oauth/authorize?client_id=1",
            "https://slack.com/oauth/v2/authorize?client_id=1&scope=chat",
            "https://www.reddit.com/api/v1/authorize?client_id=1&response_type=code",
            "https://api.twitter.com/oauth/authenticate?oauth_token=abc",
            "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=1",
            "https://appleid.apple.com/auth/authorize?client_id=1",
        ]
        for link in signIns {
            precondition(OAuthDetector.isLikelyOAuthPopupURL(URL(string: link)!), "sign-in missed: \(link)")
        }
        print("OAuthDetectorCheck passed: \(links.count) links, \(signIns.count) sign-ins")
    }
}
