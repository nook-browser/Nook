//
//  TabsController+Intents.swift
//  Nook
//
//  Every user-facing change to tabs, folders, spaces, profiles and window selection.
//

import AppKit
import NookTabsCore
import WebKit

extension TabsController {
    // MARK: - Open

    /// Creates a tab for `url` at the top of `parent` (default: the window's tabs section).
    /// `.newTab` selects it, `.background` leaves selection alone and loads nothing,
    /// `.replaceCurrent` loads `url` in the selected page.
    @discardableResult
    func open(url: URL, in window: BrowserWindowState, placement: Placement, parent: Parent? = nil) -> UUID? {
        if placement == .replaceCurrent, let selected = window.selectedItemID, let session = ensureSession(for: selected) {
            session.load(url)
            select(selected, in: window)
            return selected
        }
        guard let target = parent ?? window.spaceID.map({ Parent.tabs(spaceID: $0) }) else { return nil }
        let id = UUID()
        let created = perform(owner(of: window), "open") {
            try $0.createTab(id: id, url: url, title: url.host ?? url.absoluteString, in: target, after: nil)
        }
        guard created != nil else { return nil }
        if placement != .background { select(id, in: window) }
        return id
    }

    /// Wraps a web view created elsewhere (Peek, mini window) in a new item and session.
    @discardableResult
    func adopt(webView: WKWebView, url: URL, title: String, in window: BrowserWindowState, placement: Placement) -> UUID? {
        let owner = owner(of: window)
        let replaced = placement == .replaceCurrent ? window.selectedItemID : nil
        let source = tree(owner)
        let target: Parent
        var after: UUID? = nil
        if let replaced, let item = source.item(replaced), source.scope(of: replaced) == .device {
            target = item.parent
            after = replaced
        } else if let spaceID = window.spaceID {
            target = .tabs(spaceID: spaceID)
        } else {
            return nil
        }
        let id = UUID()
        guard perform(owner, "adopt", { try $0.createTab(id: id, url: url, title: title, in: target, after: after) }) != nil else {
            return nil
        }
        let session = PageSession(
            itemID: id, url: url, title: title, isPrivate: window.privateTree != nil,
            controller: self, browserManager: browserManager, adoptedWebView: webView)
        register(session, in: window)
        if placement != .background { select(id, in: window) }
        if let replaced, after == replaced { close(replaced) }
        return id
    }

    /// A WebKit-created popup from `opener`: a new selected tab in the opener's window whose
    /// session owns `webView`. WebKit drives the popup's first navigation.
    @discardableResult
    func adoptPopup(webView: FocusableWKWebView, url: URL?, opener: PageSession) -> UUID? {
        guard let window = window(for: opener), let spaceID = window.spaceID else { return nil }
        let id = UUID()
        let pageURL = url ?? URL(string: "about:blank")!
        guard perform(owner(of: window), "popup", {
            try $0.createTab(id: id, url: pageURL, title: "New Tab", in: .tabs(spaceID: spaceID), after: nil)
        }) != nil else { return nil }
        let session = PageSession(
            itemID: id, url: pageURL, title: "New Tab", isPrivate: window.privateTree != nil,
            controller: self, browserManager: browserManager)
        session.isPopupHost = true
        register(session, in: window)
        session.installPopupWebView(webView)
        if let url, url.scheme != nil, url.absoluteString != "about:blank" {
            session.load(url)
        }
        // Select only after the session owns its view, so selection cannot create a second one.
        select(id, in: window)
        return id
    }

    private func register(_ session: PageSession, in window: BrowserWindowState) {
        if window.privateTree != nil {
            window.privateSessions[session.itemID] = session
        } else {
            addSession(session)
        }
    }

    // MARK: - Selection

