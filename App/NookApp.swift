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
import WebKit

@main
struct NookApp: App {
    @State private var windowRegistry = WindowRegistry()
    @State private var webViewCoordinator = WebViewCoordinator()
    @State private var settingsManager = NookSettingsService()
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var aiConfigService: AIConfigService
    @State private var mcpManager = MCPManager()
    @State private var aiService: AIService
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
            ContentView()
                .background(BackgroundWindowModifier())
                .ignoresSafeArea(.all)
                .environmentObject(browserManager)
                .environment(windowRegistry)
                .environment(webViewCoordinator)
                .environment(\.nookSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .environment(aiConfigService)
                .environment(mcpManager)
                .environment(aiService)
                .onAppear {
                    setupApplicationLifecycle()
                    setupAIServices()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            NookCommands(
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                shortcutManager: keyboardShortcutManager
            )
        }

        // Native macOS Settings window
        Settings {
            SettingsView()
                .environmentObject(browserManager)
                .environmentObject(browserManager.gradientColorManager)
                .environment(\.nookSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .environment(aiConfigService)
                .environment(mcpManager)
        }
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
        browserManager.appDelegate = appDelegate

        // TEMPORARY: Wire coordinators to BrowserManager
        // TODO: Remove these connections - coordinators should be independent
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.nookSettings = settingsManager
        browserManager.tabManager.nookSettings = settingsManager
        browserManager.aiService = aiService
        browserManager.aiConfigService = aiConfigService

        // Configure managers that depend on settings
        browserManager.compositorManager.setUnloadTimeout(settingsManager.tabUnloadTimeout)
        browserManager.trackingProtectionManager.setEnabled(settingsManager.blockCrossSiteTracking)

        // Initialize keyboard shortcut manager
        keyboardShortcutManager.setBrowserManager(browserManager)
        browserManager.keyboardShortcutManager = keyboardShortcutManager

        // Set up window lifecycle callbacks
        windowRegistry.onWindowRegister = { [weak browserManager] windowState in
            browserManager?.setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = { [webViewCoordinator, weak browserManager] windowId in
            // Only cleanup if browserManager still exists (it's captured weakly)
            if let browserManager = browserManager {
                webViewCoordinator.cleanupWindow(windowId, tabManager: browserManager.tabManager)
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
                print("⚠️ [NookApp] Window \(windowId) closed after BrowserManager deallocation - performed minimal cleanup")
            }
        }

        windowRegistry.onActiveWindowChange = { [weak browserManager] windowState in
            browserManager?.setActiveWindowState(windowState)
        }
    }
}

// MARK: - Window Configuration

/// Configures the window appearance and behavior for Nook browser windows
///
/// This modifier:
/// - Hides the standard macOS title bar and window buttons
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
                window.styleMask = [
                    .titled, .closable, .miniaturizable, .resizable,
                    .fullSizeContentView,
                ]

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
