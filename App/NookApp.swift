//
//  NookApp.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import AppKit
import Carbon
import OSLog
import Sparkle
import SwiftUI

@main
struct NookApp: App {
    @State private var windowRegistry = WindowRegistry()
    @State private var webViewCoordinator = WebViewCoordinator()
    @State private var settingsManager = NookSettingsService()
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var aiConfigService: AIConfigService
    @State private var mcpManager = MCPManager()
    @State private var aiService: AIService
    @State private var tabOrganizerManager = TabOrganizerManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // TEMPORARY: BrowserManager will be phased out as a global singleton.
    // Eventually each manager (TabManager, etc.) will be independent and injected via environment.
    @StateObject private var browserManager = BrowserManager()

    init() {
        let config = AIConfigService()
        _aiConfigService = State(initialValue: config)
        _aiService = State(initialValue: AIService(configService: config))
    }

    var body: some Scene {
        WindowGroup {
            TransitionView(showB: $settingsManager.didFinishOnboarding) {
                OnboardingView()
                    .ignoresSafeArea(.all)
                    .background(BackgroundWindowModifier())
                    .environment(\.nookSettings, settingsManager)
                    .environmentObject(browserManager)
            } viewB: {
                ContentView()
                    .ignoresSafeArea(.all)
                    .background(BackgroundWindowModifier())
                    .environmentObject(browserManager)
                    .environmentObject(browserManager.tabManager)
                    .environment(windowRegistry)
                    .environment(webViewCoordinator)
                    .environment(\.nookSettings, settingsManager)
                    .environment(keyboardShortcutManager)
                    .environment(aiConfigService)
                    .environment(mcpManager)
                    .environment(aiService)
                    .environment(tabOrganizerManager)
                    .onAppear {
                        setupApplicationLifecycle()
                        setupAIServices()
                    }
                
                
            }

        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            NookCommands(
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                shortcutManager: keyboardShortcutManager,
                tabOrganizerManager: tabOrganizerManager
            )
        }


        // macOS 26 style sidebar settings window
        Window("Nook Settings", id: "nook-settings") {
            SettingsWindow()
                .environmentObject(browserManager)
                .environmentObject(browserManager.tabManager)
                .environmentObject(browserManager.gradientColorManager)
                .environment(\.nookSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .environment(aiConfigService)
                .environment(mcpManager)
                .environment(tabOrganizerManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // MARK: - Application Lifecycle Setup

    /// Wires AI services to runtime dependencies (BrowserManager, MCP, etc.)
    private func setupAIServices() {
        aiService.browserManager = browserManager
        aiService.mcpManager = mcpManager

        let toolExecutor = BrowserToolExecutor(browserManager: browserManager)
        aiService.browserToolExecutor = toolExecutor

        // Start enabled MCP servers
        mcpManager.startEnabledServers(configs: aiConfigService.mcpServers)
    }

    /// Configures application-level dependencies and callbacks when the first window appears.
    ///
    /// This function sets up the following connections:
    /// - AppDelegate ↔ BrowserManager: For app termination cleanup and Sparkle update integration
    /// - WindowRegistry callbacks: Register, close, and activate window state
    /// - Keyboard shortcut manager: Enable global keyboard shortcuts
    ///
    /// TEMPORARY CONNECTIONS (to be removed during refactoring):
    /// - BrowserManager ← WebViewCoordinator: Currently BrowserManager holds a reference to coordinate web views
    /// - BrowserManager ← WindowRegistry: Currently BrowserManager tracks active window state
    ///
    /// These temporary connections exist because BrowserManager is currently a god object.
    /// Future refactoring will eliminate these by:
    /// 1. Moving WebViewCoordinator ownership to per-window state
    /// 2. Moving window management out of BrowserManager entirely
    /// 3. Using pure environment-based dependency injection
    private func setupApplicationLifecycle() {
        // Connect AppDelegate for termination and updates
        appDelegate.browserManager = browserManager
        appDelegate.windowRegistry = windowRegistry
        appDelegate.mcpManager = mcpManager
        appDelegate.drainPendingURLs()
        browserManager.appDelegate = appDelegate

        // TEMPORARY: Wire coordinators to BrowserManager
        // TODO: Remove these connections - coordinators should be independent
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.nookSettings = settingsManager
        browserManager.tabManager.nookSettings = settingsManager
        browserManager.siteRoutingManager.settingsService = settingsManager
        browserManager.siteRoutingManager.browserManager = browserManager
        browserManager.aiService = aiService
        browserManager.aiConfigService = aiConfigService

        // Configure managers that depend on settings
        browserManager.compositorManager.setMode(
            settingsManager.tabManagementMode
        )
        browserManager.contentBlockerManager.setEnabled(
            settingsManager.blockCrossSiteTracking || settingsManager.adBlockerEnabled
        )

        // Apply appearance mode
        applyAppearanceMode(settingsManager.appearanceMode)
        NotificationCenter.default.addObserver(
            forName: .appearanceModeChanged,
            object: nil,
            queue: .main
        ) { [weak settingsManager] _ in
            guard let settings = settingsManager else { return }
            applyAppearanceMode(settings.appearanceMode)
        }

        // Initialize keyboard shortcut manager
        keyboardShortcutManager.setBrowserManager(browserManager)
        browserManager.keyboardShortcutManager = keyboardShortcutManager
        browserManager.mcpManager = mcpManager
        browserManager.tabOrganizerManager = tabOrganizerManager

        // Set up window lifecycle callbacks
        windowRegistry.onWindowRegister = { [weak browserManager] windowState in
            browserManager?.setupWindowState(windowState)
        }
        // Retroactively set up any windows that registered before this callback was set
        // (child .onAppear fires before parent .onAppear in SwiftUI)
        for (_, windowState) in windowRegistry.windows {
            browserManager.setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = {
            [webViewCoordinator, weak browserManager] windowId in
            // Only cleanup if browserManager still exists (it's captured weakly)
            if let browserManager = browserManager {
                webViewCoordinator.cleanupWindow(
                    windowId,
                    tabManager: browserManager.tabManager
                )
                browserManager.splitManager.cleanupWindow(windowId)

                // Clean up incognito window if applicable
                if let windowState = browserManager.windowRegistry?.windows[windowId],
                   windowState.isIncognito {
                    Task {
                        await browserManager.closeIncognitoWindow(windowState)
                    }
                }
            } else {
                // BrowserManager was deallocated - perform minimal cleanup
                // Remove compositor container view to prevent leaks
                webViewCoordinator.removeCompositorContainerView(for: windowId)
            }
        }

        windowRegistry.onActiveWindowChange = {
            [weak browserManager] windowState in
            browserManager?.setActiveWindowState(windowState)
        }
    }
}

// MARK: - Appearance Mode

private func applyAppearanceMode(_ mode: AppearanceMode) {
    switch mode {
    case .system:
        NSApp.appearance = nil  // Follow system
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

// MARK: - Window Configuration

/// Configures the window appearance and behavior for Nook browser windows
///
/// This modifier:
/// - Hides the title bar text while keeping native traffic light buttons visible
/// - Sets transparent background for custom window styling
/// - Configures minimum window size
/// - Enables full-size content view for edge-to-edge content
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
                var mask: NSWindow.StyleMask = [
                    .titled, .closable, .miniaturizable, .resizable,
                    .fullSizeContentView,
                ]
                // Preserve fullScreen flag — removing it outside a transition crashes on macOS 15.5+
                if window.styleMask.contains(.fullScreen) {
                    mask.insert(.fullScreen)
                }
                window.styleMask = mask

                window.minSize = NSSize(width: 470, height: 382)
                window.contentMinSize = NSSize(width: 470, height: 382)

                // Persist and restore window frame (position + size) across launches.
                // setFrameAutosaveName makes macOS automatically save the frame to
                // UserDefaults whenever it changes, so the window size is remembered
                // on close — not just on quit.
                window.setFrameAutosaveName("NookBrowserWindow")
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        // Only re-apply if somehow reset (e.g., view transition flash)
        guard !window.titlebarAppearsTransparent else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

