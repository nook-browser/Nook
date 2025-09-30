//
//  KeyboardShortcut.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import Foundation
import AppKit

// MARK: - Keyboard Shortcut Data Model
struct KeyboardShortcut: Identifiable, Hashable, Codable {
    let id: UUID
    let action: ShortcutAction
    var keyCombination: KeyCombination
    var isEnabled: Bool = true
    var isCustomizable: Bool = true

    init(action: ShortcutAction, keyCombination: KeyCombination, isEnabled: Bool = true, isCustomizable: Bool = true) {
        self.id = UUID()
        self.action = action
        self.keyCombination = keyCombination
        self.isEnabled = isEnabled
        self.isCustomizable = isCustomizable
    }
}

// MARK: - Shortcut Actions
enum ShortcutAction: String, CaseIterable, Hashable, Codable {
    // Navigation
    case goBack = "go_back"
    case goForward = "go_forward"
    case refresh = "refresh"
    case clearCookiesAndRefresh = "clear_cookies_and_refresh"

    // Tab Management
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case nextTab = "next_tab"
    case previousTab = "previous_tab"
    case goToTab1 = "go_to_tab_1"
    case goToTab2 = "go_to_tab_2"
    case goToTab3 = "go_to_tab_3"
    case goToTab4 = "go_to_tab_4"
    case goToTab5 = "go_to_tab_5"
    case goToTab6 = "go_to_tab_6"
    case goToTab7 = "go_to_tab_7"
    case goToTab8 = "go_to_tab_8"
    case goToLastTab = "go_to_last_tab"

    // Space Management
    case nextSpace = "next_space"
    case previousSpace = "previous_space"

    // Window Management
    case newWindow = "new_window"
    case closeWindow = "close_window"
    case closeBrowser = "close_browser"
    case toggleFullScreen = "toggle_full_screen"

    // Tools & Features
    case openCommandPalette = "open_command_palette"
    case openDevTools = "open_dev_tools"
    case viewDownloads = "view_downloads"
    case viewHistory = "view_history"
    case copyLink = "copy_link"
    case expandAllFolders = "expand_all_folders"

    var displayName: String {
        switch self {
        case .goBack: return "Go Back"
        case .goForward: return "Go Forward"
        case .refresh: return "Refresh"
        case .clearCookiesAndRefresh: return "Clear Cookies and Refresh"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .goToTab1: return "Go to Tab 1"
        case .goToTab2: return "Go to Tab 2"
        case .goToTab3: return "Go to Tab 3"
        case .goToTab4: return "Go to Tab 4"
        case .goToTab5: return "Go to Tab 5"
        case .goToTab6: return "Go to Tab 6"
        case .goToTab7: return "Go to Tab 7"
        case .goToTab8: return "Go to Tab 8"
        case .goToLastTab: return "Go to Last Tab"
        case .nextSpace: return "Next Space"
        case .previousSpace: return "Previous Space"
        case .newWindow: return "New Window"
        case .closeWindow: return "Close Window"
        case .closeBrowser: return "Close Browser"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .openCommandPalette: return "Open Command Palette"
        case .openDevTools: return "Developer Tools"
        case .viewDownloads: return "View Downloads"
        case .viewHistory: return "View History"
        case .copyLink: return "Copy Link"
        case .expandAllFolders: return "Expand All Folders"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .goBack, .goForward, .refresh, .clearCookiesAndRefresh:
            return .navigation
        case .newTab, .closeTab, .nextTab, .previousTab, .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToLastTab:
            return .tabs
        case .nextSpace, .previousSpace:
            return .spaces
        case .newWindow, .closeWindow, .closeBrowser, .toggleFullScreen:
            return .window
        case .openCommandPalette, .openDevTools, .viewDownloads, .viewHistory, .copyLink, .expandAllFolders:
            return .tools
        }
    }
}

// MARK: - Shortcut Categories
enum ShortcutCategory: String, CaseIterable, Hashable, Codable {
    case navigation = "navigation"
    case tabs = "tabs"
    case spaces = "spaces"
    case window = "window"
    case tools = "tools"

