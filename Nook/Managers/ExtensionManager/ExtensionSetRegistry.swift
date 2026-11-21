// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionSetRegistry.swift
//  Nook
//
//  Which extension set a page, window or profile runs, and the ExtensionManager for each set.
//  A set is chosen per profile (`NookSettingsService.extensionSets`). A website data store must
//  never have pages in two sets: WebKit serves one controller per WebContent process.
//

import Foundation
import os
import WebKit
import NookSettings
import NookWeb

@MainActor
final class ExtensionSetRegistry {
    static let shared = ExtensionSetRegistry()

    weak var browserManager: BrowserManager?
    private var managers: [UUID: ExtensionManager] = [:]

    var defaultSetID: UUID { ExtensionManager.shared.setID }

    /// The default set first, then any other set something has opened.
    var loadedManagers: [ExtensionManager] {
        [ExtensionManager.shared] + managers.values.sorted { $0.setID.uuidString < $1.setID.uuidString }
    }

    func manager(forSet id: UUID) -> ExtensionManager {
        if id == defaultSetID {
            ExtensionManager.shared.setIdle(false)
            return .shared
        }
        if let existing = managers[id] { return existing }
        let created = ExtensionManager(setID: id)
        managers[id] = created
        if let browserManager { created.attach(browserManager: browserManager) }
        return created
    }

    /// Starts every set a profile uses before any page loads, so its content scripts are ready,
    /// and deletes the sets a private window was still running when their profile went.
    func loadSetsInUse() {
        guard let settings = browserManager?.nookSettings else { return }
        let sets = settings.extensionSets
        let waiting = pendingDeletion.filter { !sets.membership.values.contains($0) && !sets.dormant.values.joined().contains($0) }
        if !pendingDeletion.isEmpty { pendingDeletion = [] }
        deleteSets(waiting)
        for id in Set(sets.membership.values) { _ = manager(forSet: id) }
        idleDefaultSetIfUnused()
    }

    // MARK: - Resolving a set

    /// False until someone makes a Separate profile. Nothing below reads the tab tree before
    /// that, so a view that asks for a set does not run again on every tab change.
    private var hasOtherSets: Bool {
        !managers.isEmpty || browserManager?.nookSettings?.extensionSets.membership.isEmpty == false
    }

    func setID(forProfile profile: UUID?) -> UUID {
        guard let profile, let settings = browserManager?.nookSettings else { return defaultSetID }
        return settings.extensionSets.setID(forProfile: profile, defaultSet: defaultSetID)
    }

    func setID(forSpace spaceID: UUID?) -> UUID {
        guard hasOtherSets else { return defaultSetID }
        return setID(forProfile: spaceID.flatMap { browserManager?.tabs.tree.dataStoreID(for: $0) })
    }

    /// A window runs the set of the space it shows. A private window keeps the set of the window
    /// it was opened from for as long as that set is loaded, whatever its profile does meanwhile.
    func setID(for window: BrowserWindowState) -> UUID {
        guard window.isIncognito || window.privateTree != nil else { return setID(forSpace: window.spaceID) }
        guard let set = window.privateExtensionSetID, managers[set] != nil else { return defaultSetID }
        return set
    }

    /// Sets a private window still runs. They stay loaded, and are not deleted, until it closes.
    private var privateWindowSets: Set<UUID> {
        Set(browserManager?.windowRegistry?.allWindows.compactMap(\.privateExtensionSetID) ?? [])
    }

    /// An item's set comes from its space, and a private item's from its window.
    func setID(forItem itemID: UUID) -> UUID {
        guard hasOtherSets, let tabs = browserManager?.tabs else { return defaultSetID }
        if let space = tabs.tree.spaceID(of: itemID) { return setID(forSpace: space) }
        return tabs.privateWindows.first { $0.privateTree?.item(itemID) != nil }.map(setID(for:)) ?? defaultSetID
    }

    /// The set a page's web view is built with; nil for an Agent page, which gets no extensions.
    func setID(for session: PageSession) -> UUID? {
        if session.isAgentPage { return nil }
        if let detached = session.detachedProfile {
            if detached.isEphemeral { return session.detachedWindow.map(setID(for:)) ?? defaultSetID }
            return setID(forProfile: detached.id)
        }
        return setID(forItem: session.itemID)
    }

    func manager(for session: PageSession) -> ExtensionManager? {
        setID(for: session).map { manager(forSet: $0) }
    }

    func manager(for window: BrowserWindowState) -> ExtensionManager {
        manager(forSet: setID(for: window))
    }

    // MARK: - Changing sets

    /// Profiles whose set changed: their open pages are unloaded, so each comes back with the
    /// new set's controller, and windows showing their spaces move to the new set.
    func profilesChangedSet(_ profiles: Set<UUID>) {
        guard let bm = browserManager, !profiles.isEmpty else { return }
        // Peek and mini window pages cannot reload in place, so they close.
        for manager in loadedManagers { manager.closeDetachedPages(ofProfiles: profiles) }
        for session in bm.tabs.sessions where !session.isUnloaded {
            guard let space = bm.tabs.tree.spaceID(of: session.itemID),
                  let store = bm.tabs.tree.dataStoreID(for: space), profiles.contains(store) else { continue }
            session.unload()
            if bm.tabs.isVisibleInAnyWindow(session.itemID) { session.loadWebViewIfNeeded() }
        }
        bm.windowRegistry?.allWindows.forEach(windowSpaceChanged)
        for window in bm.tabs.regularWindows { window.refreshCompositor() }
    }

