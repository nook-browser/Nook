// Licensed under GPL-3.0. See LICENSE.
//
//  SearchUtilsCheck.swift
//  Nook
//
//  What the URL bar treats as an address and what it searches. NookWeb has no test target, so
//  this compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/SearchUtils.swift \
//           Packages/NookWeb/Checks/SearchUtilsCheck.swift -o /tmp/search-utils-check && /tmp/search-utils-check
//

import Foundation

@main
struct SearchUtilsCheck {
    static func main() {
        let template = "https://search.example/?q=%@"
        let addresses = [
            "example.com", "example.de", "sub.example.co.uk/path?q=1", "example.com#top", "nas.local:8080",
            "b\u{FC}cher.de", "localhost:3000", "192.168.1.140/Dashboard", "https://x.test/a b",
        ]
        for input in addresses {
            precondition(isLikelyURL(input), "\(input) should be an address")
            precondition(!normalizeURL(input, queryTemplate: template).hasPrefix("https://search.example"), "\(input) should navigate")
        }
        for input in ["3.14", "what.", "asp.net core", "me@example.com", "v1.2", "swift", "a.b"] {
            precondition(!isLikelyURL(input), "\(input) should be a search")
            precondition(normalizeURL(input, queryTemplate: template).hasPrefix("https://search.example"), "\(input) should search")
        }
        precondition(normalizeURL("192.168.1.140", queryTemplate: template) == "http://192.168.1.140")
        precondition(normalizeURL("example.de", queryTemplate: template) == "https://example.de")
        print("SearchUtilsCheck passed")
    }
}