    var displayName: String {
        switch self {
        case .navigation: return "Navigation"
        case .tabs: return "Tabs"
        case .spaces: return "Spaces"
        case .window: return "Window"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .navigation: return "arrow.left.arrow.right"
        case .tabs: return "doc.on.doc"
        case .spaces: return "rectangle.3.group"
        case .window: return "macwindow"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Key Combination
struct KeyCombination: Hashable, Codable {
    let key: String
    let modifiers: Modifiers

    init(key: String, modifiers: Modifiers = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    var displayString: String {
        var parts = modifiers.displayStrings
        parts.append(key.uppercased())
        return parts.joined(separator: " + ")
    }

    // For matching with NSEvent
    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .keyUp else { return false }

        let keyMatches = event.charactersIgnoringModifiers?.lowercased() == key

        let modifierMatches =
            (modifiers.contains(.command) == (event.modifierFlags.contains(.command))) &&
            (modifiers.contains(.option) == (event.modifierFlags.contains(.option))) &&
            (modifiers.contains(.control) == (event.modifierFlags.contains(.control))) &&
            (modifiers.contains(.shift) == (event.modifierFlags.contains(.shift)))

        return keyMatches && modifierMatches
    }
}

// MARK: - Modifiers
struct Modifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let control = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)

    var displayStrings: [String] {
        var strings: [String] = []
        if contains(.command) { strings.append("⌘") }
        if contains(.option) { strings.append("⌥") }
        if contains(.control) { strings.append("⌃") }
        if contains(.shift) { strings.append("⇧") }
        return strings
    }
}

// MARK: - Default Shortcuts
extension KeyboardShortcut {
    static var defaultShortcuts: [KeyboardShortcut] {
        [
            // Navigation
            KeyboardShortcut(action: .goBack, keyCombination: KeyCombination(key: "[", modifiers: [.command])),
            KeyboardShortcut(action: .goForward, keyCombination: KeyCombination(key: "]", modifiers: [.command])),
            KeyboardShortcut(action: .refresh, keyCombination: KeyCombination(key: "r", modifiers: [.command])),
            KeyboardShortcut(action: .clearCookiesAndRefresh, keyCombination: KeyCombination(key: "r", modifiers: [.command, .shift, .option])),

            // Tab Management
            KeyboardShortcut(action: .newTab, keyCombination: KeyCombination(key: "t", modifiers: [.command])),
            KeyboardShortcut(action: .closeTab, keyCombination: KeyCombination(key: "w", modifiers: [.command])),
            KeyboardShortcut(action: .nextTab, keyCombination: KeyCombination(key: "tab", modifiers: [.control])),
            KeyboardShortcut(action: .previousTab, keyCombination: KeyCombination(key: "tab", modifiers: [.control, .shift])),
            KeyboardShortcut(action: .goToTab1, keyCombination: KeyCombination(key: "1", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab2, keyCombination: KeyCombination(key: "2", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab3, keyCombination: KeyCombination(key: "3", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab4, keyCombination: KeyCombination(key: "4", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab5, keyCombination: KeyCombination(key: "5", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab6, keyCombination: KeyCombination(key: "6", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab7, keyCombination: KeyCombination(key: "7", modifiers: [.command])),
            KeyboardShortcut(action: .goToTab8, keyCombination: KeyCombination(key: "8", modifiers: [.command])),
            KeyboardShortcut(action: .goToLastTab, keyCombination: KeyCombination(key: "9", modifiers: [.command])),

            // Space Management
            KeyboardShortcut(action: .nextSpace, keyCombination: KeyCombination(key: "]", modifiers: [.command, .control])),
            KeyboardShortcut(action: .previousSpace, keyCombination: KeyCombination(key: "[", modifiers: [.command, .control])),

            // Window Management
            KeyboardShortcut(action: .newWindow, keyCombination: KeyCombination(key: "n", modifiers: [.command])),
            KeyboardShortcut(action: .closeWindow, keyCombination: KeyCombination(key: "w", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .closeBrowser, keyCombination: KeyCombination(key: "q", modifiers: [.command])),
            KeyboardShortcut(action: .toggleFullScreen, keyCombination: KeyCombination(key: "f", modifiers: [.command, .control])),

            // Tools & Features
            KeyboardShortcut(action: .openCommandPalette, keyCombination: KeyCombination(key: "p", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .openDevTools, keyCombination: KeyCombination(key: "i", modifiers: [.command, .option])),
            KeyboardShortcut(action: .viewDownloads, keyCombination: KeyCombination(key: "j", modifiers: [.command, .shift])),
            KeyboardShortcut(action: .viewHistory, keyCombination: KeyCombination(key: "y", modifiers: [.command])),
            KeyboardShortcut(action: .copyLink, keyCombination: KeyCombination(key: "c", modifiers: [.command, .option])),
            KeyboardShortcut(action: .expandAllFolders, keyCombination: KeyCombination(key: "e", modifiers: [.command, .shift]))
        ]
    }
}