    /// A window that now shows a space in another set leaves the old set's view of windows and
    /// joins the new one's.
    func windowSpaceChanged(_ window: BrowserWindowState) {
        closeStrayTabs()
        for manager in loadedManagers { manager.windowSetMayHaveChanged(window) }
        _ = manager(for: window).windowAdapter(for: window)
    }

    /// Tabs that left a set, because their profile changed set or they moved to a space of
    /// another profile, are closed to that set's extensions. Free while one set is loaded.
    func closeStrayTabs() {
        guard !managers.isEmpty else { return }
        for manager in loadedManagers { manager.closeTabsOfOtherSets() }
    }

    /// Changes a profile's set through `change`, then deletes what became garbage and moves the
    /// profile's pages and windows to the new set.
    func update(_ change: (inout ExtensionSets, UUID) -> [UUID], profile: UUID) {
        guard let settings = browserManager?.nookSettings else { return }
        let before = setID(forProfile: profile)
        var sets = settings.extensionSets
        let garbage = change(&sets, defaultSetID)
        settings.extensionSets = sets
        if setID(forProfile: profile) != before { profilesChangedSet([profile]) }
        deleteSets(garbage)
        unloadIdleSets()
    }

    func profileDeleted(_ profile: UUID) {
        update({ sets, d in sets.profileDeleted(profile, defaultSet: d) }, profile: profile)
    }

    /// A space split off into a profile of its own keeps the extension set it had.
    func profileSplit(_ new: UUID, from old: UUID) {
        let set = setID(forProfile: old)
        guard set != defaultSetID, let profiles = browserManager?.tabs.profiles.map(\.id) else { return }
        update({ sets, d in sets.sync(new, with: set, profiles: profiles, defaultSet: d) }, profile: new)
    }

    /// A set no profile runs any more stops running. Its data stays for Separate to bring back.
    private func unloadIdleSets() {
        guard let settings = browserManager?.nookSettings else { return }
        let running = Set(settings.extensionSets.membership.values).union(privateWindowSets)
        for id in Array(managers.keys) where !running.contains(id) { managers.removeValue(forKey: id)?.tearDown() }
        idleDefaultSetIfUnused()
    }

    /// The default set loads extensions only while a profile or a private window runs it. Its
    /// manager is a singleton, so it idles instead of going; `manager(forSet:)` wakes it.
    private func idleDefaultSetIfUnused() {
        guard let bm = browserManager, let sets = bm.nookSettings?.extensionSets else { return }
        // With no Separate profile every profile is in the default set, so one-set users stop here.
        let used = sets.membership.isEmpty
            || sets.choices(profiles: bm.tabs.profiles.map(\.id), defaultSet: defaultSetID).contains { $0.set == defaultSetID }
        ExtensionManager.shared.setIdle(!used && !privateWindowSets.contains(defaultSetID))
    }

    /// The pin list is shared by every set, so an id leaves it only when no loaded set still has the extension.
    func unpinIfUninstalled(_ extensionID: String) {
        guard !loadedManagers.contains(where: { $0.installedExtensions.contains { $0.id == extensionID } }) else { return }
        browserManager?.nookSettings?.pinnedExtensionIDs.removeAll { $0 == extensionID }
    }

    private static let pendingDeletionKey = "Nook.Extensions.SetsToDelete"
    private var pendingDeletion: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: Self.pendingDeletionKey) ?? []).compactMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: Self.pendingDeletionKey) }
    }

    /// Removes sets no profile uses or remembers: controllers, packages and extension data.
    func deleteSets(_ ids: [UUID]) {
        let held = privateWindowSets
        for id in ids where id != defaultSetID {
            // ponytail: a set a private window still runs goes at the next launch, not when the window closes.
            if held.contains(id) { pendingDeletion.append(id); continue }
            let manager = managers.removeValue(forKey: id)
            let storage = manager?.storageRoot ?? Self.storageFolder(id)
            manager?.tearDown()
            try? FileManager.default.removeItem(at: ExtensionManager.setDirectory(id))
            if let storage { try? FileManager.default.removeItem(at: storage) }
            UserDefaults.standard.removeObject(forKey: "Nook.Extensions.LastUpdateCheck.\(id.uuidString)")
            UserDefaults.standard.removeObject(forKey: ExtensionCompatSidePanel.behaviorKey(set: id))
            Task { @MainActor in
                // Emptied first: WebKit refuses to remove a store it still holds, and then only
                // an empty folder stays behind.
                await WKWebsiteDataStore(forIdentifier: id)
                    .removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                } catch {
                    ExtensionManager.logger.error("Extension set \(id.uuidString, privacy: .public) store not removed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Where WebKit keeps the extension storage of a controller that is not loaded to ask.
    private static func storageFolder(_ id: UUID) -> URL? {
        guard let bundle = Bundle.main.bundleIdentifier,
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        return library.appendingPathComponent("WebKit/\(bundle)/WebExtensions/\(id.uuidString)")
    }
}
