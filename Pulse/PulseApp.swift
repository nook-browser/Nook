//
//  PulseApp.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit
import OSLog

@main
struct PulseApp: App {
    @StateObject private var browserManager = BrowserManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BackgroundWindowModifier())
                .ignoresSafeArea(.all)
                .environmentObject(browserManager)
                .onAppear {
                    // Connect browser manager to app delegate for cleanup
                    appDelegate.browserManager = browserManager
                }
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

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pulse", category: "AppTermination")
    weak var browserManager: BrowserManager?
    
    // Prefer async termination path to avoid MainActor deadlocks
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.log.info("applicationShouldTerminate: returning terminateLater and starting async persistence")

        // Minimal fallback if BrowserManager is unavailable
        guard let manager = browserManager else {
            // Attempt a best-effort save via shared persistence container
            do {
                let ctx = Persistence.shared.container.mainContext
                try ctx.save()
                AppDelegate.log.info("Fallback save without BrowserManager succeeded")
            } catch {
                AppDelegate.log.error("Fallback save without BrowserManager failed: \(String(describing: error))")
            }
            return .terminateNow
        }

        Task { @MainActor in
            let overallStart = CFAbsoluteTimeGetCurrent()
            AppDelegate.log.info("Termination task started on MainActor")

            // Phase 1: Atomic snapshot persistence (non-throwing Bool)
            let persistStart = CFAbsoluteTimeGetCurrent()
            let atomic: Bool = await manager.tabManager.persistSnapshotAwaitingResult()
            let pdt = CFAbsoluteTimeGetCurrent() - persistStart
            AppDelegate.log.info("Atomic persistence \(atomic ? "succeeded" : "did not run; fallback used") in \(String(format: "%.3f", pdt))s")

            // Phase 2: Ensure SwiftData changes are committed
            let contextSaveStart = CFAbsoluteTimeGetCurrent()
            do {
                try manager.modelContext.save()
                let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                AppDelegate.log.info("Context save completed in \(String(format: "%.3f", sdt))s")
            } catch {
                let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                AppDelegate.log.error("Context save failed in \(String(format: "%.3f", sdt))s: \(String(describing: error))")
            }

            // Phase 3: Graceful cleanup
            manager.cleanupAllTabs()
            AppDelegate.log.info("Cleanup completed; WKWebView processes terminated")

            let total = CFAbsoluteTimeGetCurrent() - overallStart
            AppDelegate.log.info("Termination task finished in \(String(format: "%.3f", total))s; replying to terminate")
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Keep minimal to avoid MainActor deadlocks; main work happens in applicationShouldTerminate
        AppDelegate.log.info("applicationWillTerminate called")
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
            Button("New URL / Search") {
                browserManager.openCommandPalette()
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
        CommandMenu("Extensions") {
            Button("Install Extension...") {
                browserManager.showExtensionInstallDialog()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Button("Manage Extensions...") {
                // Open settings to extensions tab
                openWindow(id: "settings")
                browserManager.settingsManager.currentSettingsTab = .extensions
            }

            if #available(macOS 15.5, *) {
                Divider()
                Button("Open Popup Console") {
                    browserManager.extensionManager?.showPopupConsole()
                }
            }
        }
        
        // Window Commands
        CommandMenu("Window") {
            Button("Toggle Picture in Picture") {
                browserManager.tabManager.currentTab?.requestPictureInPicture()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(browserManager.tabManager.currentTab == nil || 
                     !(browserManager.tabManager.currentTab?.hasVideoContent == true || 
                       browserManager.tabManager.currentTab?.hasPiPActive == true))
            
            Divider()
            
            Button(browserManager.tabManager.currentTab?.isAudioMuted == true ? "Unmute Audio" : "Mute Audio") {
                browserManager.tabManager.currentTab?.toggleMute()
            }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(browserManager.tabManager.currentTab == nil || 
                     browserManager.tabManager.currentTab?.hasAudioContent != true)
        }

        // Appearance Commands
        CommandMenu("Appearance") {
            Button("Customize Space Gradient...") {
                browserManager.showGradientEditor()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(browserManager.tabManager.currentSpace == nil)
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
