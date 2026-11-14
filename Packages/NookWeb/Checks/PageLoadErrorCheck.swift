// Licensed under GPL-3.0. See LICENSE.
//
//  PageLoadErrorCheck.swift
//  Nook
//
//  Load error sorting check. NookWeb has no test target, so this compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/PageLoadError.swift \
//           Packages/NookWeb/Checks/PageLoadErrorCheck.swift -o /tmp/load-error-check && /tmp/load-error-check
//
//  Created by Bain Gurley on 13/11/2026.
//

import Foundation

@main
struct PageLoadErrorCheck {
    static func main() {
        let u = URL(string: "https://a.example/")!
        func e(_ domain: String, _ code: Int) -> NSError { NSError(domain: domain, code: code) }

        precondition(PageLoadError(error: e(NSURLErrorDomain, -1009), attempted: u)?.kind == .offline)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1003), attempted: u)?.kind == .hostNotFound)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1004), attempted: u)?.kind == .noAnswer)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1001), attempted: u)?.kind == .noAnswer)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1202), attempted: u)?.kind == .certificate)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1200), attempted: u)?.kind == .certificate)
        precondition(PageLoadError(error: e(NSURLErrorDomain, -1100), attempted: u)?.kind == .other)

        // Stop or a newer navigation, a load that became a download, and the ad blocker's own card.
        precondition(PageLoadError(error: e(NSURLErrorDomain, -999), attempted: u) == nil)
        precondition(PageLoadError(error: e("WebKitErrorDomain", 102), attempted: u) == nil)
        precondition(PageLoadError(error: e("WebKitErrorDomain", 104), attempted: u) == nil)

        // The failing URL in userInfo wins over the attempted one.
        let f = NSError(domain: NSURLErrorDomain, code: -1003,
                        userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://b.example/")!])
        precondition(PageLoadError(error: f, attempted: u)?.url.host == "b.example")

        print("PageLoadErrorCheck passed")
    }
}
