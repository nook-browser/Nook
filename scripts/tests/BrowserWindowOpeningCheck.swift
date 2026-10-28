// Licensed under GPL-3.0. See LICENSE.
// Run with: python3 scripts/tests/check-browser-windows.py build-prototype
// Links the actual Debug app module and runs in a disposable app bundle and data directory.

import AppKit
import NookSettings
import NookWeb
@testable import Nook

@main
struct BrowserWindowOpeningCheck {
    @MainActor
    static func main() async throws {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("com.nook.window-check.") == true,
                     "Run through check-browser-windows.py to isolate application data")

        let app = NSApplication.shared
        let settings = NookSettingsService()
        let registry = WindowRegistry()
        let manager = BrowserManager(settings: settings, windowRegistry: registry)
        let coordinator = WebViewCoordinator()
        let aiConfig = AIConfigService()
        let ai = AIService(configService: aiConfig)
        let shortcuts = KeyboardShortcutManager()
        let mcp = MCPManager()
        let organizer = TabOrganizerManager()
        var registrations: [UUID: Int] = [:]

        precondition(settings.externalLinksInMiniWindow, "New and upgrading users default to mini windows")
        settings.externalLinksInMiniWindow = false
        precondition(!NookSettingsService().externalLinksInMiniWindow, "The external-link preference must persist")
        settings.externalLinksInMiniWindow = true

        app.setActivationPolicy(.prohibited)
        manager.webViewCoordinator = coordinator
        manager.aiConfigService = aiConfig
        manager.aiService = ai
        manager.keyboardShortcutManager = shortcuts
        manager.mcpManager = mcp
        manager.tabOrganizerManager = organizer
        registry.onWindowRegister = { window in
            registrations[window.id, default: 0] += 1
            manager.setupWindowState(window)
        }
        registry.onWindowClose = { id in
            if let window = registry.windows[id] {
                manager.tabs.detach(window: window)
            }
        }
        registry.onActiveWindowChange = { manager.setActiveWindowState($0) }

        func closeBrowserWindows() {
            for window in registry.allWindows {
                window.window?.close()
                registry.unregister(window.id)
            }
        }

        let first = manager.openBrowserWindow()!

        precondition(registry.activeWindow === first)
        precondition(first.window != nil && first.spaceID != nil, "The returned window must be ready immediately")
        precondition(manager.openBrowserWindow() === first, "Consecutive requests must share one window")
        registry.activeWindowId = nil
        precondition(manager.openBrowserWindow() === first, "Reuse a registered window before its focus notification arrives")
        registry.register(first)
        precondition(registrations[first.id] == 1, "SwiftUI must not run setup a second time")

        let second = manager.createNewWindow()!

        precondition(second !== first && registry.windows.count == 2, "An explicit new-window request must stay distinct")
        precondition(second.window != nil && second.spaceID != nil)
        precondition(first.window?.tabbingMode == .disallowed && second.window?.tabbingMode == .disallowed,
                     "Browser windows must not participate in macOS native window tabs")
        precondition(manager.openBrowserWindow() === second)

        // Allow SwiftUI onAppear and focus notifications to run, then check registration again.
        try await Task.sleep(for: .milliseconds(200))
        precondition(registrations[first.id] == 1 && registrations[second.id] == 1)
        closeBrowserWindows()

        settings.externalLinksInMiniWindow = false

        let a = URL(string: "about:blank#first")!
        let b = URL(string: "about:blank#second")!

        manager.presentExternalURL(a)
        manager.presentExternalURL(b)

        let reused = registry.activeWindow!
        let opened = manager.tabs.tree.items.values.filter { $0.url == a || $0.url == b }

        precondition(registry.windows.count == 1 && opened.count == 2, "A burst of external links must open once each in one window")
        precondition(reused.window != nil && reused.spaceID != nil)
        closeBrowserWindows()

        // Mini-window promotion uses the same path, including when every browser window is closed.
        settings.externalLinksInMiniWindow = true
        manager.presentExternalURL(URL(string: "about:blank#mini")!)
        precondition(registry.windows.isEmpty)

        let mini = app.windows.compactMap { $0 as? MiniBrowserWindow }.first!

        mini.openInSpaceAction!()
        precondition(registry.windows.count == 1)
        precondition(manager.tabs.tree.items.values.contains { $0.url?.fragment == "mini" })
        closeBrowserWindows()

        // Matching external links must still route when no regular window exists, even with mini enabled.
        let target = manager.tabs.orderedSpaces.first!.id
        let routedURL = URL(string: "https://window-check.invalid/routed")!

        settings.siteRoutingRules = [SiteRoutingRule(domain: "window-check.invalid", targetSpaceId: target)]
        manager.presentExternalURL(routedURL)
        try await Task.sleep(for: .milliseconds(200))
        precondition(registry.windows.count == 1)
        precondition(registry.activeWindow?.spaceID == target)
        precondition(manager.tabs.tree.items.values.filter { $0.url == routedURL }.count == 1)
        closeBrowserWindows()

        let olderRegular = manager.createNewWindow()!
        let newerRegular = manager.createNewWindow()!

        registry.setActive(olderRegular)
        manager.createIncognitoWindow()

        let privateWindow = registry.activeWindow!
        let externalURL = URL(string: "about:blank#outside-private")!

