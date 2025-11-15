//
//  NookApp.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // TEMPORARY: BrowserManager will be phased out as a global singleton.
    // Eventually each manager (TabManager, etc.) will be independent and injected via environment.
    @StateObject private var browserManager = BrowserManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BackgroundWindowModifier())
                .ignoresSafeArea(.all)
                .environmentObject(browserManager)
                .environment(windowRegistry)
                .environment(webViewCoordinator)
                .environment(\.nookSettings, settingsManager)
                .onAppear {
                    setupApplicationLifecycle()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            NookCommands(browserManager: browserManager, windowRegistry: windowRegistry)
        }

        // Native macOS Settings window
        Settings {
            SettingsView()
                .environmentObject(browserManager)
                .environmentObject(browserManager.gradientColorManager)
                .environment(\.nookSettings, settingsManager)
        }
    }

    // MARK: - Application Lifecycle Setup

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
        browserManager.appDelegate = appDelegate

        // TEMPORARY: Wire coordinators to BrowserManager
        // TODO: Remove these connections - coordinators should be independent
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.settingsManager = settingsManager

        // Configure managers that depend on settings
        browserManager.compositorManager.setUnloadTimeout(settingsManager.tabUnloadTimeout)
        browserManager.trackingProtectionManager.setEnabled(settingsManager.blockCrossSiteTracking)

        // Initialize keyboard shortcut manager
        settingsManager.keyboardShortcutManager.setBrowserManager(browserManager)

        // Set up window lifecycle callbacks
        windowRegistry.onWindowRegister = { [weak browserManager] windowState in
            browserManager?.setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = { [webViewCoordinator, weak browserManager] windowId in
            webViewCoordinator.cleanupWindow(windowId, tabManager: browserManager!.tabManager)
            browserManager?.splitManager.cleanupWindow(windowId)
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
