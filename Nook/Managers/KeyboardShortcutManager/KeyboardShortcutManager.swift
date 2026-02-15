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
    
    /// Flag to prevent re-entrancy when forwarding events to WebView
    private var isForwardingEvent = false

    /// All shortcuts for UI display (sorted by display name)
    var shortcuts: [KeyboardShortcut] {
        Array(shortcutMap.values).sorted { $0.action.displayName < $1.action.displayName }
    }

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    
    /// Detector for website keyboard shortcut conflicts
    let websiteShortcutDetector = WebsiteShortcutDetector()

    init() {
        loadShortcuts()
        setupGlobalMonitor()
    }

    func setBrowserManager(_ manager: BrowserManager) {
        self.browserManager = manager
        self.windowRegistry = manager.windowRegistry
        self.websiteShortcutDetector.browserManager = manager
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
        // Prevent re-entrancy when forwarding events to WebView
        guard !isForwardingEvent else {
            print("⌨️ [KSM] Skipping - already forwarding event")
            return false
        }
        
        // Arrow keys and other navigation keys should pass through to the WebView
        // UNLESS they have modifiers (cmd, option, etc.) - those might be Nook shortcuts
        let keyCode = event.keyCode
        let navigationKeyCodes: Set<UInt16> = [
            123, // left arrow
            124, // right arrow
            125, // down arrow
            126, // up arrow
            115, // home
            119, // end
            116, // page up
            121, // page down
        ]
        if navigationKeyCodes.contains(keyCode) {
            // If arrow keys have modifiers, don't pass through - let them be checked as shortcuts
            // This prevents the "bonk" sound when using combo shortcuts like cmd+option+arrow
            let hasModifiers = event.modifierFlags.contains(.command) ||
                              event.modifierFlags.contains(.option) ||
                              event.modifierFlags.contains(.control) ||
                              event.modifierFlags.contains(.shift)
            if !hasModifiers {
                return false // Pass through for pure navigation (no modifiers)
            }
            // Has modifiers - continue to check if it's a Nook shortcut
        }
        
        guard let keyCombination = KeyCombination(from: event) else { 
            print("⌨️ [KSM] Could not create KeyCombination from event")
            return false
        }
        
        print("⌨️ [KSM] ===== KEYDOWN: \(keyCombination.lookupKey) =====")

        guard let shortcut = shortcutMap[keyCombination.lookupKey],
              shortcut.isEnabled else {
            print("⌨️ [KSM] No Nook shortcut for: \(keyCombination.lookupKey)")
            return false
        }
        
        print("⌨️ [KSM] Found Nook shortcut: \(shortcut.action.displayName)")

        // MARK: - Website Shortcut Conflict Resolution
        // Check if this shortcut conflicts with a website shortcut
        if let windowId = windowRegistry?.activeWindow?.id {
            print("⌨️ [KSM] Checking for website conflict, windowId: \(windowId)")
            let shouldPass = websiteShortcutDetector.shouldPassToWebsite(
                keyCombination,
                windowId: windowId,
                nookActionName: shortcut.action.displayName
            )
            
            if shouldPass {
                // First press: Forward event directly to the WebView
                print("⌨️ [KSM] >>> FIRST PRESS - Forwarding to WebView <<<")
                forwardEventToWebView(event)
                return true // We handled it (by forwarding)
            } else if websiteShortcutDetector.hasPendingShortcut(for: windowId) {
                // Second press within timeout - we'll execute Nook action below
                print("⌨️ [KSM] >>> SECOND PRESS - Executing Nook action <<<")
            } else {
                print("⌨️ [KSM] No conflict detected, executing Nook action")
            }
        } else {
            print("⌨️ [KSM] No active window found for conflict check")
        }

        print("⌨️ [KSM] Executing Nook shortcut: \(shortcut.action.displayName)")
        executeAction(shortcut.action)
        return true
    }
    
    /// Forward a keyboard event directly to the active WebView
    private func forwardEventToWebView(_ event: NSEvent) {
        guard let windowState = windowRegistry?.activeWindow,
              let tabId = windowState.currentTabId,
              let windowId = windowRegistry?.activeWindow?.id,
              let webView = browserManager?.getWebView(for: tabId, in: windowId) else {
            print("⌨️ [KSM] Could not find WebView to forward event")
            return
        }
        
        // Set flag to prevent re-entrancy
        isForwardingEvent = true
        defer { isForwardingEvent = false }
        
        // Make the WebView the first responder if it isn't already
        if webView.window?.firstResponder != webView {
            webView.window?.makeFirstResponder(webView)
        }
        
        // Try JavaScript dispatch first - this is more reliable for web apps
        dispatchKeyboardEventToWebView(webView, event: event)
        
        // Also call keyDown for native WebView handling (scroll, copy/paste, etc.)
        webView.keyDown(with: event)
        print("⌨️ [KSM] Event forwarded to WebView via JS and keyDown")
    }
    
    /// Dispatch a keyboard event to the WebView's DOM via JavaScript
    private func dispatchKeyboardEventToWebView(_ webView: WKWebView, event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? event.characters ?? ""
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        // Build modifier flags for JavaScript
        var jsModifiers: [String] = []
        if modifiers.contains(.command) { jsModifiers.append("metaKey: true") }
        if modifiers.contains(.shift) { jsModifiers.append("shiftKey: true") }
        if modifiers.contains(.control) { jsModifiers.append("ctrlKey: true") }
        if modifiers.contains(.option) { jsModifiers.append("altKey: true") }
        let modifierStr = jsModifiers.joined(separator: ", ")
        
        // Escape the key for JavaScript
        let escapedKey = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        
        // Map keyCode to JavaScript key codes
        let jsKeyCode = mapToJSKeyCode(key, keyCode: keyCode, modifiers: modifiers)
        
        let js = """
        (function() {
            var keyEvent = new KeyboardEvent('keydown', {
                key: '\(escapedKey)',
                code: '\(jsKeyCode)',
                keyCode: \(keyCode),
                which: \(keyCode),
                \(modifierStr),
                bubbles: true,
                cancelable: true,
                composed: true
            });
            
            var dispatched = document.activeElement.dispatchEvent(keyEvent);
            if (!dispatched) {
                // Try dispatching to document if activeElement didn't handle it
                document.dispatchEvent(keyEvent);
            }
            
            // Also dispatch keyup
            var keyUpEvent = new KeyboardEvent('keyup', {
                key: '\(escapedKey)',
                code: '\(jsKeyCode)',
                keyCode: \(keyCode),
                which: \(keyCode),
                \(modifierStr),
                bubbles: true,
                cancelable: true,
                composed: true
            });
            document.activeElement.dispatchEvent(keyUpEvent);
            
            return dispatched;
        })();
        """
        
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("⌨️ [KSM] JS dispatch error: \(error.localizedDescription)")
            } else {
                print("⌨️ [KSM] JS dispatch result: \(result ?? "nil")")
            }
        }
    }
    
    /// Map NSEvent keyCode to JavaScript code string
    private func mapToJSKeyCode(_ key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        // Map common keys to JavaScript code values
        switch keyCode {
        case 0x00: return "KeyA"
        case 0x01: return "KeyS"
        case 0x02: return "KeyD"
        case 0x03: return "KeyF"
        case 0x04: return "KeyH"
        case 0x05: return "KeyG"
        case 0x06: return "KeyZ"
        case 0x07: return "KeyX"
        case 0x08: return "KeyC"
        case 0x09: return "KeyV"
        case 0x0B: return "KeyB"
        case 0x0C: return "KeyQ"
        case 0x0D: return "KeyW"
        case 0x0E: return "KeyE"
        case 0x0F: return "KeyR"
        case 0x10: return "KeyY"
        case 0x11: return "KeyT"
        case 0x12: return "Digit1"
        case 0x13: return "Digit2"
        case 0x14: return "Digit3"
        case 0x15: return "Digit4"
        case 0x16: return "Digit6"
        case 0x17: return "Digit5"
        case 0x18: return "Equal"
        case 0x19: return "Digit9"
        case 0x1A: return "Digit7"
        case 0x1B: return "Minus"
        case 0x1C: return "Digit8"
        case 0x1D: return "Digit0"
        case 0x1E: return "BracketRight"
        case 0x1F: return "KeyO"
        case 0x20: return "KeyU"
        case 0x21: return "BracketLeft"
        case 0x22: return "KeyI"
        case 0x23: return "KeyP"
        case 0x24: return "Enter"
        case 0x25: return "KeyL"
        case 0x26: return "KeyJ"
        case 0x27: return "Quote"
        case 0x28: return "KeyK"
        case 0x29: return "Semicolon"
        case 0x2A: return "Backslash"
        case 0x2B: return "Comma"
        case 0x2C: return "Slash"
        case 0x2D: return "KeyN"
        case 0x2E: return "KeyM"
        case 0x2F: return "Period"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Backspace"
        case 0x35: return "Escape"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x7B: return "ArrowLeft"
        case 0x7C: return "ArrowRight"
        case 0x7D: return "ArrowDown"
        case 0x7E: return "ArrowUp"
        default: return "Key\(key.uppercased())"
        }
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
