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
import Sparkle

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
                    // Connect browser manager to app delegate for cleanup and Sparkle integration
                    appDelegate.browserManager = browserManager
                    browserManager.appDelegate = appDelegate

                    // Initialize keyboard shortcut manager
                    browserManager.settingsManager.keyboardShortcutManager.setBrowserManager(browserManager)
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

class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AppTermination")
    weak var browserManager: BrowserManager?
    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)
    private var mouseEventMonitor: Any?
    private var terminationCleanupPending = false
    private var terminationTimeoutTask: Task<Void, Never>?
    private let quitTerminationTimeoutNanoseconds: UInt64 = 5_000_000_000

    // Sparkle updater controller
    lazy var updaterController: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: urlEventClass,
            andEventID: urlEventID
        )
        
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                    guard let self = self, let manager = self.browserManager else { return event }
                    
                    switch event.buttonNumber {
                    case 2:
                        manager.openCommandPalette()
                    case 3:
                        guard
                            let windowState = manager.activeWindowState,
                            let currentTab = manager.currentTabForActiveWindow(),
                            let webView = manager.getWebView(for: currentTab.id, in: windowState.id)
                        else {
                            return event
                        }

                        webView.goBack()
                    case 4:
                        guard
                            let windowState = manager.activeWindowState,
                            let currentTab = manager.currentTabForActiveWindow(),
                            let webView = manager.getWebView(for: currentTab.id, in: windowState.id)
                        else {
                            return event
                        }
                        webView.goForward()
                    default:
                        break
                    }
                    return event
                }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }
    
    // Prefer async termination path to avoid MainActor deadlocks
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reasonDescriptor = NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: kAEQuitReason)
        let reasonCode = reasonDescriptor?.enumCodeValue ?? FourCharCode(0)
        let askBeforeQuit = browserManager?.settingsManager.askBeforeQuit ?? false
        let tabCount = browserManager?.tabManager.allTabs().count ?? 0

        AppDelegate.log.info("applicationShouldTerminate invoked; reasonCode=\(reasonCode, privacy: .public); askBeforeQuit=\(askBeforeQuit, privacy: .public); tabCount=\(tabCount, privacy: .public)")

        guard let manager = browserManager else {
            AppDelegate.log.info("No browser manager attached; returning terminateNow")
            return .terminateNow
        }

        if manager.hasPreparedForQuit {
            AppDelegate.log.info("Quit preparation already completed; returning terminateNow")
            return .terminateNow
        }

        if terminationCleanupPending {
            AppDelegate.log.info("Termination cleanup already pending; returning terminateLater")
            return .terminateLater
        }

        terminationCleanupPending = true
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil

        let application = sender

        Task.detached { [weak self] in
            guard let self = self else { return }
            await manager.prepareForQuitIfNeeded(includeUICleanup: false)
            await MainActor.run {
                AppDelegate.log.info("Termination cleanup finished; replying true")
                application.reply(toApplicationShouldTerminate: true)
                self.terminationCleanupPending = false
                self.terminationTimeoutTask?.cancel()
                self.terminationTimeoutTask = nil
            }
        }

        terminationTimeoutTask = Task.detached { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: self.quitTerminationTimeoutNanoseconds)
            await MainActor.run {
                guard self.terminationCleanupPending else { return }
                AppDelegate.log.error("Termination cleanup timeout; replying true to avoid hang")
                self.terminationCleanupPending = false
                application.reply(toApplicationShouldTerminate: true)
                self.terminationTimeoutTask?.cancel()
                self.terminationTimeoutTask = nil
            }
        }

        AppDelegate.log.info("applicationShouldTerminate returning .terminateLater (cleanup pending)")
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

// MARK: - Sparkle Delegate

extension AppDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            browserManager?.handleUpdaterFoundValidUpdate(item)
        }
    }

    func updater(_ updater: SPUUpdater, didFinishDownloadingUpdate item: SUAppcastItem) {
        Task { @MainActor in
            browserManager?.handleUpdaterFinishedDownloading(item)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            browserManager?.handleUpdaterDidNotFindUpdate()
        }
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        Task { @MainActor in
            browserManager?.handleUpdaterAbortedUpdate()
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            browserManager?.handleUpdaterAbortedUpdate()
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationInvocation: @escaping () -> Void) {
        Task { @MainActor in
            browserManager?.handleUpdaterWillInstallOnQuit(item)
        }
    }
}

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
            
            Button("Import from Arc") {
                browserManager.importArcData()
            }
            Divider()

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
                newWindow.minSize = NSSize(width: 470, height: 382)
                newWindow.contentMinSize = NSSize(width: 470, height: 382)
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

            Button("Toggle AI Assistant") {
                browserManager.toggleAISidebar()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!browserManager.settingsManager.showAIAssistant)

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
                // window.isMovableByWindowBackground = true // Disabled - use SwiftUI-based window drag system instead
                window.isMovable = true
                window.styleMask.insert(.fullSizeContentView)
                var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                // Without this, we get the error "NSWindowStyleMaskFullScreen cleared on a window outside of a full screen transition."
                if window.styleMask.contains(.fullScreen) {
                    styleMask.insert(.fullScreen)
                }
                window.styleMask = styleMask

                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.minSize = NSSize(width: 470, height: 382)
                window.contentMinSize = NSSize(width: 470, height: 382)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {

    }
}
