//
//  NookCommands.swift
//  Nook
//
//  Menu bar commands for the Nook browser application
//

import AppKit
import SwiftUI
import WebKit

struct NookCommands: Commands {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.nookSettings) var nookSettings
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init(browserManager: BrowserManager, windowRegistry: WindowRegistry, shortcutManager: KeyboardShortcutManager) {
        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
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

        // App Menu Section (under Nook)
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Make Nook Default Browser") {
                browserManager.setAsDefaultBrowser()
            }
            
            Button("Check for Updates...") {
                appDelegate.updaterController.checkForUpdates(nil)
            }
        }
        
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

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab") {
                browserManager.undoCloseTab()
            }
            .modifier(dynamicShortcut(.undoCloseTab))
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

            Button("Close Tab") {
                if windowRegistry.activeWindow?.isCommandPaletteVisible == true {
                    windowRegistry.activeWindow?.commandPalette?.close()
                } else {
                    browserManager.closeCurrentTab()
                }
            }
            .modifier(dynamicShortcut(.closeTab))
            .disabled(browserManager.tabManager.tabs.isEmpty)
            Divider()
            Button("Open Command Bar") {
                let currentURL = browserManager.currentTabForActiveWindow()?.url.absoluteString ?? ""
                windowRegistry.activeWindow?.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Copy Current URL") {
                browserManager.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserManager.currentTabForActiveWindow() == nil)
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
                browserManager.requestPiPForCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.togglePictureInPicture))
            .disabled(
                browserManager.currentTabForActiveWindow() == nil
                    || !(browserManager.currentTabHasVideoContent()
                        || browserManager.currentTabHasPiPActive())
            )
        }

        // View commands
        CommandGroup(after: .windowSize) {

            Button("Find in Page") {
                browserManager.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Reload Page") {
                browserManager.refreshCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Zoom In") {
                browserManager.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Zoom Out") {
                browserManager.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Actual Size") {
                browserManager.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserManager.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Web Inspector") {
                browserManager.openWebInspector()
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Force Quit App") {
                browserManager.showQuitDialog()
            }
            .modifier(dynamicShortcut(.closeBrowser))

            Divider()

            Button(browserManager.currentTabIsMuted() ? "Unmute Audio" : "Mute Audio") {
                browserManager.toggleMuteCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserManager.currentTabForActiveWindow() == nil
                    || !browserManager.currentTabHasAudioContent())
        }

        Group {
            CommandMenu("Privacy") {
                Menu("Clear Cookies") {
                    Button("Clear Cookies for Current Site") {
                        browserManager.clearCurrentPageCookies()
                    }
                    .disabled(browserManager.currentTabForActiveWindow()?.url.host == nil)

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
                    .disabled(browserManager.currentTabForActiveWindow()?.url.host == nil)

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

            if nookSettings.experimentalExtensions {
                CommandMenu("Extensions") {
                    Button("Install Extension...") {
                        browserManager.showExtensionInstallDialog()
                    }
                    .modifier(dynamicShortcut(.installExtension))

                    Button("Manage Extensions...") {
                        openSettings()
                        nookSettings.currentSettingsTab = .extensions
                    }

                    if #available(macOS 15.5, *) {
                        Divider()
                        Button("Open Popup Console") {
                            browserManager.extensionManager?.showPopupConsole()
                        }
                    }
                }
            }

            CommandMenu("Appearance") {
                Button("Customize Space Gradient...") {
                    browserManager.showGradientEditor()
                }
                .modifier(dynamicShortcut(.customizeSpaceGradient))
                .disabled(browserManager.tabManager.currentSpace == nil)

                Divider()

                Button("Create Boosts") {
                    browserManager.showBoostsDialog()
                }
                .modifier(dynamicShortcut(.createBoost))
                .disabled(browserManager.currentTabForActiveWindow() == nil)
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
