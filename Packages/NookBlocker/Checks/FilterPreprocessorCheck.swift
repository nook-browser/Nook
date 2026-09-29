// Licensed under GPL-3.0. See LICENSE.
//
//  FilterPreprocessorCheck.swift
//  Nook
//
//  uBO's `!#if` blocks load only for the environment Nook reports.
//  swiftc Sources/NookBlocker/FilterPreprocessor.swift Checks/FilterPreprocessorCheck.swift -o /tmp/pp && /tmp/pp
//

import Foundation

@main
struct FilterPreprocessorCheck {
    static func main() {
        // The shape of uBO quick-fixes' YouTube block: a Firefox-only json-prune nested three deep.
        let quickFixes = """
        !#if !env_mv3
        !#if !cap_html_filtering
        !#if env_firefox
        youtube.com##+js(json-prune, adPlacements playerAds)
        !#endif
        !#endif
        !#endif
        !#if !cap_html_filtering
        www.youtube.com##+js(trusted-replace-fetch-response, '"adSlots"', '"no_ads"', player?)
        !#else
        ||www.youtube.com/youtubei/v1/player?$xhr,1p,replace=/"adSlots"/"no_ads"/
        !#endif
        !#if env_safari
        /^https:\\/\\/[a-f0-9][a-f0-9]\\./$doc
        !#else
        /^https:\\/\\/[a-f0-9]{2}\\./$doc
        !#endif
        ||always.example^
        """
        let kept = FilterPreprocessor.apply(quickFixes).split(separator: "\n").map(String.init)
        precondition(kept == [
            "www.youtube.com##+js(trusted-replace-fetch-response, '\"adSlots\"', '\"no_ads\"', player?)",
            "/^https:\\/\\/[a-f0-9][a-f0-9]\\./$doc",
            "||always.example^",
        ], "unexpected lines: \(kept)")

        precondition(FilterPreprocessor.evaluate("ext_ublock && !ext_ubol"))
        precondition(!FilterPreprocessor.evaluate("env_chromium || env_firefox"))
        precondition(FilterPreprocessor.evaluate("env_mobile || env_safari"))
        precondition(!FilterPreprocessor.evaluate("unknown_token"))
        precondition(!FilterPreprocessor.evaluate("!(env_safari)"))

        let plain = "||a.example^\n||b.example^"
        precondition(FilterPreprocessor.apply(plain) == plain)
        print("FilterPreprocessorCheck passed")
    }
}
