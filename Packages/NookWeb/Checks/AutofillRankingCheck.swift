// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  AutofillRankingCheck.swift
//  Nook
//
//  Omnibox autofill ranking check. NookWeb has no test target, so this compiles the shipped
//  source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/AutofillRanking.swift \
//           Packages/NookWeb/Checks/AutofillRankingCheck.swift -o /tmp/autofill-check && /tmp/autofill-check
//
//  Created by Bain Gurley on 19/09/2026.
//

import Foundation

@main
struct AutofillRankingCheck {
    static func day(_ offset: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400) }

    static func main() {
        // Ranks by summed visits, so a host reached through many pages beats one popular deep page.
        let feed = AutofillRanking.aggregate([
            (url: "https://www.facebook.com/marketplace", visitCount: 3, lastVisited: day(1)),
            (url: "https://www.facebook.com/", visitCount: 4, lastVisited: day(2)),
            (url: "https://faceboard.io/dashboard", visitCount: 6, lastVisited: day(3))
        ])
        precondition(feed["facebook.com"] == HostStat(visits: 7, lastVisited: day(2)))
        precondition(AutofillRanking.bestHost(in: feed, prefix: "facebo", minVisits: 2) == "facebook.com")

        // The `www.` prefix is stripped for both matching and the returned host.
        precondition(AutofillRanking.host(for: "https://www.facebook.com/x") == "facebook.com")
        precondition(AutofillRanking.bestHost(in: feed, prefix: "www.f", minVisits: 2) == nil)
        precondition(AutofillRanking.bestHost(in: feed, prefix: "faceboa", minVisits: 2) == "faceboard.io")

        // A tie on visits goes to the host visited most recently.
        let tied = AutofillRanking.aggregate([
            (url: "https://old.example.com/", visitCount: 5, lastVisited: day(1)),
            (url: "https://new.example.org/", visitCount: 5, lastVisited: day(9))
        ])
        precondition(AutofillRanking.bestHost(in: tied, prefix: "ne", minVisits: 2) == "new.example.org")

        // A host below the visit floor is never offered, so one stray visit cannot hijack Return.
        let stray = AutofillRanking.aggregate([(url: "https://strangesite.com/", visitCount: 1, lastVisited: day(4))])
        precondition(AutofillRanking.bestHost(in: stray, prefix: "stra", minVisits: 2) == nil)
        precondition(AutofillRanking.bestHost(in: stray, prefix: "stra", minVisits: 1) == "strangesite.com")

        // Guards: one character, a typed path, and a multi-word search never autofill.
        precondition(AutofillRanking.bestHost(in: feed, prefix: "f", minVisits: 1) == nil)
        precondition(AutofillRanking.bestHost(in: feed, prefix: "facebook.com/mar", minVisits: 1) == nil)
        precondition(AutofillRanking.bestHost(in: feed, prefix: "face book", minVisits: 1) == nil)

        // Entries whose URL has no host are skipped rather than crashing the scan.
        precondition(AutofillRanking.host(for: "not a url") == nil)
        precondition(AutofillRanking.aggregate([(url: "not a url", visitCount: 9, lastVisited: day(1))]).isEmpty)

        // A visit folded into a built index counts the same as one present at build time, which is
        // what lets addVisits keep the index rather than drop it.
        var live = stray
        AutofillRanking.add(url: "https://strangesite.com/more", visits: 1, at: day(6), to: &live)
        precondition(live["strangesite.com"] == HostStat(visits: 2, lastVisited: day(6)))
        precondition(AutofillRanking.bestHost(in: live, prefix: "stra", minVisits: 2) == "strangesite.com")

        // An older visit arriving late, as an import can, must not drag lastVisited backwards.
        AutofillRanking.add(url: "https://strangesite.com/old", visits: 1, at: day(2), to: &live)
        precondition(live["strangesite.com"] == HostStat(visits: 3, lastVisited: day(6)))

        print("AutofillRanking: all checks passed")
    }
}
