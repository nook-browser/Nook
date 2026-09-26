// Licensed under GPL-3.0. See LICENSE.
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

        CommandGroup(replacing: .appInfo) {
            Button("About Nook", systemImage: "info.circle") {
                browserManager.showAbout()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                browserManager.openSettings(tab: .general)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!nookSettings.didFinishOnboarding)

            Button("Import from another Browser", systemImage: "square.and.arrow.down") {
                browserManager.showBrowserImportDialog()
            }
            .disabled(!nookSettings.didFinishOnboarding)
        }

        // Replace the standard Quit menu item to route through showQuitDialog(),
        // which respects the "warn before quitting" setting
        CommandGroup(replacing: .appTermination) {
            Button("Quit Nook", systemImage: "power") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        // App Menu Section (under Nook)
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Make Nook Default Browser", systemImage: "globe") {
                browserManager.setAsDefaultBrowser()
            }

            Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") {
                browserManager.appDelegate?.updaterController.checkForUpdates(nil)
            }
        }
        

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab", systemImage: "arrow.uturn.backward") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .modifier(dynamicShortcut(.undoCloseTab))

            Button("Reopen Closed Tab", systemImage: "arrow.uturn.forward") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab", systemImage: "plus.square") {
                windowRegistry.activeWindow?.commandPalette?.open()
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window", systemImage: "macwindow.badge.plus") {
                browserManager.createNewWindow()
            }
            .modifier(dynamicShortcut(.newWindow))
            
            Button("New Incognito Window", systemImage: "eye.slash") {
                browserManager.createIncognitoWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Divider()
            Button("Open Command Bar", systemImage: "command") {
                let currentURL = browserManager.tabs.activeWindowSession?.url.absoluteString ?? ""
                windowRegistry.activeWindow?.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Copy Current URL", systemImage: "link") {
                browserManager.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()
            Button("Print…", systemImage: "printer") {
                browserManager.printCurrentPage()
            }
            .modifier(dynamicShortcut(.printPage))
            .disabled(browserManager.tabs.activeWindowSession == nil)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar", systemImage: "sidebar.left") {
                browserManager.toggleSidebar()
            }
            .modifier(dynamicShortcut(.toggleSidebar))

            Button("Toggle AI Assistant", systemImage: "sparkles") {
                browserManager.toggleAISidebar()
            }
            .modifier(dynamicShortcut(.toggleAIAssistant))
            .disabled(!nookSettings.showAIAssistant)

            Button("Toggle Picture in Picture", systemImage: "pip") {
                browserManager.tabs.activeWindowSession?.requestPictureInPicture()
            }
            .modifier(dynamicShortcut(.togglePictureInPicture))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || !(browserManager.tabs.activeWindowSession.map { $0.hasVideoContent || $0.hasPiPActive } ?? false)
            )

            if tabOrganizerManager.isAvailable {
                Divider()

                Button("Organize Tabs", systemImage: "rectangle.stack") {
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
        }

        // View commands
        CommandGroup(after: .windowSize) {

            Button("Find in Page", systemImage: "magnifyingglass") {
                browserManager.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Reload Page", systemImage: "arrow.clockwise") {
                browserManager.tabs.activeWindowSession?.refresh()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                browserManager.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                browserManager.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Actual Size", systemImage: "1.magnifyingglass") {
                browserManager.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)", systemImage: "arrow.triangle.2.circlepath") {
                browserManager.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Web Inspector", systemImage: "chevron.left.forwardslash.chevron.right") {
                browserManager.openWebInspector()
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button(
                browserManager.tabs.activeWindowSession?.isAudioMuted == true ? "Unmute Audio" : "Mute Audio",
                systemImage: browserManager.tabs.activeWindowSession?.isAudioMuted == true ? "speaker.wave.2" : "speaker.slash"
            ) {
                browserManager.tabs.activeWindowSession?.toggleMute()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || browserManager.tabs.activeWindowSession?.hasAudioContent != true)
        }

        Group {
            CommandMenu("Privacy") {
                Menu("Clear Cookies", systemImage: "circle.grid.3x3") {
                    Button("Clear Cookies for Current Site", systemImage: "globe") {
                        browserManager.clearCurrentPageCookies()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Expired Cookies", systemImage: "clock.badge.xmark") {
                        browserManager.clearExpiredCookies()
                    }

                    Divider()

                    Button("Clear All Cookies", systemImage: "trash") {
                        browserManager.clearAllCookies()
                    }

                    Divider()

                    Button("Clear Third-Party Cookies", systemImage: "person.2.slash") {
                        browserManager.clearThirdPartyCookies()
                    }

                    Button("Clear High-Risk Cookies", systemImage: "exclamationmark.shield") {
                        browserManager.clearHighRiskCookies()
                    }
                }

                Menu("Clear Cache", systemImage: "internaldrive") {
                    Button("Clear Cache for Current Site", systemImage: "globe") {
                        browserManager.clearCurrentPageCache()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Stale Cache", systemImage: "clock.arrow.circlepath") {
                        browserManager.clearStaleCache()
                    }

                    Button("Clear Disk Cache", systemImage: "internaldrive") {
                        browserManager.clearDiskCache()
                    }

                    Button("Clear Memory Cache", systemImage: "memorychip") {
                        browserManager.clearMemoryCache()
                    }

                    Divider()

                    Button("Clear All Cache", systemImage: "trash") {
                        browserManager.clearAllCache()
                    }

                    Divider()

                    Button("Clear Personal Data Cache", systemImage: "person.crop.circle.badge.xmark") {
                        browserManager.clearPersonalDataCache()
                    }

                    Button("Clear Favicon Cache", systemImage: "photo") {
                        browserManager.clearFaviconCache()
                    }
                }

                Divider()

                Button("Privacy Cleanup", systemImage: "hand.raised") {
                    browserManager.performPrivacyCleanup()
                }

                Button("Clear Browsing History", systemImage: "clock.arrow.circlepath") {
                    browserManager.historyManager.clearHistory()
                }

                Button("Clear All Website Data", systemImage: "trash") {
                    Task {
                        // Tabs use one store per space; Peek and the base config have used the default.
                        let tabs = browserManager.tabs
                        let dataStores: [WKWebsiteDataStore] = tabs.orderedSpaces.compactMap { tabs.profile(forSpace: $0.id)?.dataStore }
                            + [WKWebsiteDataStore.default()]
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        for dataStore in dataStores {
                            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
                        }
                    }
                }
            }

            CommandMenu("Extensions") {
                Button("Toggle Extension Library", systemImage: "puzzlepiece.extension") {
                    browserManager.toggleExtensionLibrary()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Install Extension...", systemImage: "plus.app") {
                    browserManager.showExtensionInstallDialog()
                }
                .modifier(dynamicShortcut(.installExtension))

                Button("Manage Extensions...", systemImage: "gearshape") {
                    browserManager.openSettings(tab: .extensions)
                }

                Divider()

                Button("Chrome Web Store", systemImage: "storefront") {
                    browserManager.tabs.activeWindowSession?.load(URL(string: "https://chromewebstore.google.com")!)
                }

                #if DEBUG
                Divider()
                Button("Open Popup Console", systemImage: "terminal") {
                    browserManager.extensionManager?.showPopupConsole()
                }
                #endif
            }

            CommandMenu("Appearance") {
                Button("Space Settings...", systemImage: "paintpalette") {
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
