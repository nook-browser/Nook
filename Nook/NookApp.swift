//
//  NookApp.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit
import OSLog
import AppKit
import Carbon

@main
struct NookApp: App {
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
            NookCommands(browserManager: browserManager)
        }

        // Native macOS Settings window
        Settings {
            SettingsView()
                .environmentObject(browserManager)
                .environmentObject(browserManager.gradientColorManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AppTermination")
    weak var browserManager: BrowserManager?
    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: urlEventClass,
            andEventID: urlEventID
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }
    
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

    // MARK: - External URL Handling
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let stringValue = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: stringValue) else {
            return
        }
        handleIncoming(url: url)
    }

    private func handleIncoming(url: URL) {
        guard let manager = browserManager else {
            return
        }
        Task { @MainActor in
            manager.presentExternalURL(url)
        }
    }
}

struct NookCommands: Commands {
    let browserManager: BrowserManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .windowList) {}
        // Use the native Settings menu (no replacement of .appSettings)
        
        // File Section
        CommandGroup(after: .newItem) {
            
            Button("New Tab") {
                browserManager.openCommandPalette()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("New Window") {
                // Create a new window using SwiftUI's WindowGroup
                let newWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                newWindow.contentView = NSHostingView(rootView: ContentView()
                    .background(BackgroundWindowModifier())
                    .ignoresSafeArea(.all)
                    .environmentObject(browserManager))
                newWindow.title = "Nook"
                newWindow.center()
                newWindow.makeKeyAndOrderFront(nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Close Tab") {
                if browserManager.activeWindowState?.isCommandPaletteVisible == true {
                    browserManager.closeCommandPalette(for: browserManager.activeWindowState)
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
            Button("Toggle Picture in Picture") {
                browserManager.requestPiPForCurrentTabInActiveWindow()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(browserManager.currentTabForActiveWindow() == nil ||
                     !(browserManager.currentTabHasVideoContent() ||
                       browserManager.currentTabHasPiPActive()))
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("New URL / Search") {
                browserManager.openCommandPaletteWithCurrentURL()
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
            .disabled(browserManager.currentTabForActiveWindow() == nil ||
                     !browserManager.currentTabHasAudioContent())
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
                window.isMovableByWindowBackground = true
                window.isMovable = true
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
