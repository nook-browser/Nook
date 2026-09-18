// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import Foundation
import Testing
@testable import NookTabsCore

/// The format-1 files had profiles above spaces. These check that a real pair survives the merge.
struct ProfileMergeTests {
    let personal = UUID()
    let work = UUID()
    let personalSpace = UUID()
    let workSpace = UUID()
    let workSecondSpace = UUID()
    let favorite = UUID()
    let pinned = UUID()
    let deviceTab = UUID()
    let windowID = UUID()

    private func profile(_ id: UUID, _ name: String, _ order: String) -> [String: Any] {
        ["id": id.uuidString, "name": name, "icon": "person", "order": order, "modifiedAt": 1_800_000_000.0]
    }

    private func space(_ id: UUID, _ profileID: UUID, _ name: String, _ order: String) -> [String: Any] {
        ["id": id.uuidString, "profileID": profileID.uuidString, "name": name, "icon": "house",
         "accentHex": "#112233", "order": order, "modifiedAt": 1_800_000_000.0]
    }

    private func tab(_ id: UUID, _ parent: [String: Any], _ title: String) -> [String: Any] {
        ["id": id.uuidString, "parent": parent, "order": "V", "modifiedAt": 1_800_000_000.0,
         "kind": ["tab": ["url": "https://example.com/\(title)", "pageTitle": title]]]
    }

    /// Two profiles with one space each, the shape a single-space-per-profile user has.
    private func legacyFiles() -> (structure: Data, device: Data) {
        let structure: [String: Any] = [
            "formatVersion": 1,
            "profiles": [profile(personal, "Personal", "V"), profile(work, "Work", "k")],
            "spaces": [space(personalSpace, personal, "Personal", "V"),
                       space(workSpace, work, "Work", "V"),
                       space(workSecondSpace, work, "Work Extra", "k")],
            "items": [tab(favorite, ["favorites": ["profileID": personal.uuidString]], "fav"),
                      tab(pinned, ["pinned": ["spaceID": personalSpace.uuidString]], "pin")]
        ]
        let device: [String: Any] = [
            "formatVersion": 1,
            "items": [tab(deviceTab, ["tabs": ["spaceID": personalSpace.uuidString]], "device")],
            "state": [
                "openFolders": [],
                "openPages": [],
                "firstLaunchCompleted": true,
                "closed": [["items": [tab(UUID(), ["tabs": ["spaceID": workSpace.uuidString]], "gone")],
                            "section": ["tabs": ["spaceID": workSpace.uuidString]],
                            "closedAt": 1_800_000_000.0]],
                "windows": [["id": windowID.uuidString,
                             "spaceID": personalSpace.uuidString,
                             "selectedItemBySpace": [personalSpace.uuidString, deviceTab.uuidString]]]
            ]
        ]
        return (try! JSONSerialization.data(withJSONObject: structure),
                try! JSONSerialization.data(withJSONObject: device))
    }

    private func write(_ files: (structure: Data, device: Data)) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! files.structure.write(to: dir.appendingPathComponent("structure.json"))
        try! files.device.write(to: dir.appendingPathComponent("device.json"))
        return dir
    }

    /// The merged space keeps the profile's id, so its website data store keeps its cookies.
    @Test func firstSpaceOfEachProfileTakesTheProfileID() {
        let loaded = TabStore(directory: write(legacyFiles())).load(now: fixedNow)
        #expect(loaded.outcome == .loaded)
        let ids = loaded.tree.orderedSpaces.map(\.id)
        #expect(ids == [personal, work, workSecondSpace])
        // The merged space keeps the space's own name and accent, not the profile's.
        #expect(loaded.tree.space(personal)?.name == "Personal")
        #expect(loaded.tree.space(work)?.name == "Work")
        #expect(loaded.tree.space(personal)?.accentHex == "#112233")
        #expect(loaded.migratedSpaceIDs[personalSpace] == personal)
        #expect(loaded.migratedSpaceIDs[workSpace] == work)
        #expect(loaded.migratedSpaceIDs[workSecondSpace] == workSecondSpace)
        checkInvariants(loaded.tree)
    }

    @Test func itemsFollowTheirSectionToTheMergedSpace() {
        let loaded = TabStore(directory: write(legacyFiles())).load(now: fixedNow)
        #expect(loaded.tree.item(favorite)?.parent == .favorites(spaceID: personal))
        #expect(loaded.tree.item(pinned)?.parent == .pinned(spaceID: personal))
        #expect(loaded.tree.item(deviceTab)?.parent == .tabs(spaceID: personal))
        #expect(loaded.tree.scope(of: favorite) == .synced)
        #expect(loaded.tree.scope(of: deviceTab) == .device)
        #expect(loaded.tree.item(favorite)?.pageTitle == "fav")
    }

    @Test func windowsAndClosedEntriesFollowTheMergedSpace() {
        let loaded = TabStore(directory: write(legacyFiles())).load(now: fixedNow)
        #expect(loaded.device.windows.first?.spaceID == personal)
        #expect(loaded.device.windows.first?.selectedItemBySpace == [personal: deviceTab])
        #expect(loaded.device.closed.first?.section == .tabs(spaceID: work))
        #expect(loaded.device.closed.first?.items.first?.parent == .tabs(spaceID: work))
    }

    /// A second launch reads the format-2 files it wrote and migrates nothing.
    @Test func migrationRunsOnceAndSurvivesASaveCycle() throws {
        let dir = write(legacyFiles())
        let store = TabStore(directory: dir)
        let loaded = store.load(now: fixedNow)
        store.save(loaded.tree, loaded.device)
        store.flush()

        let reloaded = TabStore(directory: dir).load(now: fixedNow)
        #expect(reloaded.migratedSpaceIDs.isEmpty)
        #expect(reloaded.tree.orderedSpaces.map(\.id) == [personal, work, workSecondSpace])
        #expect(reloaded.tree.item(favorite)?.parent == .favorites(spaceID: personal))
        #expect(reloaded.tree.item(deviceTab)?.parent == .tabs(spaceID: personal))
        // The untouched format-1 files are kept apart from the daily backup.
        let preMerge = dir.appendingPathComponent("Backups/\(TabStore.dayStamp(fixedNow))-pre-merge/structure.json")
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: preMerge)) as! [String: Any]
        #expect(original["profiles"] != nil)
        #expect(original["formatVersion"] as? Int == 1)
    }

    /// A profile that lost its spaces still becomes one, so its favorites have somewhere to live.
    @Test func profileWithoutSpacesBecomesASpace() {
        let structure: [String: Any] = [
            "formatVersion": 1,
            "profiles": [profile(personal, "Personal", "V")],
            "spaces": [],
            "items": [tab(favorite, ["favorites": ["profileID": personal.uuidString]], "fav")]
        ]
        let dir = write((try! JSONSerialization.data(withJSONObject: structure), Data()))
        let loaded = TabStore(directory: dir).load(now: fixedNow)
        #expect(loaded.tree.orderedSpaces.map(\.id) == [personal])
        #expect(loaded.tree.space(personal)?.name == "Personal")
        #expect(loaded.tree.favorites(of: personal).map(\.id) == [favorite])
        checkInvariants(loaded.tree)
    }

    @Test func unreadableFormatOneFileIsNotMistakenForFormatTwo() {
        let dir = write((Data("{\"formatVersion\":1,\"spaces\":[]}".utf8), Data()))
        guard case .readOnly = TabStore(directory: dir).load(now: fixedNow).outcome else {
            Issue.record("a format-1 file with nothing to migrate must not load")
            return
        }
    }
}
