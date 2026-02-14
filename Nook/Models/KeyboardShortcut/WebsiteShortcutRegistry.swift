//
//  WebsiteShortcutRegistry.swift
//  Nook
//
//  Created by AI Assistant on 2025.
//
//  Database of known web application keyboard shortcuts for conflict detection.
//  When Nook and a website share the same shortcut, we enable a "double-press"
//  system where the first press goes to the website, and the second press
//  (within 1 second) goes to Nook.
//

import Foundation

// MARK: - Website Shortcut Profile

/// Represents a website/webapp and its keyboard shortcuts that may conflict with Nook.
struct WebsiteShortcutProfile: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let domainPatterns: [String]      // Glob patterns like "*.figma.com", "figma.com"
    let shortcuts: [WebsiteShortcut]
    let icon: String?                 // SF Symbol name if available
    
    init(id: UUID = UUID(), name: String, domainPatterns: [String], shortcuts: [WebsiteShortcut], icon: String? = nil) {
        self.id = id
        self.name = name
        self.domainPatterns = domainPatterns
        self.shortcuts = shortcuts
        self.icon = icon
    }
    
    /// Check if a URL matches this profile's domain patterns
    func matches(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return domainPatterns.contains { pattern in
            matchesPattern(host: host, pattern: pattern.lowercased())
        }
    }
    
    private func matchesPattern(host: String, pattern: String) -> Bool {
        // Handle wildcard patterns like "*.figma.com"
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2)) // Remove "*."
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host == pattern
    }
    
    /// Check if this profile has a shortcut that matches the given key combination
    func hasShortcut(matching keyCombination: KeyCombination) -> WebsiteShortcut? {
        shortcuts.first { $0.matches(keyCombination) }
    }
}

// MARK: - Website Shortcut

/// A single keyboard shortcut used by a website.
struct WebsiteShortcut: Codable, Hashable {
    let key: String                    // Key character (lowercase)
    let modifiers: Modifiers           // Modifier keys
    let description: String?           // What the shortcut does in the web app
    
    init(key: String, modifiers: Modifiers = [], description: String? = nil) {
        self.key = key.lowercased()
        self.modifiers = modifiers
        self.description = description
    }
    
    /// Check if this shortcut matches a KeyCombination
    func matches(_ keyCombination: KeyCombination) -> Bool {
        return key.lowercased() == keyCombination.key.lowercased() && 
               modifiers == keyCombination.modifiers
    }
    
    /// Create lookup key for matching with Nook shortcuts
    var lookupKey: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }
}

// MARK: - Default Website Profiles

extension WebsiteShortcutProfile {
    
    /// All known website profiles with their shortcuts
    static let knownProfiles: [WebsiteShortcutProfile] = [
        // MARK: - Figma
        .init(
            name: "Figma",
            domainPatterns: ["*.figma.com", "figma.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Search / Quick Actions"),
                .init(key: "d", modifiers: [.command], description: "Duplicate"),
                .init(key: "+", modifiers: [.command], description: "Zoom In"),
                .init(key: "-", modifiers: [.command], description: "Zoom Out"),
                .init(key: "0", modifiers: [.command], description: "Zoom to 100%"),
                .init(key: "\\", modifiers: [.command], description: "Show/Hide UI"),
                .init(key: ".", modifiers: [.command], description: "Show/Hide UI"),
                .init(key: "c", modifiers: [.command, .option], description: "Copy properties"),
                .init(key: "v", modifiers: [.command, .option], description: "Paste properties"),
                .init(key: "k", modifiers: [.command, .option], description: "Create component"),
                .init(key: "b", modifiers: [.command, .option], description: "Detach instance"),
                .init(key: "c", modifiers: [.command, .shift], description: "Copy as PNG"),
                .init(key: "g", modifiers: [.shift], description: "Layout grids"),
            ],
            icon: "paintbrush.pointed"
        ),
        
