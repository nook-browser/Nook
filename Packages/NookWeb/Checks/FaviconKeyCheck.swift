// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconKeyCheck.swift
//  Nook
//
//  Favicon cache key check. Compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/FaviconCache.swift \
//           Packages/NookWeb/Checks/FaviconKeyShim.swift \
//           Packages/NookWeb/Checks/FaviconKeyCheck.swift -o /tmp/favicon-key-check && /tmp/favicon-key-check
//

import Foundation

@main
struct FaviconKeyCheck {
    static func key(_ s: String) -> String? { FaviconCache.key(for: URL(string: s)!) }

    static func main() {
        precondition(key("http://h") == "h")
        precondition(key("http://h:80") == "h")
        precondition(key("https://h:443") == "h")
        precondition(key("https://h") == "h")
        precondition(key("http://h:8080") == "h_8080")
        precondition(key("https://h:8443") == "h_8443")
        precondition(key("http://h:443") == "h_443")
        precondition(key("http://[::1]:8080") == "::1_8080")
        precondition(key("mailto:a@b") == nil)

        for k in ["::1_8080", "a/b", "h_8080", "x.y-z"] {
            let name = FaviconCache.shared.fileName(k)
            precondition(name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil, name)
        }
        precondition(FaviconCache.shared.fileName("::1_8080") == "__1_8080.png")
        precondition(FaviconCache.shared.fileName("example.com") == "example.com.png")
        print("FaviconKeyCheck ok")
    }
}
