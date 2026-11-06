// Licensed under GPL-3.0. See LICENSE.
//
//  AllowlistRuleCheck.swift
//  Nook
//
//  swiftc Sources/NookBlocker/AllowlistRule.swift Checks/AllowlistRuleCheck.swift -o /tmp/allow && /tmp/allow
//

@main
struct AllowlistRuleCheck {
    static func main() {
        let list = ["example.com", "Docs.Google.com"]
        precondition(AllowlistRule.covering("example.com", in: list) == "example.com")
        precondition(AllowlistRule.covering("www.example.com", in: list) == "example.com")
        precondition(AllowlistRule.covering("docs.google.com", in: list) == "docs.google.com")
        precondition(AllowlistRule.covering("google.com", in: list) == nil)
        precondition(AllowlistRule.covering("notexample.com", in: list) == nil)
        precondition(AllowlistRule.covering("a.example.com", in: ["example.com", "a.example.com"]) == "a.example.com")
        precondition(AllowlistRule.covering("x.org", in: []) == nil)
    }
}