        // MARK: - Notion
        .init(
            name: "Notion",
            domainPatterns: ["*.notion.so", "*.notion.site", "notion.so", "notion.site"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Quick Find / Search"),
                .init(key: "p", modifiers: [.command], description: "Quick Find / Search"),
                .init(key: "n", modifiers: [.command], description: "New Page"),
                .init(key: "[", modifiers: [.command], description: "Go Back"),
                .init(key: "]", modifiers: [.command], description: "Go Forward"),
                .init(key: "l", modifiers: [.command], description: "Copy Page URL"),
                .init(key: "s", modifiers: [.command], description: "Sync / Save"),
                .init(key: "f", modifiers: [.command], description: "Find in Page"),
                .init(key: "/", modifiers: [], description: "Search"),
                .init(key: "n", modifiers: [.command, .shift], description: "New Notion Window"),
                .init(key: "u", modifiers: [.command, .shift], description: "Go to Parent Page"),
                .init(key: "d", modifiers: [.command, .shift], description: "Insert Date"),
                .init(key: "t", modifiers: [.command, .shift], description: "Insert Time"),
                .init(key: "m", modifiers: [.command, .shift], description: "Add Comment"),
                .init(key: "a", modifiers: [.command, .shift], description: "Show Comments"),
            ],
            icon: "square.dashed"
        ),
        
        // MARK: - Linear
        .init(
            name: "Linear",
            domainPatterns: ["*.linear.app", "linear.app"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Command Menu"),
                .init(key: "enter", modifiers: [.command], description: "Save / Submit"),
                .init(key: "escape", modifiers: [], description: "Back / Close"),
                .init(key: "c", modifiers: [.command, .shift], description: "Copy Current URL"),
                .init(key: "a", modifiers: [.command], description: "Select All"),
                .init(key: "a", modifiers: [.command, .option], description: "Select All in Group"),
                .init(key: "/", modifiers: [], description: "Open Search"),
                .init(key: "?", modifiers: [.shift], description: "Open Help"),
                .init(key: "i", modifiers: [.command], description: "Open Details Sidebar"),
                .init(key: "b", modifiers: [.command], description: "Toggle List/Board View"),
                .init(key: "f", modifiers: [], description: "Add Filter"),
                .init(key: "x", modifiers: [], description: "Select in List"),
                .init(key: "space", modifiers: [], description: "Peek into Issue"),
            ],
            icon: "arrow.triangle.branch"
        ),
        
        // MARK: - Gmail
        .init(
            name: "Gmail",
            domainPatterns: ["mail.google.com"],
            shortcuts: [
                // Note: Gmail uses many single-key shortcuts, but most don't conflict with Nook
                // since Nook requires modifiers for most actions. We only track conflicts.
                .init(key: "enter", modifiers: [.command], description: "Send"),
                .init(key: "c", modifiers: [.control, .shift], description: "Add CC"),
                .init(key: "b", modifiers: [.control, .shift], description: "Add BCC"),
                .init(key: "k", modifiers: [.control, .shift], description: "Insert Link"),
                .init(key: "/", modifiers: [], description: "Open Search"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
            ],
            icon: "envelope"
        ),
        
        // MARK: - GitHub
        .init(
            name: "GitHub",
            domainPatterns: ["github.com", "*.github.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Command Palette"),
                .init(key: "p", modifiers: [.command, .shift], description: "Command Palette (VS Code in Codespaces)"),
                .init(key: "/", modifiers: [], description: "Focus Search"),
                .init(key: "s", modifiers: [], description: "Focus Search"),
                .init(key: "g", modifiers: [], description: "Go to... (prefix key)"),
                .init(key: "?", modifiers: [.shift], description: "Show Keyboard Shortcuts"),
            ],
            icon: "chevron.left.forwardslash.chevron.right"
        ),
        
        // MARK: - Slack
        .init(
            name: "Slack",
            domainPatterns: ["*.slack.com", "slack.com", "app.slack.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Quick Switcher"),
                .init(key: "n", modifiers: [.command], description: "Compose New Message"),
                .init(key: "[", modifiers: [.command], description: "Previous Channel in History"),
                .init(key: "]", modifiers: [.command], description: "Next Channel in History"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
                .init(key: "escape", modifiers: [], description: "Mark All Read"),
                .init(key: "k", modifiers: [.command, .shift], description: "Open Direct Messages"),
                .init(key: "t", modifiers: [.command, .shift], description: "Open Threads"),
                .init(key: "l", modifiers: [.command, .shift], description: "Open Channel Browser"),
                .init(key: "i", modifiers: [.command, .shift], description: "Open Channel Info"),
                .init(key: "m", modifiers: [.command, .shift], description: "Open Recent Mentions"),
                .init(key: ".", modifiers: [.command], description: "Toggle Right Pane"),
            ],
            icon: "bubble.left.and.bubble.right"
        ),
        