    func select(_ itemID: UUID, in window: BrowserWindowState) {
        let owner = owner(of: window)
        let source = tree(owner)
        guard let item = source.item(itemID) else { return }
        if item.isFolder {
            toggleFolder(itemID)
            return
        }
        let previous = selectedSession(in: window)
        if let spaceID = source.spaceID(of: itemID) {
            window.spaceID = spaceID
        } else if let profileID = source.profileID(of: itemID),
                  window.spaceID.flatMap({ source.space($0)?.profileID }) != profileID {
            // A favorite of another profile: show that profile's first space.
            window.spaceID = source.orderedSpaces(in: profileID).first?.id ?? window.spaceID
        }
        guard let spaceID = window.spaceID else { return }
        setProfile(source.space(spaceID)?.profileID, of: window)
        window.selectedItemBySpace[spaceID] = itemID
        var recent = window.recentItemsBySpace[spaceID, default: []]
        recent.removeAll { $0 == itemID }
        recent.append(itemID)
        window.recentItemsBySpace[spaceID] = recent.suffix(Self.recentLimit)

        if let session = ensureSession(for: itemID) {
            session.loadWebViewIfNeeded()
            session.checkMediaState()
            if session !== previous, !session.isPrivate {
                ExtensionManager.shared.notifyTabActivated(new: session, previous: previous)
            }
        }
        mirror(window)
        window.refreshCompositor()
    }

    func selectNext(in window: BrowserWindowState) {
        step(1, in: window)
    }

    func selectPrevious(in window: BrowserWindowState) {
        step(-1, in: window)
    }

    private func step(_ offset: Int, in window: BrowserWindowState) {
        let order = displayOrder(in: window)
        guard !order.isEmpty else { return }
        let current = window.selectedItemID.flatMap { order.firstIndex(of: $0) } ?? (offset > 0 ? -1 : 0)
        let next = (current + offset + order.count) % order.count
        select(order[next], in: window)
    }

    /// 0-based over `displayOrder(in:)`.
    func select(index: Int, in window: BrowserWindowState) {
        let order = displayOrder(in: window)
        guard order.indices.contains(index) else { return }
        select(order[index], in: window)
    }

    func selectLast(in window: BrowserWindowState) {
        guard let last = displayOrder(in: window).last else { return }
        select(last, in: window)
    }

    /// Shows a space; its remembered selection (or first item) becomes selected.
    func setSpace(_ spaceID: UUID, in window: BrowserWindowState) {
        let source = tree(owner(of: window))
        guard let space = source.space(spaceID) else { return }
        window.spaceID = spaceID
        setProfile(space.profileID, of: window)
        let order = displayOrder(in: window)
        if let remembered = window.selectedItemBySpace[spaceID], order.contains(remembered) {
            select(remembered, in: window)
        } else if let first = order.first {
            select(first, in: window)
        } else {
            window.selectedItemBySpace[spaceID] = nil
            mirror(window)
            window.refreshCompositor()
        }
    }

    /// A window showing another profile's space adopts that profile (data store, history, cookies).
    private func setProfile(_ profileID: UUID?, of window: BrowserWindowState) {
        guard window.profileID != profileID else { return }
        window.profileID = profileID
        browserManager?.windowProfileChanged(window)
    }

    func selectNextSpace(in window: BrowserWindowState) {
        stepSpace(1, in: window)
    }

    func selectPreviousSpace(in window: BrowserWindowState) {
        stepSpace(-1, in: window)
    }

    private func stepSpace(_ offset: Int, in window: BrowserWindowState) {
        let spaces = tree(owner(of: window)).orderedSpaces
        guard spaces.count > 1, let current = spaces.firstIndex(where: { $0.id == window.spaceID }) else { return }
        let next = current + offset
        guard spaces.indices.contains(next) else { return }
        setSpace(spaces[next].id, in: window)
    }

    // MARK: - Close

    /// A pinned or favorite tab ends its page and keeps the item. Anything in the tabs section,
    /// and any folder, is removed into the reopen history.
    func close(_ itemID: UUID) {
        guard let owner = owner(ofItem: itemID) else { return }
        let source = tree(owner)
        guard let item = source.item(itemID) else { return }
        if !item.isFolder, source.scope(of: itemID) == .synced {
            moveSelectionOff([itemID])
            endSession(itemID)
            save()
            return
        }
        remove(itemID)
    }

