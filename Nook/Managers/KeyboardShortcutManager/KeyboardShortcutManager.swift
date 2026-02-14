//
//  KeyboardShortcutManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
@Observable
class KeyboardShortcutManager {
    private let userDefaults = UserDefaults.standard
    private let shortcutsKey = "keyboard.shortcuts"
    private let shortcutsVersionKey = "keyboard.shortcuts.version"
    private let currentVersion = 5 // Increment when adding new shortcuts

    /// Hash-based storage for O(1) lookup: ["cmd+t": KeyboardShortcut]
    private var shortcutMap: [String: KeyboardShortcut] = [:]

    /// All shortcuts for UI display (sorted by display name)
    var shortcuts: [KeyboardShortcut] {
        Array(shortcutMap.values).sorted { $0.action.displayName < $1.action.displayName }
    }

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    init() {
        loadShortcuts()
        setupGlobalMonitor()
    }

    func setBrowserManager(_ manager: BrowserManager) {
        self.browserManager = manager
        self.windowRegistry = manager.windowRegistry
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        let savedVersion = userDefaults.integer(forKey: shortcutsVersionKey)

        // Load from UserDefaults or use defaults
        if let data = userDefaults.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            // Populate hash map from loaded shortcuts
            for shortcut in decoded {
                shortcutMap[shortcut.lookupKey] = shortcut
            }

            // Check if we need to merge new shortcuts
            if savedVersion < currentVersion {
                mergeWithDefaults()
                userDefaults.set(currentVersion, forKey: shortcutsVersionKey)
            }
        } else {
            // Use defaults and populate hash map
            let defaults = KeyboardShortcut.defaultShortcuts
            for shortcut in defaults {
                shortcutMap[shortcut.lookupKey] = shortcut
            }
            userDefaults.set(currentVersion, forKey: shortcutsVersionKey)
            saveShortcuts()
        }
    }

    private func mergeWithDefaults() {
        let defaultShortcuts = KeyboardShortcut.defaultShortcuts
        var needsUpdate = false

        for defaultShortcut in defaultShortcuts {
            // Check if this shortcut already exists (by action)
            if !shortcutMap.values.contains(where: { $0.action == defaultShortcut.action }) {
                // Add missing shortcut
                shortcutMap[defaultShortcut.lookupKey] = defaultShortcut
                needsUpdate = true
            }
        }

        if needsUpdate {
            saveShortcuts()
        }
    }

    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            userDefaults.set(encoded, forKey: shortcutsKey)
        }
    }

    // MARK: - Public Interface

    /// O(1) lookup of shortcut by key combination
    func shortcut(for keyCombination: KeyCombination) -> KeyboardShortcut? {
        shortcutMap[keyCombination.lookupKey]
    }

    /// O(n) lookup of shortcut by action (for specific action queries)
    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcutMap.values.first { $0.action == action && $0.isEnabled }
    }

    func updateShortcut(action: ShortcutAction, keyCombination: KeyCombination) {
        // Find the existing shortcut first
        guard var shortcut = shortcutMap.values.first(where: { $0.action == action }) else {
            return
        }

        // Remove old entry
        shortcutMap.removeValue(forKey: shortcut.lookupKey)

        // Update and add back
        shortcut.keyCombination = keyCombination
        shortcutMap[keyCombination.lookupKey] = shortcut
        saveShortcuts()
    }

    func toggleShortcut(action: ShortcutAction, isEnabled: Bool) {
        if let key = shortcutMap.first(where: { $0.value.action == action })?.key,
           var shortcut = shortcutMap[key] {
            shortcut.isEnabled = isEnabled
            shortcutMap[key] = shortcut
            saveShortcuts()
        }
    }

    func resetToDefaults() {
        shortcutMap.removeAll()
        let defaults = KeyboardShortcut.defaultShortcuts
        for shortcut in defaults {
            shortcutMap[shortcut.lookupKey] = shortcut
        }
        saveShortcuts()
    }

    // MARK: - Conflict Detection

    func hasConflict(keyCombination: KeyCombination, excludingAction: ShortcutAction? = nil) -> ShortcutAction? {
        guard let shortcut = shortcutMap[keyCombination.lookupKey],
              shortcut.isEnabled else {
            return nil
        }

        if shortcut.action != excludingAction {
            return shortcut.action
        }
        return nil
    }

    func isValidKeyCombination(_ keyCombination: KeyCombination) -> Bool {
        // Basic validation - ensure it's not empty and has at least one modifier
        guard !keyCombination.key.isEmpty else { return false }

        // Require at least one modifier for most keys (except function keys, etc.)
        let functionKeys = ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
                           "escape", "delete", "forwarddelete", "home", "end", "pageup", "pagedown",
                           "help", "tab", "return", "space", "uparrow", "downarrow", "leftarrow", "rightarrow"]

        if functionKeys.contains(keyCombination.key.lowercased()) {
            return true
        }

        return !keyCombination.modifiers.isEmpty
    }

    // MARK: - Shortcut Execution

    func executeShortcut(_ event: NSEvent) -> Bool {
        guard let keyCombination = KeyCombination(from: event) else { return false }

        guard let shortcut = shortcutMap[keyCombination.lookupKey],
              shortcut.isEnabled else {
            return false
        }

        executeAction(shortcut.action)
        return true
    }

    private func executeAction(_ action: ShortcutAction) {
        guard let browserManager = browserManager else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch action {
            // Navigation
            case .goBack:
                // Use window-specific webview like the UI buttons do
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId) {
                    if webView.canGoBack {
                        webView.goBack()
                    }
                }
            case .goForward:
                // Use window-specific webview like the UI buttons do
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId) {
                    if webView.canGoForward {
                        webView.goForward()
                    }
                }
            case .refresh:
                browserManager.refreshCurrentTabInActiveWindow()
            case .clearCookiesAndRefresh:
                browserManager.clearCurrentPageCookies()
                browserManager.refreshCurrentTabInActiveWindow()

            // Tab Management
            case .newTab:
                self.windowRegistry?.activeWindow?.commandPalette?.open()
            case .closeTab:
                browserManager.closeCurrentTab()
            case .undoCloseTab:
                browserManager.undoCloseTab()
            case .nextTab:
                browserManager.selectNextTabInActiveWindow()
            case .previousTab:
                browserManager.selectPreviousTabInActiveWindow()
            case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8:
                let tabIndex = Int(action.rawValue.components(separatedBy: "_").last ?? "0") ?? 1
                browserManager.selectTabByIndexInActiveWindow(tabIndex - 1)
            case .goToLastTab:
                browserManager.selectLastTabInActiveWindow()
            case .duplicateTab:
                browserManager.duplicateCurrentTab()
            case .toggleTopBarAddressView:
                browserManager.toggleTopBarAddressView()

            // Space Management
            case .nextSpace:
                browserManager.selectNextSpaceInActiveWindow()
            case .previousSpace:
                browserManager.selectPreviousSpaceInActiveWindow()

            // Window Management
            case .newWindow:
                browserManager.createNewWindow()
            case .closeWindow:
                browserManager.closeActiveWindow()
            case .closeBrowser:
                browserManager.showQuitDialog()
            case .toggleFullScreen:
                browserManager.toggleFullScreenForActiveWindow()

            // Tools & Features
            case .openCommandPalette:
                self.windowRegistry?.activeWindow?.commandPalette?.open()
            case .openDevTools:
                browserManager.openWebInspector()
            case .viewDownloads:
                browserManager.showDownloads()
            case .viewHistory:
                browserManager.showHistory()
            case .expandAllFolders:
                browserManager.expandAllFoldersInSidebar()

            // NEW: Missing actions that were only in NookCommands
            case .focusAddressBar:
                let currentURL = browserManager.currentTabForActiveWindow()?.url.absoluteString ?? ""
                self.windowRegistry?.activeWindow?.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
            case .findInPage:
                browserManager.showFindBar()
            case .zoomIn:
                browserManager.zoomInCurrentTab()
            case .zoomOut:
                browserManager.zoomOutCurrentTab()
            case .actualSize:
                browserManager.resetZoomCurrentTab()

            // NEW: Menu actions that were missing ShortcutAction definitions
            case .toggleSidebar:
                browserManager.toggleSidebar()
            case .toggleAIAssistant:
                browserManager.toggleAISidebar()
            case .togglePictureInPicture:
                browserManager.requestPiPForCurrentTabInActiveWindow()
            case .copyCurrentURL:
                browserManager.copyCurrentURL()
            case .hardReload:
                browserManager.hardReloadCurrentPage()
            case .muteUnmuteAudio:
                browserManager.toggleMuteCurrentTabInActiveWindow()
            case .installExtension:
                browserManager.showExtensionInstallDialog()
            case .customizeSpaceGradient:
                browserManager.showGradientEditor()
            case .createBoost:
                browserManager.showBoostsDialog()
            }

            NotificationCenter.default.post(
                name: .shortcutExecuted,
                object: nil,
                userInfo: ["action": action]
            )
        }
    }

    // MARK: - Global Event Monitoring

    nonisolated(unsafe) private var eventMonitor: Any?

    private func setupGlobalMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            // Try to execute shortcut - if handled, consume event
            if self.executeShortcut(event) {
                return nil // Consume the event
            }

            return event // Pass through
        }
        self.eventMonitor = monitor
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor as! NSObjectProtocol)
        }
    }
}

// MARK: - Notification
extension Notification.Name {
    static let shortcutExecuted = Notification.Name("shortcutExecuted")
    static let shortcutsChanged = Notification.Name("shortcutsChanged")
}
