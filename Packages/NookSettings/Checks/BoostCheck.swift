// Licensed under GPL-3.0. See LICENSE.
//
//  BoostCheck.swift
//  Nook
//
//  Boost matching, CSS, import validation and lossy loading:
//
//    swiftc Packages/NookSettings/Sources/NookSettings/SiteRoutingRule.swift \
//           Packages/NookSettings/Sources/NookSettings/Boost.swift \
//           Packages/NookSettings/Checks/BoostCheck.swift -o /tmp/boost-check && /tmp/boost-check
//

import Foundation

@main
struct BoostCheck {
    static func main() throws {
        precondition(Boost.normalizeHost("https://www.Example.com/a") == "example.com")
        for bad in ["com", "*.com", "", "a b.com", ".com", "a..", "exa*mple.com"] {
            precondition(Boost.normalizeHost(bad).isEmpty, bad)
        }

        let b = Boost(host: "example.com")
        func hit(_ boost: Boost, _ s: String) -> Bool { boost.matches(URL(string: s)!) }
        precondition(hit(b, "https://example.com/x") && hit(b, "http://www.example.com") && hit(b, "https://a.b.example.com:8080"))
        precondition(!hit(b, "https://notexample.com") && !hit(b, "https://example.com.evil.io"))
        precondition(!hit(b, "about:blank") && !hit(b, "file:///example.com") && !hit(b, "nook://example.com"))
        var exact = b; exact.includeSubdomains = false
        precondition(hit(exact, "https://example.com") && !hit(exact, "https://www.example.com"))
        var off = b; off.isEnabled = false
        precondition(!hit(off, "https://example.com"))

        precondition(Boost(host: "example.com").compiledCSS.isEmpty)
        var styled = Boost(host: "example.com", brightness: 0.8, fontFamily: "Menlo}; body{display:none", fontScale: 1.2, textCase: .uppercase, css: "a{color:red}")
        let css = styled.compiledCSS
        precondition(css.contains("brightness(0.80)") && css.contains("font-size: 120%") && css.hasSuffix("a{color:red}"))
        precondition(!css.contains("display:none") && !css.contains("};"), "font name must not escape its rule")
        styled.tint = "#FF0000"
        precondition(styled.compiledCSS.contains("background: #FF0000") && styled.compiledCSS.contains("mix-blend-mode"))
        for bad in ["red", "#FF00", "#GG0000", "#FF0000; x{}", ""] {
            styled.tint = bad
            precondition(!styled.compiledCSS.contains("html::after"), bad)
        }
        styled.tint = "#00FF00"
        styled.resetVisuals()
        precondition(styled.compiledCSS == "a{color:red}" && styled.tint.isEmpty)

        // Dark page: one root filter carrying the brightness too, pictures turned back, and reset.
        var dark = Boost(host: "example.com", brightness: 0.9, darkPage: true)
        let darkCSS = dark.compiledCSS
        precondition(darkCSS.contains("filter: invert(1) hue-rotate(180deg) brightness(0.90) !important"), darkCSS)
        precondition(darkCSS.components(separatedBy: "html { filter").count == 2, "one root filter")
        precondition(darkCSS.contains("img, video") && darkCSS.contains(":where(html)"))
        dark.resetVisuals()
        precondition(!dark.darkPage && dark.compiledCSS.isEmpty)
        // A Boost saved before the field existed loads with it off.
        let old = try JSONDecoder().decode(Boost.self, from: Data(#"{"host":"a.com"}"#.utf8))
        precondition(!old.darkPage)

        var script = Boost(host: "example.com", script: "alert(1)", scriptEnabled: true)
        let data = BoostBundle.export([script])!
        let back = try BoostBundle.parse(data)
        precondition(back.count == 1 && !back[0].scriptEnabled && back[0].id != script.id && back[0].script == "alert(1)")
        script.host = "com"
        precondition((try? BoostBundle.parse(BoostBundle.export([script])!)) == nil)
        precondition((try? BoostBundle.parse(Data("{}".utf8))) == nil)
        precondition((try? BoostBundle.parse(Data(#"{"schema":99,"boosts":[]}"#.utf8))) == nil)

        // One broken entry and one with only a host: the first drops, the second keeps defaults.
        let json = #"[{"nonsense":1},{"host":"a.com"}]"#
        let lossy = try JSONDecoder().decode(LossyBoosts.self, from: Data(json.utf8))
        precondition(lossy.boosts.count == 1 && lossy.boosts[0].isEnabled && lossy.boosts[0].brightness == 1)
        print("BoostCheck ok")
    }
}
