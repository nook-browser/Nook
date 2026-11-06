// Licensed under GPL-3.0. See LICENSE.
//
//  NookURLCommandCheck.swift
//  Nook
//
//  swiftc Packages/NookWeb/Sources/NookWeb/NookURLCommand.swift \
//         Packages/NookWeb/Checks/NookURLCommandCheck.swift -o /tmp/nookurl-check && /tmp/nookurl-check
//

import Foundation

@main
struct NookURLCommandCheck {
    static func parse(_ s: String) -> NookURLCommand? { NookURLCommand.parse(URL(string: s)!) }

    static func main() {
        let open = parse("nook://open?url=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1%23x&space=Work&reuse=1&junk=2")
        precondition(open?.action == .open(URL(string: "https://example.com/a?b=1#x")!, reuse: true))
        precondition(open?.space == "Work" && open?.ignored == ["junk"])
        precondition(parse("nook://open?url=http://a.com")?.action == .open(URL(string: "http://a.com")!, reuse: false))
        precondition(parse("NOOK://OPEN?url=https://a.com") != nil)
        precondition(parse("nook://search?q=hello%20world&space=a")?.action == .search("hello world"))
        precondition(parse("nook://space?name=Work")?.space == "Work")
        precondition(parse("nook://open?url=https://a.com&space=") == nil && parse("nook://open?url=https://a.com&space=%20") == nil)
        precondition(parse("nook://search?q=a&space=" + String(repeating: "x", count: 9000)) == nil)

        // Hostile or malformed
        for bad in [
            "nook://open", "nook://open?url=", "nook://open?url=file:///etc/passwd",
            "nook://open?url=javascript:alert(1)", "nook://open?url=data:text/html,hi",
            "nook://open?url=nook://open?url=https://a.com", "nook://open?url=https://",
            "nook://open?url=ftp://a.com", "nook://search", "nook://search?q=%20", "nook://space",
            "nook://quit", "nook://delete?url=https://a.com", "nook:///open?url=https://a.com",
            "https://open?url=https://a.com", "nook://open?url=" + String(repeating: "a", count: 9000),
        ] {
            precondition(parse(bad) == nil, bad)
        }
        // First duplicate wins; reuse only for exactly 1.
        precondition(parse("nook://open?url=https://a.com&url=file:///x")?.action == .open(URL(string: "https://a.com")!, reuse: false))
        precondition(parse("nook://open?url=https://a.com&reuse=true")?.action == .open(URL(string: "https://a.com")!, reuse: false))

        // Search URL
        let t = "https://www.google.com/search?q=%@"
        precondition(NookURLCommand.searchURL(for: "a&b c+d", template: t)?.absoluteString == "https://www.google.com/search?q=a%26b%20c%2Bd")
        precondition(NookURLCommand.searchURL(for: "x", template: "javascript:%@") == nil)

        // Space match
        let a = UUID(), b = UUID()
        let spaces = [(id: a, name: "Work"), (id: b, name: "Home")]
        precondition(NookURLCommand.match("work", in: spaces) == a)
        precondition(NookURLCommand.match(b.uuidString.lowercased(), in: spaces) == b)
        precondition(NookURLCommand.match("Wor", in: spaces) == nil)
        precondition(NookURLCommand.match(UUID().uuidString, in: spaces) == nil)

        // Same page
        func same(_ x: String, _ y: String) -> Bool { NookURLCommand.isSamePage(URL(string: x)!, URL(string: y)!) }
        precondition(same("https://A.com/p/#top", "https://a.com/p"))
        precondition(same("https://a.com", "https://a.com/"))
        precondition(!same("https://a.com/p?x=1", "https://a.com/p?x=2"))
        precondition(!same("http://a.com", "https://a.com"))
        print("NookURLCommandCheck passed")
    }
}
