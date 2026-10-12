// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

/// A pinned folder whose tabs follow a source.
struct LiveFolderTests {
    private func pr(_ n: Int, _ title: String? = nil) -> LivePage {
        LivePage(url: URL(string: "https://example.com/pull/\(n)")!, title: title ?? "PR \(n)")
    }

    private func owns(_ url: URL) -> Bool { url.path.hasPrefix("/pull/") }

    private func liveFolder(_ f: inout Fixture) throws -> UUID {
        let id = UUID()
        try f.tree.createFolder(id: id, title: "Pull Requests", in: .pinned(spaceID: f.spaceA), after: nil, live: .githubPulls, now: fixedNow)
        return id
    }

    @Test func addsInSourceOrderThenFollowsTheSource() throws {
        var f = Fixture()
        let folder = try liveFolder(&f)
        let parent = Parent.folder(itemID: folder)
        try f.tree.reconcileLive(folder, with: [pr(3), pr(1)], owns: owns, now: fixedNow)
        #expect(f.titles(parent) == ["PR 3", "PR 1"])

        // 1 merged, 3 was retitled, 7 is new and goes on top.
        try f.tree.reconcileLive(folder, with: [pr(7), pr(3, "renamed")], owns: owns, now: fixedNow)
        #expect(f.titles(parent) == ["PR 7", "renamed"])
        checkInvariants(f.tree)

        // The same answer again changes nothing.
        #expect(try f.tree.reconcileLive(folder, with: [pr(7), pr(3, "renamed")], owns: owns, now: fixedNow).isEmpty)
    }

    @Test func keepsOpenPagesDismissedStayOutAndOtherTabsAreLeftAlone() throws {
        var f = Fixture()
        let folder = try liveFolder(&f)
        let parent = Parent.folder(itemID: folder)
        try f.tree.reconcileLive(folder, with: [pr(1), pr(2)], owns: owns, now: fixedNow)
        let open = f.tree.children(of: parent)[0].id
        let own = f.tab("notes", in: parent)

        try f.tree.reconcileLive(folder, with: [pr(5), pr(6)], dismissed: [pr(6).url], keeping: [open], owns: owns, now: fixedNow)
        #expect(f.titles(parent) == ["PR 5", "PR 1", "notes"])
        #expect(f.tree.item(own) != nil)

        // Its page closed, so the next pass takes it.
        try f.tree.reconcileLive(folder, with: [pr(5)], owns: owns, now: fixedNow)
        #expect(f.titles(parent) == ["PR 5", "notes"])
    }

    @Test func removesASecondTabForOnePage() throws {
        var f = Fixture()
        let folder = try liveFolder(&f)
        let parent = Parent.folder(itemID: folder)
        for _ in 0..<2 {
            try f.tree.createTab(url: pr(1).url, title: "PR 1", in: parent, after: nil, now: fixedNow)
        }
        try f.tree.reconcileLive(folder, with: [pr(1), pr(1)], owns: owns, now: fixedNow)
        #expect(f.titles(parent) == ["PR 1"])
    }

    @Test func sourceSurvivesCodingAndOldFilesDecode() throws {
        var f = Fixture()
        let folder = try liveFolder(&f)
        let item = try #require(f.tree.item(folder))
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(Item.self, from: data).live == .githubPulls)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["live"] = nil
        let old = try JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.live == nil)
        json["live"] = "somethingNewer"
        let newer = try JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(newer.live?.rawValue == "somethingNewer")

        // device.json from before live folders has no liveDismissed key.
        var device = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceState())) as! [String: Any]
        device["liveDismissed"] = nil
        #expect(try JSONDecoder().decode(DeviceState.self, from: JSONSerialization.data(withJSONObject: device)).liveDismissed == nil)
    }
}
