// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc Nook/Managers/ExtensionManager/ExternallyConnectableMatch.swift \
//         Packages/NookWeb/Checks/ExternallyConnectableMatchCheck.swift -o /tmp/ec-check && /tmp/ec-check
import Foundation

@main
struct ExternallyConnectableMatchCheck {
    static func main() {
        let yes = ["https://foo.github.io/*", "https://*.example.co.uk/*", "https://*.example.com/*",
                   "http://localhost/*", "http://127.0.0.1:3000/*", "http://[::1]/*", "https://example.com/*"]
        let no = ["https://*.github.io/*", "https://*.co.uk/*", "https://*.com/*", "http://example.com/*",
                  "https://*.vercel.app/*", "https://*.s3.amazonaws.com/*", "*://example.com/*",
                  "https://*/*", "https://com/*", "example.com", "https://*.github.io./*", "https://*.com./*"]
        for p in yes { precondition(ExternallyConnectableMatch.isAcceptable(p), p) }
        for p in no { precondition(!ExternallyConnectableMatch.isAcceptable(p), p) }
        print("ok")
    }
}