    /// Deletes an item and its subtree from the sidebar, pinned tabs and favorites included.
    /// Pages end; reopening the closed entry puts it back in its place.
    func remove(_ itemID: UUID) {
        guard let owner = owner(ofItem: itemID) else { return }
        let ids = tree(owner).subtree(of: itemID)
        moveSelectionOff(Set(ids))
        var closedEntry: ClosedEntry?
        let change = perform(owner, "remove") { tree in
            let result = try tree.close(itemID)
            closedEntry = result.closed
            return result.change
        }
        guard change != nil, let closedEntry else { return }
        for id in ids { endSession(id) }
        switch owner {
        case .main:
            recordClosed(closedEntry)
        case .privateWindow(let window):
            window.privateClosed.append(closedEntry)
            if window.privateClosed.count > DeviceState.closedLimit { window.privateClosed.removeFirst() }
        }
    }

    func close(_ itemIDs: [UUID]) {
        for id in itemIDs { close(id) }
    }

    func closeSelected(in window: BrowserWindowState) {
        guard let selected = window.selectedItemID else { return }
        close(selected)
    }

    /// Restores the newest closed entry and selects it. A private window reopens from its own
    /// in-memory history.
    func reopenLastClosed(in window: BrowserWindowState) {
        let owner = owner(of: window)
        let isPrivate = window.privateTree != nil
        guard let entry = isPrivate ? window.privateClosed.last : device.closed.last,
              let fallbackSpace = window.spaceID ?? tree(owner).orderedSpaces.first?.id else { return }
        guard perform(owner, "reopen", { try $0.reopen(entry, fallback: .tabs(spaceID: fallbackSpace)) }) != nil else { return }
        if isPrivate {
            window.privateClosed.removeLast()
        } else {
            dropLastClosed()
        }
        let restored = entry.items.map(\.id)
        for folder in entry.items where folder.isFolder { openFolder(folder.id) }
        if let firstTab = restored.first(where: { tree(owner).item($0)?.isFolder == false }) {
            select(firstTab, in: window)
        }
    }

    static let recentLimit = 30

    /// Before items disappear (or a pinned tab's page ends), every window selecting one returns
    /// to the item it selected before, else the next item in display order, else the previous.
    private func moveSelectionOff(_ ids: Set<UUID>) {
        for window in allWindows {
            for space in window.recentItemsBySpace.keys {
                window.recentItemsBySpace[space]?.removeAll { ids.contains($0) }
            }
            if let split = window.split, ids.contains(split.leftItemID) || ids.contains(split.rightItemID) {
                window.split = nil
            }
            guard let selected = window.selectedItemID, ids.contains(selected), let spaceID = window.spaceID else {
                for (space, item) in window.selectedItemBySpace where ids.contains(item) {
                    window.selectedItemBySpace[space] = nil
                }
                continue
            }
            let order = displayOrder(in: window)
            let index = order.firstIndex(of: selected) ?? 0
            // Recent items stay eligible inside collapsed folders; ones moved to another space do not.
            let source = tree(owner(of: window))
            // Only open tabs qualify: every tab in the tabs section, and pinned tabs or favorites
            // whose page is still open. With none left the window shows the empty space.
            let isOpen: (UUID) -> Bool = { id in
                // A pinned page left open at quit has a saved open page but no session yet.
                source.scope(of: id) == .device || self.session(for: id) != nil || self.device.openPages[id] != nil
            }
            let recent = (window.recentItemsBySpace[spaceID] ?? []).reversed().filter { id in
                guard let item = source.item(id), !item.isFolder, isOpen(id) else { return false }
                let itemSpace = source.spaceID(of: id)
                return itemSpace == spaceID || (itemSpace == nil && source.profileID(of: id) == source.space(spaceID)?.profileID)
            }
            let candidates = recent
                + order[(index + 1)...].filter { !ids.contains($0) && isOpen($0) }
                + order[..<index].reversed().filter { !ids.contains($0) && isOpen($0) }
            for (space, item) in window.selectedItemBySpace where ids.contains(item) {
                window.selectedItemBySpace[space] = nil
            }
            if let next = candidates.first {
                select(next, in: window)
            } else {
                window.selectedItemBySpace[spaceID] = nil
                mirror(window)
                window.refreshCompositor()
            }
        }
    }

