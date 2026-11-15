// Licensed under GPL-3.0. See LICENSE.
//
//  SiteMediaChoiceCheck.swift
//  Nook
//
//  A site's Auto-Play and sidebar video choices: which site a choice applies to, what a site with
//  none gets, and when a record is dropped. NookSettings has no test target, so this compiles the
//  shipped source directly:
//
//    swiftc Packages/NookSettings/Sources/NookSettings/SitePermission.swift \
//           Packages/NookSettings/Checks/SiteMediaChoiceCheck.swift -o /tmp/site-media-check && /tmp/site-media-check
//

import Foundation

@main
struct SiteMediaChoiceCheck {
    static func main() {
        var sites: [String: SitePermissionRecord] = [:]

        // A site with no choice: every site may auto-play, and the sidebar video follows Settings.
        precondition(sites.autoplay(for: "example.com") == .allowAll)
        precondition(sites.autoplay(for: nil) == .allowAll)
        precondition(sites.autoPictureInPicture(for: "example.com", fallback: true))
        precondition(!sites.autoPictureInPicture(for: "example.com", fallback: false))
        precondition(!sites.autoPictureInPicture(for: nil, fallback: false))

        // A choice is kept for the host, with or without www and in any case, and for no other host.
        sites.update("www.Example.com") { $0.autoplay = .never }
        precondition(sites.autoplay(for: "example.com") == .never && sites.autoplay(for: "WWW.EXAMPLE.COM") == .never)
        precondition(sites.autoplay(for: "m.example.com") == .allowAll && sites.autoplay(for: "example.org") == .allowAll)
        precondition(sites.keys.sorted() == ["example.com"])

        // The sidebar video choice overrides Settings either way.
        sites.update("example.com") { $0.autoPictureInPicture = false }
        precondition(!sites.autoPictureInPicture(for: "www.example.com", fallback: true))
        sites.update("video.test") { $0.autoPictureInPicture = true }
        precondition(sites.autoPictureInPicture(for: "video.test", fallback: false))

        // Clearing one choice keeps the others; a record with nothing left is dropped.
        sites.update("example.com") { $0.policies[.camera] = .block }
        sites.update("example.com") { $0.autoplay = nil }
        precondition(sites["example.com"]?.policies[.camera] == .block && sites["example.com"]?.autoPictureInPicture == false)
        sites.update("example.com") { $0.policies[.camera] = nil }
        precondition(sites["example.com"] != nil, "the sidebar video choice alone keeps the record")
        sites.update("example.com") { $0.autoPictureInPicture = nil }
        precondition(sites["example.com"] == nil)

        // What 1.6.0 saved still reads, with no choice; what this build saves reads back.
        let old = try! JSONEncoder().encode(["a.com": OldRecord(host: "a.com", policies: [.microphone: .allow])])
        let read = try! JSONDecoder().decode([String: SitePermissionRecord].self, from: old)
        precondition(read["a.com"]?.policies[.microphone] == .allow && read.autoplay(for: "a.com") == .allowAll)
        sites.update("b.com") { $0.autoplay = .stopMediaWithSound }
        let saved = try! JSONEncoder().encode(sites)
        precondition(try! JSONDecoder().decode([String: SitePermissionRecord].self, from: saved) == sites)
        // An older build reads the new record too: it ignores the fields it does not know.
        precondition(try! JSONDecoder().decode([String: OldRecord].self, from: saved)["b.com"]?.host == "b.com")

        precondition(SiteAutoplay.allCases.map(\.label) == ["Allow All Auto-Play", "Stop Media with Sound", "Never Auto-Play"])
        print("SiteMediaChoiceCheck passed")
    }
}

/// The record as 1.6.0 wrote it.
private struct OldRecord: Codable {
    var host: String
    var policies: [SitePermission: SitePermissionPolicy]
}
