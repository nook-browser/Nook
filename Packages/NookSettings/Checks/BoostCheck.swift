// Licensed under GPL-3.0. See LICENSE.
//
//  BoostCheck.swift
//  Nook
//
//  Boost matching, CSS, import validation and lossy loading:
//
//    swiftc Packages/NookSettings/Sources/NookSettings/SiteRoutingRule.swift \
//           Packages/NookSettings/Sources/NookSettings/Boost.swift \
//           Packages/NookSettings/Sources/NookSettings/BoostStore.swift \
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

        // Dark page: a layer over the page carries the filter (none on the root), pictures turned back, and reset.
        var dark = Boost(host: "example.com", brightness: 0.9, darkPage: true)
        let darkCSS = dark.compiledCSS
        precondition(darkCSS.contains("backdrop-filter: invert(1) hue-rotate(180deg) brightness(0.90)"), darkCSS)
        precondition(!darkCSS.contains("html { filter") && !darkCSS.contains("html{filter"), "no filter on the root")
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

        // Zap: stored as selectors, compiled to host##selector, and the YouTube bait is refused.
        var zapped = Boost(host: "example.com", zaps: ["div.ad", "#player-ads", "div#player-ads.x", "a{b}", "x##y", ""])
        precondition(Boost.zapFilterLines([zapped]) == ["example.com##div.ad"], "\(Boost.zapFilterLines([zapped]))")
        precondition(zapped.compiledCSS == "div.ad { display: none !important; }")
        zapped.isEnabled = false
        precondition(Boost.zapFilterLines([zapped]).isEmpty)

        // Imported CSS cannot reach the network, and a script stays off.
        let hostile = Boost(host: "a.com", css: "@import 'https://x/y.css'; a{background:URL( https://x/p.png )} b{background:u\\72l(https://x)}", zaps: ["#player-ads", "p.x"], script: "1", scriptEnabled: true)
        let imported = try BoostBundle.parse(BoostBundle.export([hostile])!)[0]
        let lower = imported.css.lowercased()
        precondition(!lower.contains("@import") && !lower.contains("url(") && !lower.contains("\\"), imported.css)
        precondition(imported.zaps == ["p.x"] && !imported.scriptEnabled)

        // Storage: a file round trip, and a legacy blob migrates once and the file wins afterwards.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boost-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Boosts.json")
        precondition(BoostStore.read(from: file, legacy: nil).isEmpty && !FileManager.default.fileExists(atPath: file.path))
        let keep = Boost(name: "k", host: "k.com", brightness: 0.7, zaps: ["p"])
        BoostStore.write([keep], to: file)
        precondition(BoostStore.read(from: file, legacy: nil) == [keep])
        let legacyBlob = try JSONEncoder().encode([Boost(name: "old", host: "old.com")])
        precondition(BoostStore.read(from: file, legacy: legacyBlob) == [keep], "an existing file beats the legacy blob")
        let fresh = dir.appendingPathComponent("Fresh.json")
        let migrated = BoostStore.read(from: fresh, legacy: legacyBlob)
        precondition(migrated.count == 1 && migrated[0].host == "old.com" && FileManager.default.fileExists(atPath: fresh.path))
        precondition(BoostStore.read(from: fresh, legacy: Data(#"[{"host":"other.com"}]"#.utf8)) == migrated, "migrates once")
        // An undecodable file is kept as .bak before anything overwrites it.
        let broken = dir.appendingPathComponent("Broken.json")
        try Data("not json".utf8).write(to: broken)
        precondition(BoostStore.read(from: broken, legacy: nil).isEmpty)
        precondition((try? Data(contentsOf: broken.appendingPathExtension("bak"))) == Data("not json".utf8))
        let store = BoostStore(fileURL: fresh)
        store.save([keep]); store.flush()
        precondition(BoostStore.read(from: fresh, legacy: nil) == [keep], "flush waits for the write")

        // Bait rules are refused in any spelling, in zaps and in raw CSS.
        for bait in ["#PLAYER-ADS", "div.player-ads", "[id*=\"player-ads\"]", "[class~='Player-Ads']"] {
            precondition(!Boost.isAllowedZap(bait), bait)
        }
        let rawCSS = "a{color:red} #Player-Ads{display:none} [class*=player-ads]{x:y} b{color:blue}"
        precondition(Boost.removingBaitRules(rawCSS) == "a{color:red} b{color:blue}", Boost.removingBaitRules(rawCSS))
        precondition(Boost.removingBaitRules("a{}") == "a{}")
        precondition(!Boost(host: "x.com", css: rawCSS).compiledCSS.lowercased().contains("player-ads"))
        let layer = Boost(host: "x.com", darkPage: true).compiledCSS
        precondition(layer.contains("position: fixed !important") && layer.contains("z-index: 2147483646 !important")
            && layer.contains("pointer-events: none !important") && layer.contains(":not(:fullscreen"), layer)
        precondition(Boost.css(for: URL(string: "https://x.com/")!, in: [Boost(host: "x.com", css: "a{b:c}")]) == "a{b:c}")
        print("BoostCheck ok")
    }
}