        // MARK: - Google Docs
        .init(
            name: "Google Docs",
            domainPatterns: ["docs.google.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Insert Link"),
                .init(key: "s", modifiers: [.command], description: "Save"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
                .init(key: "c", modifiers: [.command, .shift], description: "Word Count"),
                .init(key: "p", modifiers: [.command], description: "Print"),
                .init(key: "f", modifiers: [.command], description: "Find"),
                .init(key: "h", modifiers: [.command], description: "Find and Replace"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
                .init(key: "z", modifiers: [.command, .shift], description: "Redo"),
                .init(key: "0", modifiers: [.command, .option], description: "Normal Text"),
                .init(key: "1", modifiers: [.command, .option], description: "Heading 1"),
                .init(key: "2", modifiers: [.command, .option], description: "Heading 2"),
            ],
            icon: "doc.text"
        ),
        
        // MARK: - Google Sheets
        .init(
            name: "Google Sheets",
            domainPatterns: ["sheets.google.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Search Menus"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
                .init(key: "s", modifiers: [.command], description: "Save"),
                .init(key: "f", modifiers: [.command], description: "Find"),
                .init(key: "h", modifiers: [.command], description: "Find and Replace"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
                .init(key: "z", modifiers: [.command, .shift], description: "Redo"),
            ],
            icon: "tablecells"
        ),
        
        // MARK: - Google Slides
        .init(
            name: "Google Slides",
            domainPatterns: ["slides.google.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Insert Link"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
                .init(key: "s", modifiers: [.command], description: "Save"),
                .init(key: "p", modifiers: [.command], description: "Print"),
                .init(key: "f", modifiers: [.command], description: "Find"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
            ],
            icon: "play.rectangle"
        ),
        
        // MARK: - YouTube
        .init(
            name: "YouTube",
            domainPatterns: ["youtube.com", "*.youtube.com", "youtu.be"],
            shortcuts: [
                // YouTube uses single-key shortcuts that don't usually conflict with Nook
                // since Nook requires modifiers. Including for completeness.
                .init(key: "k", modifiers: [], description: "Play/Pause"),
                .init(key: "j", modifiers: [], description: "Rewind 10s"),
                .init(key: "l", modifiers: [], description: "Forward 10s"),
                .init(key: "f", modifiers: [], description: "Fullscreen"),
                .init(key: "m", modifiers: [], description: "Mute"),
                .init(key: "t", modifiers: [], description: "Theater Mode"),
                .init(key: "i", modifiers: [], description: "Mini Player"),
                .init(key: "/", modifiers: [], description: "Focus Search"),
                .init(key: "escape", modifiers: [], description: "Exit Fullscreen"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
            ],
            icon: "play.rectangle.fill"
        ),
        
        // MARK: - Twitter / X
        .init(
            name: "X (Twitter)",
            domainPatterns: ["twitter.com", "x.com", "*.twitter.com"],
            shortcuts: [
                // Single-key shortcuts, low conflict with Nook
                .init(key: "j", modifiers: [], description: "Next Tweet"),
                .init(key: "k", modifiers: [], description: "Previous Tweet"),
                .init(key: "n", modifiers: [], description: "New Tweet"),
                .init(key: "m", modifiers: [], description: "New DM"),
                .init(key: "/", modifiers: [], description: "Search"),
                .init(key: "?", modifiers: [.shift], description: "Show Keyboard Shortcuts"),
                .init(key: "enter", modifiers: [.command], description: "Send Tweet"),
            ],
            icon: "bird"
        ),
        
        // MARK: - Discord
        .init(
            name: "Discord",
            domainPatterns: ["discord.com", "*.discord.com", "discordapp.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Quick Switcher"),
                .init(key: "n", modifiers: [.command], description: "New DM"),
                .init(key: "f", modifiers: [.command], description: "Find"),
                .init(key: "/", modifiers: [], description: "Quick Search"),
                .init(key: "escape", modifiers: [], description: "Close Modal"),
                .init(key: "]", modifiers: [.command], description: "Next Channel"),
                .init(key: "[", modifiers: [.command], description: "Previous Channel"),
                .init(key: "m", modifiers: [.command], description: "Mute"),
                .init(key: "/", modifiers: [.command], description: "Show Keyboard Shortcuts"),
            ],
            icon: "bubble.left.and.bubble.right.fill"
        ),
        
        // MARK: - Asana
        .init(
            name: "Asana",
            domainPatterns: ["asana.com", "*.asana.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Quick Search"),
                .init(key: "n", modifiers: [.command], description: "New Task"),
                .init(key: "f", modifiers: [.command], description: "Find"),
                .init(key: "s", modifiers: [], description: "Focus Search Bar"),
                .init(key: "escape", modifiers: [], description: "Cancel / Close"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
            ],
            icon: "checklist"
        ),
        
        // MARK: - Trello
        .init(
            name: "Trello",
            domainPatterns: ["trello.com", "*.trello.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Search"),
                .init(key: "n", modifiers: [.command], description: "New Board"),
                .init(key: "f", modifiers: [.command], description: "Filter Cards"),
                .init(key: "s", modifiers: [], description: "Focus Search"),
                .init(key: "escape", modifiers: [], description: "Close"),
            ],
            icon: "rectangle.stack"
        ),
        
        // MARK: - Jira
        .init(
            name: "Jira",
            domainPatterns: ["*.atlassian.net", "*.atlassian.com", "jira.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Quick Search"),
                .init(key: "j", modifiers: [], description: "Next Issue"),
                .init(key: "k", modifiers: [], description: "Previous Issue"),
                .init(key: "/", modifiers: [], description: "Quick Search"),
                .init(key: "c", modifiers: [], description: "Create Issue"),
                .init(key: "escape", modifiers: [], description: "Cancel"),
            ],
            icon: "list.bullet.rectangle"
        ),
        
        // MARK: - Spotify Web Player
        .init(
            name: "Spotify",
            domainPatterns: ["open.spotify.com", "spotify.com"],
            shortcuts: [
                .init(key: "space", modifiers: [], description: "Play/Pause"),
                .init(key: "right", modifiers: [], description: "Next Track"),
                .init(key: "left", modifiers: [], description: "Previous Track"),
                .init(key: "up", modifiers: [], description: "Volume Up"),
                .init(key: "down", modifiers: [], description: "Volume Down"),
                .init(key: "m", modifiers: [], description: "Mute"),
                .init(key: "s", modifiers: [], description: "Shuffle"),
                .init(key: "r", modifiers: [], description: "Repeat"),
                .init(key: "f", modifiers: [.command], description: "Search"),
            ],
            icon: "music.note"
        ),
        
        // MARK: - Canva
        .init(
            name: "Canva",
            domainPatterns: ["canva.com", "*.canva.com"],
            shortcuts: [
                .init(key: "k", modifiers: [.command], description: "Search"),
                .init(key: "c", modifiers: [.command], description: "Copy"),
                .init(key: "v", modifiers: [.command], description: "Paste"),
                .init(key: "z", modifiers: [.command], description: "Undo"),
                .init(key: "z", modifiers: [.command, .shift], description: "Redo"),
                .init(key: "s", modifiers: [.command], description: "Save"),
                .init(key: "d", modifiers: [.command], description: "Duplicate"),
                .init(key: "g", modifiers: [.command], description: "Group"),
                .init(key: "+", modifiers: [.command], description: "Zoom In"),
                .init(key: "-", modifiers: [.command], description: "Zoom Out"),
                .init(key: "0", modifiers: [.command], description: "Reset Zoom"),
            ],
            icon: "paintpalette"
        ),
    ]
}