    // MARK: - Move

    func move(_ itemID: UUID, to parent: Parent, after: UUID?) {
        guard let owner = owner(ofItem: itemID) else { return }
        let current = session(for: itemID)
        let wasSynced = tree(owner).scope(of: itemID) == .synced
        let currentURL = current?.url ?? (wasSynced ? device.openPages[itemID]?.url : nil)
        // Extensions see the move against the window list the tab was in.
        // ponytail: only the moved item is reported, not tabs inside a moved folder.
        let oldWindow = regularWindows.first { displayOrder(in: $0).contains(itemID) }
        let oldIndex = oldWindow.flatMap { displayOrder(in: $0).firstIndex(of: itemID) }
        guard perform(owner, "move", { try $0.move(itemID, to: parent, after: after, currentURL: currentURL) }) != nil else { return }
        guard case .main = owner else { return }
        let isSynced = tree.scope(of: itemID) == .synced
        if current != nil {
            ExtensionManager.shared.notifyTabMoved(itemID: itemID, from: oldIndex, in: oldWindow, pinnedChanged: wasSynced != isSynced)
        }
        if wasSynced, !isSynced {
            for id in tree.subtree(of: itemID) { setOpenPage(id, nil) }
        } else if !wasSynced, isSynced {
            for id in tree.subtree(of: itemID) {
                guard let page = session(for: id), tree.item(id)?.isFolder == false else { continue }
                setOpenPage(id, OpenPage(url: page.url, title: page.title))
            }
        }
        unloadPagesOnWrongDataStore(tree.subtree(of: itemID))
        for window in regularWindows { window.refreshCompositor() }
    }

    func drop(_ itemID: UUID, section: Parent, rows: [Row], index: Int, intoFolder: Bool) {
        let source = treeHolding(section)
        let target = source.dropTarget(section: section, rows: rows, index: index, intoFolder: intoFolder, dragged: itemID)
        if case .folder(let folderID) = target.parent { openFolder(folderID) }
        move(itemID, to: target.parent, after: target.after)
    }

    /// Appends to a pinned section (`.pinned`) or favorites (`.favorites`).
    func pin(_ itemID: UUID, to parent: Parent) {
        move(itemID, to: parent, after: children(of: parent).last?.id)
    }

    /// Moves a pinned tab or favorite to the top of its space's tabs section.
    func unpin(_ itemID: UUID) {
        let spaceID = self.spaceID(of: itemID)
            ?? allWindows.first(where: { $0.selectedItemID == itemID })?.spaceID
            ?? profileID(of: itemID).flatMap { spaces(inProfile: $0).first?.id }
        guard let spaceID else { return }
        move(itemID, to: .tabs(spaceID: spaceID), after: nil)
    }

    func rename(_ itemID: UUID, _ customTitle: String?) {
        guard let owner = owner(ofItem: itemID) else { return }
        perform(owner, "rename") { try $0.rename(itemID, customTitle: customTitle) }
    }

    /// A copy of a tab showing its current page: next to it in the tabs section, or at the top of
    /// the window's tabs section for pinned tabs and favorites. The copy is selected.
    @discardableResult
    func duplicate(_ itemID: UUID, in window: BrowserWindowState) -> UUID? {
        guard let owner = owner(ofItem: itemID), let item = tree(owner).item(itemID),
              case .tab(let url, let pageTitle) = item.kind else { return nil }
        let page = session(for: itemID)
        let deviceScope = tree(owner).scope(of: itemID) == .device
        guard let target = deviceScope ? item.parent : window.spaceID.map({ Parent.tabs(spaceID: $0) }) else { return nil }
        let id = UUID()
        guard perform(owner, "duplicate", {
            var change = try $0.createTab(id: id, url: page?.url ?? url, title: page?.title ?? pageTitle, in: target, after: deviceScope ? itemID : nil)
            if let customTitle = item.customTitle { change.merge(try $0.rename(id, customTitle: customTitle)) }
            return change
        }) != nil else { return nil }
        select(id, in: window)
        return id
    }