        precondition(privateWindow.isIncognito)
        precondition(manager.openBrowserWindow() === olderRegular, "General window opening always selects a regular window")
        registry.setActive(privateWindow)
        settings.externalLinksInMiniWindow = false
        manager.presentExternalURL(externalURL)
        precondition(registry.windows.count == 3)
        precondition(registry.activeWindow === olderRegular, "Use activation order, not window creation order")
        precondition(privateWindow.privateTree?.items.values.contains { $0.url == externalURL } != true)

        try await Task.sleep(for: .milliseconds(200))
        olderRegular.window?.close()
        registry.unregister(olderRegular.id)
        registry.setActive(privateWindow)
        manager.presentExternalURL(URL(string: "about:blank#after-close")!)
        precondition(registry.activeWindow === newerRegular, "Closing the last-used regular window reveals the previous one")
        newerRegular.window?.close()
        registry.unregister(newerRegular.id)
        registry.setActive(privateWindow)
        manager.presentExternalURL(URL(string: "about:blank#only-private")!)
        precondition(registry.windows.count == 2 && registry.activeWindow?.isIncognito == false,
                     "Only-private sessions need one new regular window")
        try await Task.sleep(for: .milliseconds(200))
        closeBrowserWindows()

        // A matching routing rule also leaves the private window untouched.
        manager.createIncognitoWindow()
        settings.externalLinksInMiniWindow = true
        manager.presentExternalURL(routedURL)
        try await Task.sleep(for: .milliseconds(200))
        precondition(registry.windows.count == 2 && registry.activeWindow?.isIncognito == false)
        precondition(registry.activeWindow?.spaceID == target)
        precondition(registrations.values.allSatisfy { $0 == 1 })
        closeBrowserWindows()

        // Promotion follows the popup's source, even after another window takes focus.
        let privateSource = manager.createIncognitoWindow()!
        let privateURL = URL(string: "about:blank#private-popup")!

        manager.externalMiniWindowManager.present(url: privateURL)

        let privateMini = app.windows.compactMap { $0 as? MiniBrowserWindow }.first { $0.isVisible }!
        let regularDestination = manager.createNewWindow()!

        privateMini.openInSpaceAction!()
        precondition(registry.activeWindow === privateSource)
        precondition(privateSource.privateTree?.items.values.contains { $0.url == privateURL } == true)
        precondition(!manager.tabs.tree.items.values.contains { $0.url == privateURL })

        manager.externalMiniWindowManager.present(url: URL(string: "about:blank#closed-private-source")!)

        let orphanMini = app.windows.compactMap { $0 as? MiniBrowserWindow }.first { $0.isVisible }!

        try await Task.sleep(for: .milliseconds(200))
        privateSource.window?.close()
        registry.unregister(privateSource.id)
        registry.setActive(regularDestination)
        orphanMini.openInSpaceAction!()
        precondition(registry.activeWindow?.isIncognito == true)
        precondition(!manager.tabs.tree.items.values.contains { $0.url?.fragment == "closed-private-source" })
        try await Task.sleep(for: .milliseconds(200))
        closeBrowserWindows()

        // Save two distinct windows, then load the same state through a fresh manager.
        let savedFirst = manager.createNewWindow()!
        let savedSecond = manager.createNewWindow()!
        let firstFrame = NSRect(x: 120, y: 130, width: 800, height: 600)
        let secondFrame = NSRect(x: 180, y: 190, width: 900, height: 650)

        try await Task.sleep(for: .milliseconds(200))
        savedFirst.window!.setFrame(firstFrame, display: false)
        savedSecond.window!.setFrame(secondFrame, display: false)
        manager.tabs.flushSync()
        closeBrowserWindows()

        let restoredRegistry = WindowRegistry()
        let restored = BrowserManager(settings: settings, windowRegistry: restoredRegistry)

        restored.webViewCoordinator = coordinator
        restored.aiConfigService = aiConfig
        restored.aiService = ai
        restored.keyboardShortcutManager = shortcuts
        restored.mcpManager = mcp
        restored.tabOrganizerManager = organizer
        restoredRegistry.onWindowRegister = { restored.setupWindowState($0) }
        restoredRegistry.onActiveWindowChange = { restored.setActiveWindowState($0) }

        let restoredFirst = restored.openBrowserWindow()!

        precondition(restoredRegistry.windows.count == 2, "Each saved window must be restored exactly once")
        precondition(restoredRegistry.allWindows.allSatisfy { $0.spaceID != nil && $0.window != nil })
        precondition(restored.openBrowserWindow() === restoredFirst)
        try await Task.sleep(for: .milliseconds(200))

        let restoredFrames = Set(restoredRegistry.allWindows.map { NSStringFromRect($0.window!.frame) })

        precondition(restoredFrames == Set([NSStringFromRect(firstFrame), NSStringFromRect(secondFrame)]))
        restored.tabs.flushSync()

        for window in restoredRegistry.allWindows {
            window.window?.close()
            restoredRegistry.unregister(window.id)
        }

        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        print("Browser window opening checks passed: readiness, reuse, distinct windows, registration, external bursts, mini promotion, routing, private exclusion, regular-window recency, and saved-window restoration")
        exit(0)
    }
}
