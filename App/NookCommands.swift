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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .windowList) {}
        // Use the native Settings menu (no replacement of .appSettings)

        // App Menu Section (under Nook)
        CommandGroup(after: .appInfo) {
            Button("Make Nook Default Browser") {
                browserManager.setAsDefaultBrowser()
            }
        }

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab") {
                browserManager.undoCloseTab()
            }
            .keyboardShortcut("z", modifiers: .command)
        }

        // File Section
        CommandGroup(after: .newItem) {

            Button("Check for Updates...") {
                appDelegate.updaterController.checkForUpdates(nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Import from another Browser") {
                browserManager.dialogManager.showDialog(
                    BrowserImportDialog(
                        onCancel: {
                            browserManager.dialogManager.closeDialog()
                        }
                    )
                )
            }
            Divider()

            Button("New Tab") {
                print("🍔 [Menu] New Tab button pressed - activeWindowState: \(String(describing: browserManager.activeWindowState?.id))")
                browserManager.activeWindowState?.commandPalette?.open()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("New Window") {
                browserManager.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Close Tab") {
                if browserManager.activeWindowState?.isCommandPaletteVisible == true {
//                    browserManager.closeCommandPalette(for: browserManager.activeWindowState)
                } else {
                    browserManager.closeCurrentTab()
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(browserManager.tabManager.tabs.isEmpty)

            Button("Copy Current URL") {
                browserManager.copyCurrentURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(browserManager.currentTabForActiveWindow() == nil)

        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserManager.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Toggle AI Assistant") {
                browserManager.toggleAISidebar()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!browserManager.settingsManager.showAIAssistant)

            Button("Toggle Picture in Picture") {
                browserManager.requestPiPForCurrentTabInActiveWindow()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(
                browserManager.currentTabForActiveWindow() == nil
                    || !(browserManager.currentTabHasVideoContent()
                        || browserManager.currentTabHasPiPActive())
            )
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("New URL / Search") {
//                browserManager.openCommandPaletteWithCurrentURL()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Find in Page") {
                browserManager.showFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Reload Page") {
                browserManager.refreshCurrentTabInActiveWindow()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            // Zoom controls
            Button("Zoom In") {
                browserManager.zoomInCurrentTab()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Zoom Out") {
                browserManager.zoomOutCurrentTab()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Actual Size") {
                browserManager.resetZoomCurrentTab()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserManager.hardReloadCurrentPage()
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Web Inspector") {
                browserManager.openWebInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Force Quit App") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: .command)

            Divider()

            Button(browserManager.currentTabIsMuted() ? "Unmute Audio" : "Mute Audio") {
                browserManager.toggleMuteCurrentTabInActiveWindow()
            }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(
                browserManager.currentTabForActiveWindow() == nil
                    || !browserManager.currentTabHasAudioContent())
        }

        // Privacy/Cookie Commands
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

        // Extensions Commands
        if browserManager.settingsManager.experimentalExtensions {
            CommandMenu("Extensions") {
                Button("Install Extension...") {
                    browserManager.showExtensionInstallDialog()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Manage Extensions...") {
                    // Open native Settings to Extensions pane
                    openSettings()
                    browserManager.settingsManager.currentSettingsTab = .extensions
                }

                if #available(macOS 15.5, *) {
                    Divider()
                    Button("Open Popup Console") {
                        browserManager.extensionManager?.showPopupConsole()
                    }
                }
            }
        }

        // Appearance Commands
        CommandMenu("Appearance") {
            Button("Customize Space Gradient...") {
                browserManager.showGradientEditor()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(browserManager.tabManager.currentSpace == nil)

            Divider()

            Button("Create Boosts") {
                browserManager.showBoostsDialog()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(browserManager.currentTabForActiveWindow() == nil)
        }
    }
}