    // MARK: - Home URL

    /// Loads a synced tab's home URL in its page.
    func resetToHome(_ itemID: UUID) {
        guard let item = item(itemID), let home = item.url, let owner = owner(ofItem: itemID),
              tree(owner).scope(of: itemID) == .synced else { return }
        if let page = session(for: itemID) {
            page.load(home)
        } else if case .main = owner {
            setOpenPage(itemID, nil)
        }
    }

    /// Makes a synced tab's current page its home URL.
    func setHomeToCurrent(_ itemID: UUID) {
        guard let current = session(for: itemID)?.url ?? device.openPages[itemID]?.url else { return }
        setHome(itemID, url: current)
    }

    func setHome(_ itemID: UUID, url: URL) {
        guard let owner = owner(ofItem: itemID) else { return }
        perform(owner, "setHome") { try $0.setURL(itemID, url) }
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(title: String, in parent: Parent, after: UUID?) -> UUID? {
        let owner: TabsController.Owner?
        switch parent {
        case .favorites(let profileID): owner = self.owner(ofProfile: profileID)
        case .pinned(let spaceID), .tabs(let spaceID): owner = self.owner(ofSpace: spaceID)
        case .folder(let folderID): owner = self.owner(ofItem: folderID)
        }
        guard let owner else { return nil }
        let id = UUID()
        guard perform(owner, "createFolder", { try $0.createFolder(id: id, title: title, in: parent, after: after) }) != nil else {
            return nil
        }
        openFolder(id)
        return id
    }

    func toggleFolder(_ folderID: UUID) {
        if isOpen(folder: folderID) {
            setFolder(folderID, open: false)
        } else {
            setFolder(folderID, open: true)
        }
    }

    func setAllFolders(open: Bool, space spaceID: UUID) {
        guard let owner = owner(ofSpace: spaceID) else { return }
        let source = tree(owner)
        let roots = source.children(of: .pinned(spaceID: spaceID)) + source.children(of: .tabs(spaceID: spaceID))
        for root in roots {
            for id in source.subtree(of: root.id) where source.item(id)?.isFolder == true {
                setFolder(id, open: open)
            }
        }
    }

    func openFolder(_ folderID: UUID) {
        setFolder(folderID, open: true)
    }

    // MARK: - Spaces

    @discardableResult
    func createSpace(profileID: UUID, name: String, icon: String, accentHex: String, after: UUID?) -> UUID? {
        guard let owner = owner(ofProfile: profileID) else { return nil }
        let id = UUID()
        guard perform(owner, "createSpace", {
            try $0.createSpace(id: id, profileID: profileID, name: name, icon: icon, accentHex: accentHex, after: after)
        }) != nil else { return nil }
        return id
    }

    func updateSpace(_ spaceID: UUID, name: String?, icon: String?, accentHex: String?) {
        guard let owner = owner(ofSpace: spaceID) else { return }
        perform(owner, "updateSpace") { try $0.updateSpace(spaceID, name: name, icon: icon, accentHex: accentHex) }
    }

    func moveSpace(_ spaceID: UUID, toProfile profileID: UUID, after: UUID?) {
        guard let owner = owner(ofSpace: spaceID) else { return }
        guard perform(owner, "moveSpace", { try $0.moveSpace(spaceID, toProfile: profileID, after: after) }) != nil else { return }
        for window in allWindows where window.spaceID == spaceID { setProfile(profileID, of: window) }
        let source = tree(owner)
        let roots = source.children(of: .pinned(spaceID: spaceID)) + source.children(of: .tabs(spaceID: spaceID))
        unloadPagesOnWrongDataStore(roots.flatMap { source.subtree(of: $0.id) })
    }

    /// Pages whose item now belongs to another profile reload on that profile's data store.
    private func unloadPagesOnWrongDataStore(_ ids: [UUID]) {
        for id in ids {
            guard let page = session(for: id), let view = page.webView, let profile = page.profile,
                  view.configuration.websiteDataStore !== profile.dataStore else { continue }
            unload(id)
        }
    }

    /// Deletes a space; its items go to the reopen history. Windows showing it move to another space.
    func deleteSpace(_ spaceID: UUID) {
        guard let owner = owner(ofSpace: spaceID) else { return }
        let source = tree(owner)
        let ids = (source.children(of: .pinned(spaceID: spaceID)) + source.children(of: .tabs(spaceID: spaceID)))
            .flatMap { source.subtree(of: $0.id) }
        var closed: [ClosedEntry] = []
        guard perform(owner, "deleteSpace", { tree in
            let result = try tree.deleteSpace(spaceID)
            closed = result.closed
            return result.change
        }) != nil else { return }
        for id in ids { endSession(id) }
        if case .main = owner {
            for entry in closed { recordClosed(entry) }
        }
        let remaining = tree(owner).orderedSpaces
        for window in allWindows where window.spaceID == spaceID {
            window.selectedItemBySpace[spaceID] = nil
            let sameProfile = remaining.first { $0.profileID == window.profileID }
            if let next = sameProfile ?? remaining.first {
                setSpace(next.id, in: window)
            }
        }
    }

    // MARK: - Profiles

    /// Creates the app profile (which owns its data store) and its record under the same id.
    @discardableResult
    func createProfile(name: String, icon: String) -> UUID {
        let id = createAppProfile(name: name, icon: icon)
        perform(.main, "createProfile") { $0.createProfile(id: id, name: name, icon: icon) }
        return id
    }

    func updateProfile(_ profileID: UUID, name: String?, icon: String?) {
        guard perform(.main, "updateProfile", { try $0.updateProfile(profileID, name: name, icon: icon) }) != nil else { return }
        updateAppProfile(profileID, name: name, icon: icon)
    }

    /// Deletes a profile; its spaces and favorites move to `heir`, windows on it switch to `heir`,
    /// and the app profile is removed. false when either delete fails.
    @discardableResult
    func deleteProfile(_ profileID: UUID, heir: UUID) -> Bool {
        let affected = items(inProfile: profileID).map(\.id)
        guard perform(.main, "deleteProfile", { try $0.deleteProfile(profileID, heir: heir) }) != nil else { return false }
        unloadPagesOnWrongDataStore(affected)
        for window in regularWindows where window.profileID == profileID {
            setProfile(heir, of: window)
        }
        return deleteAppProfile(profileID)
    }

    // MARK: - Unload

    /// Releases an item's web views; selection first moves off windows showing it.
    func unload(_ itemID: UUID) {
        guard let page = session(for: itemID) else { return }
        if isVisibleInAnyWindow(itemID) { moveSelectionOff([itemID]) }
        page.unload()
    }

    /// Unloads every page no window shows, except pages playing audio or in picture-in-picture.
    func unloadAllHidden() {
        for page in sessions where !page.isUnloaded && !isVisibleInAnyWindow(page.itemID)
            && !page.hasPlayingAudio && !page.hasPiPActive {
            page.unload()
        }
    }

    // MARK: - External Undo

    /// Applies a change built elsewhere (the tab organizer's undo) to the main tree.
    func apply(_ change: Change) {
        let before = Set(tree.items.keys.filter { tree.item($0) != nil })
        moveSelectionOff(Set(change.items.compactMap { id, value in value == nil || value?.deletedAt != nil ? id : nil }))
        perform(.main, "apply", undoable: false) { tree in tree.apply(change) }
        for id in before where tree.item(id) == nil { endSession(id) }
        // Items the change brought back must not also reopen from the history.
        let restored = Set(change.items.keys.filter { !before.contains($0) && tree.item($0) != nil })
        dropClosed(containing: restored)
        for window in regularWindows { window.refreshCompositor() }
        save()
    }
}
