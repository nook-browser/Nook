//
//  KeyboardShortcutManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import Foundation
import AppKit
import SwiftUI

@Observable
class KeyboardShortcutManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let shortcutsKey = "keyboard.shortcuts"
    private let shortcutsVersionKey = "keyboard.shortcuts.version"
    private let currentVersion = 3 // Increment when adding new shortcuts


    var shortcuts: [KeyboardShortcut] = []
    weak var browserManager: BrowserManager?

    init() {
        loadShortcuts()
        setupGlobalMonitor()
    }

    func setBrowserManager(_ manager: BrowserManager) {
        self.browserManager = manager
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        let savedVersion = userDefaults.integer(forKey: shortcutsVersionKey)
        
        // Load from UserDefaults or use defaults
        if let data = userDefaults.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            self.shortcuts = decoded
            print("🔧 [KeyboardShortcutManager] Loaded \(shortcuts.count) shortcuts from UserDefaults")
            
            // Check if we need to merge new shortcuts
            if savedVersion < currentVersion {
                print("🔧 [KeyboardShortcutManager] Version mismatch, merging defaults")
                mergeWithDefaults()
                userDefaults.set(currentVersion, forKey: shortcutsVersionKey)
            }
        } else {
            print("🔧 [KeyboardShortcutManager] No saved shortcuts, using defaults")
            self.shortcuts = KeyboardShortcut.defaultShortcuts
            userDefaults.set(currentVersion, forKey: shortcutsVersionKey)
            saveShortcuts()
        }
        
        // Print all loaded shortcuts for debugging
        for shortcut in shortcuts {
            if shortcut.action == .duplicateTab {
                print("🔧 [KeyboardShortcutManager] Found duplicateTab shortcut: \(shortcut.keyCombination.displayString) - Enabled: \(shortcut.isEnabled)")
            }
        }
    }
    
    private func mergeWithDefaults() {
        let defaultShortcuts = KeyboardShortcut.defaultShortcuts
        var needsUpdate = false
        
        // Force add duplicateTab shortcut if it doesn't exist
        if let duplicateTabShortcut = defaultShortcuts.first(where: { $0.action == .duplicateTab }) {
            if !shortcuts.contains(where: { $0.action == .duplicateTab }) {
                shortcuts.append(duplicateTabShortcut)
                needsUpdate = true
                print("🔧 [KeyboardShortcutManager] Force added duplicateTab shortcut")
            }
        }
        
        for defaultShortcut in defaultShortcuts {
            // Check if this shortcut already exists
            if !shortcuts.contains(where: { $0.action == defaultShortcut.action }) {
                // Add missing shortcut
                shortcuts.append(defaultShortcut)
                needsUpdate = true
            }
        }
        
        if needsUpdate {
            saveShortcuts()
            print("🔧 [KeyboardShortcutManager] Updated shortcuts with new additions")
        }
    }

    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            userDefaults.set(encoded, forKey: shortcutsKey)
        }
    }

    // MARK: - Public Interface

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        return shortcuts.first { $0.action == action && $0.isEnabled }
    }

    func updateShortcut(action: ShortcutAction, keyCombination: KeyCombination) {
        if let index = shortcuts.firstIndex(where: { $0.action == action }) {
            shortcuts[index].keyCombination = keyCombination
            saveShortcuts()
        }
    }

    func toggleShortcut(action: ShortcutAction, isEnabled: Bool) {
        if let index = shortcuts.firstIndex(where: { $0.action == action }) {
            shortcuts[index].isEnabled = isEnabled
            saveShortcuts()
        }
    }

    func resetToDefaults() {
        shortcuts = KeyboardShortcut.defaultShortcuts
        saveShortcuts()
    }

    // MARK: - Conflict Detection

    func hasConflict(keyCombination: KeyCombination, excludingAction: ShortcutAction? = nil) -> ShortcutAction? {
        for shortcut in shortcuts where shortcut.isEnabled {
            if shortcut.action != excludingAction && shortcut.keyCombination == keyCombination {
                return shortcut.action
            }
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
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let modifiers = event.modifierFlags
        print("🔧 [KeyboardShortcutManager] Key pressed: '\(key)' with modifiers: \(modifiers)")
        
        for shortcut in shortcuts where shortcut.isEnabled {
            print("🔧 [KeyboardShortcutManager] Checking shortcut: \(shortcut.action.displayName) - \(shortcut.keyCombination.displayString)")
            if shortcut.keyCombination.matches(event) {
                print("🔧 [KeyboardShortcutManager] Match found! Executing: \(shortcut.action.displayName)")
                executeAction(shortcut.action)
                return true
            }
        }
        return false
    }

    private func executeAction(_ action: ShortcutAction) {
        guard let browserManager = browserManager else { return }

        DispatchQueue.main.async {
            switch action {
            // Navigation
            case .goBack:
                browserManager.currentTabForActiveWindow()?.goBack()
            case .goForward:
                browserManager.currentTabForActiveWindow()?.goForward()
            case .refresh:
                browserManager.refreshCurrentTabInActiveWindow()
            case .clearCookiesAndRefresh:
                browserManager.clearCurrentPageCookies()
                browserManager.refreshCurrentTabInActiveWindow()

            // Tab Management
            case .newTab:
                browserManager.openCommandPalette()
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
                print("🔧 [KeyboardShortcutManager] Executing duplicateTab")
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
                browserManager.openCommandPalette()
            case .openDevTools:
                browserManager.openWebInspector()
            case .viewDownloads:
                browserManager.showDownloads()
            case .viewHistory:
                browserManager.showHistory()
            case .copyLink:
                browserManager.copyCurrentURL()
            case .expandAllFolders:
                browserManager.expandAllFoldersInSidebar()
            }

            NotificationCenter.default.post(
                name: .shortcutExecuted,
                object: nil,
                userInfo: ["action": action]
            )
        }
    }

    // MARK: - Global Event Monitoring

    private var eventMonitor: Any?

    private func setupGlobalMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if let self = self {
                // Check if this is cmd+z for undo close tab
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "z" {
                    if let shortcut = self.shortcut(for: .undoCloseTab), shortcut.isEnabled {
                        self.executeAction(.undoCloseTab)
                        return nil // Consume the event to prevent system sound
                    }
                }

                // Check all other shortcuts
                if self.executeShortcut(event) {
                    return nil // Consume the event
                }
            }
            return event
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
