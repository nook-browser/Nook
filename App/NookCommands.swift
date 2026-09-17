//
//  NookCommands.swift
//  Nook
//
//  Menu bar commands for the Nook browser application
//

import AppKit
import SwiftUI
import WebKit
import NookWeb

struct NookCommands: Commands {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    let tabOrganizerManager: TabOrganizerManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.nookSettings) var nookSettings

    init(browserManager: BrowserManager, windowRegistry: WindowRegistry, shortcutManager: KeyboardShortcutManager, tabOrganizerManager: TabOrganizerManager) {
        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
        self.tabOrganizerManager = tabOrganizerManager
    }

    // MARK: - Dynamic Keyboard Shortcuts

    /// Returns the key equivalent for a given action, or nil if disabled
    private func keyEquivalent(for action: ShortcutAction) -> KeyEquivalent? {
        guard let shortcut = shortcutManager.shortcut(for: action),
              shortcut.isEnabled else { return nil }
        // Handle special keys
        switch shortcut.keyCombination.key.lowercased() {
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "tab": return .tab
        case "space": return .space
        case "up", "uparrow": return .upArrow
        case "down", "downarrow": return .downArrow
        case "left", "leftarrow": return .leftArrow
        case "right", "rightarrow": return .rightArrow
        case "home": return .home
        case "end": return .end
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        case "clear": return .clear
        default:
            // Handle single character keys
            if shortcut.keyCombination.key.count == 1,
               let char = shortcut.keyCombination.key.first {
                return KeyEquivalent(char)
            }
            return nil
        }
    }

    /// Returns the event modifiers for a given action
    private func eventModifiers(for action: ShortcutAction) -> EventModifiers {
        guard let shortcut = shortcutManager.shortcut(for: action),
              shortcut.isEnabled else { return [] }
        var modifiers: EventModifiers = []
        if shortcut.keyCombination.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.keyCombination.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.keyCombination.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.keyCombination.modifiers.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// View extension to apply dynamic keyboard shortcut if enabled
    private func dynamicShortcut(_ action: ShortcutAction) -> some ViewModifier {
        DynamicShortcutModifier(
            keyEquivalent: keyEquivalent(for: action),
            modifiers: eventModifiers(for: action)
        )
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .windowList) {}

        // The Settings scene supplies the standard Settings… item at ⌘,
        CommandGroup(after: .appSettings) {
            Button("Import from another Browser") {
                browserManager.dialogManager.showDialog(
                    BrowserImportDialog(
                        onCancel: {
                            browserManager.dialogManager.closeDialog()
                        }
                    )
                )
            }
        }

        // Replace the standard Quit menu item to route through showQuitDialog(),
        // which respects the "warn before quitting" setting
        CommandGroup(replacing: .appTermination) {
            Button("Quit Nook") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        // App Menu Section (under Nook)
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Make Nook Default Browser") {
                browserManager.setAsDefaultBrowser()
            }

            Button("Check for Updates...") {
                browserManager.appDelegate?.updaterController.checkForUpdates(nil)
            }
        }
        

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .modifier(dynamicShortcut(.undoCloseTab))

            Button("Reopen Closed Tab") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                windowRegistry.activeWindow?.commandPalette?.open()
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window") {
                browserManager.createNewWindow()
            }
            .modifier(dynamicShortcut(.newWindow))
            
            Button("New Incognito Window") {
                browserManager.createIncognitoWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Divider()
            Button("Open Command Bar") {
                let currentURL = browserManager.tabs.activeWindowSession?.url.absoluteString ?? ""
                windowRegistry.activeWindow?.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Copy Current URL") {
                browserManager.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserManager.tabs.activeWindowSession == nil)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserManager.toggleSidebar()
            }
            .modifier(dynamicShortcut(.toggleSidebar))

            Button("Toggle AI Assistant") {
                browserManager.toggleAISidebar()
            }
            .modifier(dynamicShortcut(.toggleAIAssistant))
            .disabled(!nookSettings.showAIAssistant)

            Button("Toggle Picture in Picture") {
                browserManager.tabs.activeWindowSession?.requestPictureInPicture()
            }
            .modifier(dynamicShortcut(.togglePictureInPicture))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || !(browserManager.tabs.activeWindowSession.map { $0.hasVideoContent || $0.hasPiPActive } ?? false)
            )

            Divider()

            Button("Organize Tabs") {
                if let spaceID = windowRegistry.activeWindow?.spaceID {
                    Task {
                        await tabOrganizerManager.organizeTabs(in: spaceID, using: browserManager.tabs)
                    }
                }
            }
            .modifier(dynamicShortcut(.organizeTabs))
            .disabled(
                tabOrganizerManager.isOrganizing
                    || windowRegistry.activeWindow?.spaceID == nil
            )
        }

        // View commands
        CommandGroup(after: .windowSize) {

            Button("Find in Page") {
                browserManager.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Reload Page") {
                browserManager.tabs.activeWindowSession?.refresh()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Zoom In") {
                browserManager.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Zoom Out") {
                browserManager.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Actual Size") {
                browserManager.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserManager.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Web Inspector") {
                browserManager.openWebInspector()
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button(browserManager.tabs.activeWindowSession?.isAudioMuted == true ? "Unmute Audio" : "Mute Audio") {
                browserManager.tabs.activeWindowSession?.toggleMute()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || browserManager.tabs.activeWindowSession?.hasAudioContent != true)
        }

        Group {
            CommandMenu("Privacy") {
                Menu("Clear Cookies") {
                    Button("Clear Cookies for Current Site") {
                        browserManager.clearCurrentPageCookies()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Expired Cookies") {
                        browserManager.clearExpiredCookies()
                    }

                    Divider()

                    Button("Clear All Cookies") {
                        browserManager.clearAllCookies()
                    }

                    Divider()

                    Button("Clear Third-Party Cookies") {
                        browserManager.clearThirdPartyCookies()
                    }

                    Button("Clear High-Risk Cookies") {
                        browserManager.clearHighRiskCookies()
                    }
                }

                Menu("Clear Cache") {
                    Button("Clear Cache for Current Site") {
                        browserManager.clearCurrentPageCache()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Stale Cache") {
                        browserManager.clearStaleCache()
                    }

                    Button("Clear Disk Cache") {
                        browserManager.clearDiskCache()
                    }

                    Button("Clear Memory Cache") {
                        browserManager.clearMemoryCache()
                    }

                    Divider()

                    Button("Clear All Cache") {
                        browserManager.clearAllCache()
                    }

                    Divider()

                    Button("Clear Personal Data Cache") {
                        browserManager.clearPersonalDataCache()
                    }

                    Button("Clear Favicon Cache") {
                        browserManager.clearFaviconCache()
                    }
                }

                Divider()

                Button("Privacy Cleanup") {
                    browserManager.performPrivacyCleanup()
                }

                Button("Clear Browsing History") {
                    browserManager.historyManager.clearHistory()
                }

                Button("Clear All Website Data") {
                    Task {
                        let dataStore = WKWebsiteDataStore.default()
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
                    }
                }
            }

            CommandMenu("Extensions") {
                Button("Toggle Extension Library") {
                    browserManager.toggleExtensionLibrary()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Install Extension...") {
                    browserManager.showExtensionInstallDialog()
                }
                .modifier(dynamicShortcut(.installExtension))

                Button("Manage Extensions...") {
                    SettingsNavigation.shared.currentSettingsTab = .extensions
                    openSettings()
                }

                Divider()

                Button("Chrome Web Store") {
                    browserManager.tabs.activeWindowSession?.load(URL(string: "https://chromewebstore.google.com")!)
                }

                #if DEBUG
                Divider()
                Button("Open Popup Console") {
                    browserManager.extensionManager?.showPopupConsole()
                }
                #endif
            }

            CommandMenu("Appearance") {
                Button("Space Settings...") {
                    browserManager.showSpaceSettings()
                }
                .modifier(dynamicShortcut(.customizeSpaceGradient))
                .disabled(windowRegistry.activeWindow?.spaceID == nil)
            }
        }
    }
}

// MARK: - Dynamic Shortcut Modifier

/// View modifier that conditionally applies a keyboard shortcut based on user preferences
struct DynamicShortcutModifier: ViewModifier {
    let keyEquivalent: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let keyEquivalent = keyEquivalent {
            content.keyboardShortcut(keyEquivalent, modifiers: modifiers)
        } else {
            content
        }
    }
}
