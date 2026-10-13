// Licensed under GPL-3.0. See LICENSE.
//
//  SiteRoutingRuleCheck.swift
//  Nook
//
//  Which Air Traffic Control rule a URL takes. NookSettings has no test target, so this compiles
//  the shipped source directly:
//
//    swiftc Packages/NookSettings/Sources/NookSettings/SiteRoutingRule.swift \
//           Packages/NookSettings/Checks/SiteRoutingRuleCheck.swift -o /tmp/site-routing-check && /tmp/site-routing-check
//

import Foundation

@main
struct SiteRoutingRuleCheck {
    static func main() {
        let space = UUID()
        func rule(_ domain: String, _ path: String? = nil, on: Bool = true) -> SiteRoutingRule {
            SiteRoutingRule(domain: domain, pathPrefix: path, targetSpaceId: space, isEnabled: on)
        }
        let google = rule("google.com"), mail = rule("mail.google.com"), maps = rule("google.com", "/maps")
        let deep = rule("google.com", "/maps/dir"), x = rule("x.com"), off = rule("example.com", on: false)
        let rules = [google, mail, maps, deep, x, off]
        func best(_ url: String) -> SiteRoutingRule? { SiteRoutingRule.best(for: URL(string: url)!, in: rules) }

        precondition(best("https://google.com/") == google)
        precondition(best("https://www.google.com/search?q=1") == google, "www is a subdomain")
        precondition(best("https://docs.google.com/document") == google, "a rule covers subdomains")
        precondition(best("https://mail.google.com/maps") == mail, "the longest domain wins over a path")
        precondition(best("https://www.google.com/maps/place") == maps)
        precondition(best("https://google.com/maps/dir/a") == deep, "the longest path prefix wins")
        precondition(best("https://X.com/home") == x, "hosts compare without case")
        precondition(best("https://netflix.com/") == nil, "a domain is not a substring")
        precondition(best("https://notgoogle.com/") == nil)
        precondition(best("https://example.com/") == nil, "a disabled rule never matches")
        precondition(best("about:blank") == nil)
        print("SiteRoutingRuleCheck passed")
    }
}