// MARK: - Shortcut Conflict Info

/// Information about a detected shortcut conflict for toast display
struct ShortcutConflictInfo: Equatable {
    let keyCombination: KeyCombination
    let websiteName: String
    let websiteShortcutDescription: String?
    let nookActionName: String
    let timestamp: Date
    let windowId: UUID
    
    init(keyCombination: KeyCombination, websiteName: String, websiteShortcutDescription: String?, nookActionName: String, windowId: UUID) {
        self.keyCombination = keyCombination
        self.websiteName = websiteName
        self.websiteShortcutDescription = websiteShortcutDescription
        self.nookActionName = nookActionName
        self.timestamp = Date()
        self.windowId = windowId
    }
    
    static func == (lhs: ShortcutConflictInfo, rhs: ShortcutConflictInfo) -> Bool {
        lhs.keyCombination == rhs.keyCombination && 
        lhs.websiteName == rhs.websiteName && 
        lhs.windowId == rhs.windowId
    }
}

// MARK: - Settings

extension WebsiteShortcutProfile {
    /// UserDefaults key for the feature toggle
    static let websiteShortcutDetectionEnabledKey = "websiteShortcutDetectionEnabled"
    
    /// Check if the website shortcut detection feature is enabled
    static var isFeatureEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: websiteShortcutDetectionEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: websiteShortcutDetectionEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: websiteShortcutDetectionEnabledKey)
        }
    }
}