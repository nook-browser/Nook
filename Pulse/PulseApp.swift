//
//  PulseApp.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit

@main
struct PulseApp: App {
    @StateObject private var browserManager = BrowserManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BackgroundWindowModifier())
                .ignoresSafeArea(.all)
                .environmentObject(browserManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PulseCommands(browserManager: browserManager)
        }

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environmentObject(browserManager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

struct PulseCommands: Commands {
    let browserManager: BrowserManager
    @Environment(\.openWindow) private var openWindow

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .windowList) {}
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserManager.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("Focus URL Bar") {
                browserManager.focusURLBar()
            }
            .keyboardShortcut("l", modifiers: .command)
            
            Divider()
            
            Button("Web Inspector") {
                browserManager.openWebInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(browserManager.tabManager.currentTab == nil)
            
            Divider()
            
            Button("Force Quit App") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        // File Section
        CommandMenu("File") {
            
            Button("New Tab") {
                browserManager.openCommandPalette()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("New Window") {
                browserManager.openCommandPalette()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Close Tab") {
                browserManager.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(browserManager.tabManager.tabs.isEmpty)
            
            Button("Copy Current URL") {
                browserManager.copyCurrentURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(browserManager.tabManager.currentTab != nil ? false : true)

        }
        
        // Privacy/Cookie Commands
        CommandMenu("Privacy") {
            Menu("Clear Cookies") {
                Button("Clear Cookies for Current Site") {
                    browserManager.clearCurrentPageCookies()
                }
                .disabled(browserManager.tabManager.currentTab?.url.host == nil)
                
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
                .disabled(browserManager.tabManager.currentTab?.url.host == nil)
                
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
        CommandMenu("Extensions") {
            Button("Install Extension...") {
                browserManager.showExtensionInstallDialog()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Button("Manage Extensions...") {
                // Open settings to extensions tab
                openWindow(id: "settings")
            }

            if #available(macOS 15.5, *) {
                Divider()
                Button("Open Popup Console") {
                    browserManager.extensionManager?.showPopupConsole()
                }
            }
        }
    }
}

struct BackgroundWindowModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.toolbar?.isVisible = false
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.isReleasedWhenClosed = false
                window.isMovableByWindowBackground = false
                window.isMovable = false
                window.styleMask = [
                    .titled, .closable, .miniaturizable, .resizable,
                    .fullSizeContentView,
                ]

                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {

    }
}
