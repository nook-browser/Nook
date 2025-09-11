import Foundation
import SwiftUI
import AppKit
import Combine

/// Adapter for regular tabs in a space
@MainActor
class SpaceRegularTabListAdapter: TabListDataSource, ObservableObject {
    private let tabManager: TabManager
    let spaceId: UUID
    private var cancellable: AnyCancellable?
    
    init(tabManager: TabManager, spaceId: UUID) {
        self.tabManager = tabManager
        self.spaceId = spaceId
        // Relay TabManager changes to table consumers
        self.cancellable = tabManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
    
    var tabs: [Tab] {
        guard let space = tabManager.spaces.first(where: { $0.id == spaceId }) else { return [] }
        return tabManager.tabs(in: space)
    }
    
    func moveTab(from sourceIndex: Int, to targetIndex: Int) {
        objectWillChange.send()
        guard sourceIndex < tabs.count else { return }
        let tab = tabs[sourceIndex]
        tabManager.reorderRegular(tab, in: spaceId, to: targetIndex)
    }
    
    func selectTab(at index: Int) {
        guard index < tabs.count else { return }
        tabManager.setActiveTab(tabs[index])
    }
    
    func closeTab(at index: Int) {
        objectWillChange.send()
        guard index < tabs.count else { return }
        tabManager.removeTab(tabs[index].id)
    }
    
    func toggleMuteTab(at index: Int) {
        objectWillChange.send()
        guard index < tabs.count else { return }
        let tab = tabs[index]
        if tab.hasAudioContent {
            tab.toggleMute()
        }
    }
    
    func contextMenuForTab(at index: Int) -> NSMenu? {
        guard index < tabs.count else { return nil }
        let tab = tabs[index]
        let menu = NSMenu()

        // Move Up
        let upItem = NSMenuItem(title: "Move Up", action: #selector(moveTabUp(_:)), keyEquivalent: "")
        upItem.target = self
        upItem.representedObject = tab
        upItem.isEnabled = !isFirstTab(tab)
        menu.addItem(upItem)

        // Move Down
        let downItem = NSMenuItem(title: "Move Down", action: #selector(moveTabDown(_:)), keyEquivalent: "")
        downItem.target = self
        downItem.representedObject = tab
        downItem.isEnabled = !isLastTab(tab)
        menu.addItem(downItem)

        menu.addItem(NSMenuItem.separator())

        // Pin to Space
        let pinToSpaceItem = NSMenuItem(title: "Pin to Space", action: #selector(pinToSpace(_:)), keyEquivalent: "")
        pinToSpaceItem.target = self
        pinToSpaceItem.representedObject = tab
        menu.addItem(pinToSpaceItem)

        // Pin Globally
        let pinGlobalItem = NSMenuItem(title: "Pin Globally", action: #selector(pinGlobally(_:)), keyEquivalent: "")
        pinGlobalItem.target = self
        pinGlobalItem.representedObject = tab
        menu.addItem(pinGlobalItem)

        // Audio toggle if relevant
        if tab.hasAudioContent || tab.isAudioMuted {
            let title = tab.isAudioMuted ? "Unmute Audio" : "Mute Audio"
            let audioItem = NSMenuItem(title: title, action: #selector(toggleAudio(_:)), keyEquivalent: "")
            audioItem.target = self
            audioItem.representedObject = tab
            menu.addItem(audioItem)
        }

        // Unload operations
        let unloadItem = NSMenuItem(title: "Unload Tab", action: #selector(unloadTab(_:)), keyEquivalent: "")
        unloadItem.target = self
        unloadItem.representedObject = tab
        unloadItem.isEnabled = !tab.isUnloaded
        menu.addItem(unloadItem)

        let unloadAllItem = NSMenuItem(title: "Unload All Inactive Tabs", action: #selector(unloadAllInactive(_:)), keyEquivalent: "")
        unloadAllItem.target = self
        unloadAllItem.representedObject = tab
        menu.addItem(unloadAllItem)

        menu.addItem(NSMenuItem.separator())

        // Close
        let closeItem = NSMenuItem(title: "Close tab", action: #selector(closeTab(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = tab
        menu.addItem(closeItem)

        return menu
    }
    
    @objc private func moveTabUp(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.moveTabUp(tab.id)
    }

    @objc private func moveTabDown(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.moveTabDown(tab.id)
    }

    @objc private func pinToSpace(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.pinTabToSpace(tab, spaceId: spaceId)
    }

    @objc private func pinGlobally(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.addToEssentials(tab)
    }

    @objc private func toggleAudio(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tab.toggleMute()
    }

    @objc private func unloadTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.unloadTab(tab)
    }

    @objc private func unloadAllInactive(_ sender: NSMenuItem) {
        tabManager.unloadAllInactiveTabs()
    }

    @objc private func closeTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.removeTab(tab.id)
    }

    private func isFirstTab(_ tab: Tab) -> Bool { tabs.first?.id == tab.id }
    private func isLastTab(_ tab: Tab) -> Bool { tabs.last?.id == tab.id }
}

/// Adapter for pinned tabs in a space
@MainActor
class SpacePinnedTabListAdapter: TabListDataSource, ObservableObject {
    private let tabManager: TabManager
    let spaceId: UUID
    private var cancellable: AnyCancellable?
    
    init(tabManager: TabManager, spaceId: UUID) {
        self.tabManager = tabManager
        self.spaceId = spaceId
        self.cancellable = tabManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
    
        var tabs: [Tab] {
        tabManager.spacePinnedTabs(for: spaceId)
    }
    
    func moveTab(from sourceIndex: Int, to targetIndex: Int) {
        objectWillChange.send()
        guard sourceIndex < tabs.count else { return }
        let tab = tabs[sourceIndex]
        tabManager.reorderSpacePinned(tab, in: spaceId, to: targetIndex)
    }
    
    func selectTab(at index: Int) {
        guard index < tabs.count else { return }
        tabManager.setActiveTab(tabs[index])
    }
    
    func closeTab(at index: Int) {
        objectWillChange.send()
        guard index < tabs.count else { return }
        tabManager.removeTab(tabs[index].id)
    }
    
    func toggleMuteTab(at index: Int) {
        objectWillChange.send()
        guard index < tabs.count else { return }
        let tab = tabs[index]
        if tab.hasAudioContent {
            tab.toggleMute()
        }
    }
    
    func contextMenuForTab(at index: Int) -> NSMenu? {
        guard index < tabs.count else { return nil }
        let tab = tabs[index]
        let menu = NSMenu()

        // Unpin from space
        let unpinItem = NSMenuItem(title: "Unpin from Space", action: #selector(unpinFromSpace(_:)), keyEquivalent: "")
        unpinItem.target = self
        unpinItem.representedObject = tab
        menu.addItem(unpinItem)

        // Pin Globally
        let pinGlobalItem = NSMenuItem(title: "Pin Globally", action: #selector(pinGlobally(_:)), keyEquivalent: "")
        pinGlobalItem.target = self
        pinGlobalItem.representedObject = tab
        menu.addItem(pinGlobalItem)

        // Audio toggle if relevant
        if tab.hasAudioContent || tab.isAudioMuted {
            let title = tab.isAudioMuted ? "Unmute Audio" : "Mute Audio"
            let audioItem = NSMenuItem(title: title, action: #selector(toggleAudio(_:)), keyEquivalent: "")
            audioItem.target = self
            audioItem.representedObject = tab
            menu.addItem(audioItem)
        }

        // Unload operations
        let unloadItem = NSMenuItem(title: "Unload Tab", action: #selector(unloadTab(_:)), keyEquivalent: "")
        unloadItem.target = self
        unloadItem.representedObject = tab
        unloadItem.isEnabled = !tab.isUnloaded
        menu.addItem(unloadItem)

        let unloadAllItem = NSMenuItem(title: "Unload All Inactive Tabs", action: #selector(unloadAllInactive(_:)), keyEquivalent: "")
        unloadAllItem.target = self
        unloadAllItem.representedObject = tab
        menu.addItem(unloadAllItem)

        menu.addItem(NSMenuItem.separator())

        // Close tab
        let closeItem = NSMenuItem(title: "Close tab", action: #selector(closeTab(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = tab
        menu.addItem(closeItem)

        return menu
    }
    
    @objc private func unpinFromSpace(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.unpinTabFromSpace(tab)
    }

    @objc private func pinGlobally(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.addToEssentials(tab)
    }

    @objc private func toggleAudio(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tab.toggleMute()
    }

    @objc private func unloadTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.unloadTab(tab)
    }

    @objc private func unloadAllInactive(_ sender: NSMenuItem) {
        tabManager.unloadAllInactiveTabs()
    }

    @objc private func closeTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.removeTab(tab.id)
    }
}

/// Adapter for essential tabs
@MainActor
class EssentialTabListAdapter: TabListDataSource, ObservableObject {
    private let tabManager: TabManager
    private var cancellable: AnyCancellable?
    
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        // Observe TabManager and relay to collection view
        self.cancellable = tabManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
    
    deinit { cancellable?.cancel() }
    
    var tabs: [Tab] {
        // Profile-aware essentials: returns pinned tabs for current profile only
        tabManager.essentialTabs
    }
    
    func moveTab(from sourceIndex: Int, to targetIndex: Int) {
        objectWillChange.send()
        guard sourceIndex < tabs.count else { return }
        let tab = tabs[sourceIndex]
        tabManager.reorderEssential(tab, to: targetIndex)
    }
    
    func selectTab(at index: Int) {
        guard index < tabs.count else { return }
        tabManager.setActiveTab(tabs[index])
    }
    
    func closeTab(at index: Int) {
        guard index < tabs.count else { return }
        tabManager.removeTab(tabs[index].id)
    }
    
    func toggleMuteTab(at index: Int) {
        guard index < tabs.count else { return }
        let tab = tabs[index]
        if tab.hasAudioContent {
            tab.toggleMute()
        }
    }
    
    func contextMenuForTab(at index: Int) -> NSMenu? {
        guard index < tabs.count else { return nil }
        let tab = tabs[index]
        let menu = NSMenu()

        // Reload
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadTab(_:)), keyEquivalent: "")
        reloadItem.target = self
        reloadItem.representedObject = tab
        menu.addItem(reloadItem)

        menu.addItem(NSMenuItem.separator())

        // Audio toggle if relevant
        if tab.hasAudioContent || tab.isAudioMuted {
            let title = tab.isAudioMuted ? "Unmute Audio" : "Mute Audio"
            let audioItem = NSMenuItem(title: title, action: #selector(toggleAudio(_:)), keyEquivalent: "")
            audioItem.target = self
            audioItem.representedObject = tab
            menu.addItem(audioItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Unload operations
        let unloadItem = NSMenuItem(title: "Unload Tab", action: #selector(unloadTab(_:)), keyEquivalent: "")
        unloadItem.target = self
        unloadItem.representedObject = tab
        unloadItem.isEnabled = !tab.isUnloaded
        menu.addItem(unloadItem)

        let unloadAllItem = NSMenuItem(title: "Unload All Inactive Tabs", action: #selector(unloadAllInactive(_:)), keyEquivalent: "")
        unloadAllItem.target = self
        unloadAllItem.representedObject = tab
        menu.addItem(unloadAllItem)

        menu.addItem(NSMenuItem.separator())

        // Remove from essentials
        let removeItem = NSMenuItem(title: "Remove from Essentials", action: #selector(removeFromEssentials(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = tab
        menu.addItem(removeItem)

        // Close
        let closeItem = NSMenuItem(title: "Close tab", action: #selector(closeTab(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = tab
        menu.addItem(closeItem)

        return menu
    }
    
    @objc private func reloadTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tab.refresh()
    }
    
    @objc private func removeFromEssentials(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.removeFromEssentials(tab)
    }

    @objc private func toggleAudio(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tab.toggleMute()
    }

    @objc private func unloadTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.unloadTab(tab)
    }

    @objc private func unloadAllInactive(_ sender: NSMenuItem) {
        tabManager.unloadAllInactiveTabs()
    }

    @objc private func closeTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        tabManager.removeTab(tab.id)
    }
}
