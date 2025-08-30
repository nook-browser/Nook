//
//  BrowserManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import SwiftData
import AppKit
import WebKit

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer
    private init() {
        do {
            let schema = Schema([SpaceEntity.self, TabEntity.self, TabsStateEntity.self, HistoryEntity.self, ExtensionEntity.self])
            container = try ModelContainer(for: schema)
        } catch {
            print("SwiftData container creation failed: \(error)")
            print("This might be due to schema changes. Resetting database...")
            
            // Fallback: Delete the database file and create fresh
            do {
                let url = URL.applicationSupportDirectory.appending(path: "default.store")
                if FileManager.default.fileExists(atPath: url.path()) {
                    try FileManager.default.removeItem(at: url)
                    print("Removed old database file")
                }
                
                let schema = Schema([SpaceEntity.self, TabEntity.self, TabsStateEntity.self, HistoryEntity.self, ExtensionEntity.self])
                container = try ModelContainer(for: schema)
                print("Database reset and created successfully")
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }
}


@MainActor
class BrowserManager: ObservableObject {
    @Published var sidebarWidth: CGFloat = 250
    @Published var isSidebarVisible: Bool = true
    @Published var isCommandPaletteVisible: Bool = false
    @Published var didCopyURL: Bool = false
    @Published var commandPalettePrefilledText: String = ""
    @Published var shouldNavigateCurrentTab: Bool = false
    
    var modelContext: ModelContext
    var tabManager: TabManager
    var settingsManager: SettingsManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    var historyManager: HistoryManager
    var cookieManager: CookieManager
    var cacheManager: CacheManager
    var extensionManager: ExtensionManager?
    var compositorManager: TabCompositorManager
    var gradientColorManager: GradientColorManager
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    
    // Compositor container view
    var compositorContainerView: NSView?

    init() {
        // Phase 1: initialize all stored properties
        self.modelContext = Persistence.shared.container.mainContext
        if #available(macOS 15.5, *) {
            self.extensionManager = ExtensionManager.shared
        } else {
            self.extensionManager = nil
        }
        self.tabManager = TabManager(browserManager: nil, context: modelContext)
        self.settingsManager = SettingsManager()
        self.dialogManager = DialogManager()
        self.downloadManager = DownloadManager.shared
        self.historyManager = HistoryManager(context: modelContext)
        self.cookieManager = CookieManager()
        self.cacheManager = CacheManager()
        self.compositorManager = TabCompositorManager()
        self.gradientColorManager = GradientColorManager()
        self.compositorContainerView = nil

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.compositorManager.setUnloadTimeout(self.settingsManager.tabUnloadTimeout)
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
        if #available(macOS 15.5, *), let mgr = self.extensionManager {
            // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
            mgr.attach(browserManager: self)
        }
        if let g = self.tabManager.currentSpace?.gradient {
            self.gradientColorManager.setImmediate(g)
        } else {
            self.gradientColorManager.setImmediate(.default)
        }
        loadSidebarSettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabUnloadTimeoutChange),
            name: .tabUnloadTimeoutChanged,
            object: nil
        )
    }
    
    func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
        savedSidebarWidth = width
    }
    
    func saveSidebarWidthToDefaults() {
        saveSidebarSettings()
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.1)) {
            isSidebarVisible.toggle()

            if isSidebarVisible {
                sidebarWidth = savedSidebarWidth
            } else {
                sidebarWidth = 0
            }
        }
        saveSidebarSettings()
    }

    // MARK: - Command Palette
    func openCommandPalette() {
        if isCommandPaletteVisible { 
                   DispatchQueue.main.async {
            self.isCommandPaletteVisible = false
        } 
         } else {
        // Clear prefilled text and set to create new tab
        commandPalettePrefilledText = ""
        shouldNavigateCurrentTab = false
        DispatchQueue.main.async {
            self.isCommandPaletteVisible = true
        }
         }

    }

    func closeCommandPalette() {
        if !isCommandPaletteVisible { return }
        DispatchQueue.main.async {
            self.isCommandPaletteVisible = false
        }
    }

    func toggleCommandPalette() {
        if isCommandPaletteVisible {
            closeCommandPalette()
        } else {
            openCommandPalette()
        }
    }

    // MARK: - Tab Management (delegates to TabManager)
    func createNewTab() {
        _ = tabManager.createNewTab()
    }

    func closeCurrentTab() {
        tabManager.closeActiveTab()
    }

    func focusURLBar() {
        if isCommandPaletteVisible { return }
        
        // Pre-fill with current tab's URL and set to navigate current tab
        if let currentURL = tabManager.currentTab?.url {
            commandPalettePrefilledText = currentURL.absoluteString
        } else {
            commandPalettePrefilledText = ""
        }
        shouldNavigateCurrentTab = true
        
        DispatchQueue.main.async {
            self.isCommandPaletteVisible = true
        }
    }

    // MARK: - Dialog Methods
    
    func showQuitDialog() {
        dialogManager.showQuitDialog(
            onAlwaysQuit: {
                // Save always quit preference
                self.quitApplication()
            },
            onQuit: {
                self.quitApplication()
            }
        )
    }
    
    func showCustomDialog<Header: View, Body: View, Footer: View>(
        header: Header,
        body: Body,
        footer: Footer
    ) {
        dialogManager.showDialog(header: header, body: body, footer: footer)
    }
    
    func showCustomDialog<Body: View, Footer: View>(
        body: Body,
        footer: Footer
    ) {
        dialogManager.showDialog(body: body, footer: footer)
    }
    
    func showCustomDialog<Body: View>(
        body: Body
    ) {
        dialogManager.showDialog(body: body)
    }
    
    func showCustomContentDialog<Content: View>(
        header: AnyView?,
        content: Content,
        footer: AnyView?
    ) {
        dialogManager.showCustomContentDialog(header: header, content: content, footer: footer)
    }
    
    // MARK: - Appearance / Gradient Editing
    private final class GradientDraft: ObservableObject {
        @Published var value: SpaceGradient
        init(_ value: SpaceGradient) { self.value = value }
    }

    func showGradientEditor() {
        guard let space = tabManager.currentSpace else {
            // Consistent in-app dialog when no space is available
            let header = AnyView(
                DialogHeader(
                    icon: "paintpalette",
                    title: "No Space Available",
                    subtitle: "Create a space to customize its gradient."
                )
            )
            let footer = AnyView(
                DialogFooter(rightButtons: [
                    DialogButton(text: "OK", variant: .primary) { [weak self] in
                        self?.closeDialog()
                    }
                ])
            )
            showCustomContentDialog(header: header, content: Color.clear.frame(height: 0), footer: footer)
            return
        }

        let draft = GradientDraft(space.gradient)
        let binding = Binding<SpaceGradient>(
            get: { draft.value },
            set: { draft.value = $0 }
        )

        // Compact dialog: remove header icon/title to save vertical space
        let header: AnyView? = nil

        let content = GradientEditorView(gradient: binding)
            .environmentObject(self.gradientColorManager)

        let footer = AnyView(
            DialogFooter(
                leftButton: DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: { [weak self] in
                        // Restore background to the saved gradient for this space
                        self?.gradientColorManager.endInteractivePreview()
                        self?.gradientColorManager.transition(to: space.gradient, duration: 0.25)
                        self?.closeDialog()
                    }
                ),
                rightButtons: [
                    DialogButton(
                        text: "Save",
                        iconName: "checkmark",
                        variant: .primary,
                        action: { [weak self] in
                            // Commit draft to the current space and persist
                            space.gradient = draft.value
                            // End interactive editing then morph to the committed gradient
                            self?.gradientColorManager.endInteractivePreview()
                            self?.gradientColorManager.transition(to: draft.value, duration: 0.35)
                            self?.tabManager.persistSnapshot()
                            self?.closeDialog()
                        }
                    )
                ]
            )
        )

        showCustomContentDialog(
            header: header,
            content: content,
            footer: footer
        )
    }

    func closeDialog() {
        dialogManager.closeDialog()
    }
    
    private func quitApplication() {
        // Clean up all tabs before terminating
        cleanupAllTabs()
        NSApplication.shared.terminate(nil)
    }
    
    func cleanupAllTabs() {
        print("🔄 [BrowserManager] Cleaning up all tabs")
        let allTabs = tabManager.pinnedTabs + tabManager.tabs
        
        for tab in allTabs {
            print("🔄 [BrowserManager] Cleaning up tab: \(tab.name)")
            tab.closeTab()
        }
    }

    // MARK: - Private Methods
    private func loadSidebarSettings() {
        let savedWidth = userDefaults.double(forKey: "sidebarWidth")
        let savedVisibility = userDefaults.bool(forKey: "sidebarVisible")

        if savedWidth > 0 {
            savedSidebarWidth = savedWidth
            sidebarWidth = savedVisibility ? savedWidth : 0
        }
        isSidebarVisible = savedVisibility
    }

    private func saveSidebarSettings() {
        userDefaults.set(savedSidebarWidth, forKey: "sidebarWidth")
        userDefaults.set(isSidebarVisible, forKey: "sidebarVisible")
    }
    
    @objc private func handleTabUnloadTimeoutChange(_ notification: Notification) {
        if let timeout = notification.userInfo?["timeout"] as? TimeInterval {
            compositorManager.setUnloadTimeout(timeout)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Cookie Management Methods
    
    func clearCurrentPageCookies() {
        guard let currentTab = tabManager.currentTab,
              let host = currentTab.url.host else { return }
        
        Task {
            await cookieManager.deleteCookiesForDomain(host)
        }
    }
    
    func clearAllCookies() {
        Task {
            await cookieManager.deleteAllCookies()
        }
    }
    
    func clearExpiredCookies() {
        Task {
            await cookieManager.deleteExpiredCookies()
        }
    }
    
    // MARK: - Cache Management
    
    func clearCurrentPageCache() {
        guard let currentTab = tabManager.currentTab,
              let host = currentTab.url.host else { return }
        
        Task {
            await cacheManager.clearCacheForDomain(host)
        }
    }
    
    func clearStaleCache() {
        Task {
            await cacheManager.clearStaleCache()
        }
    }
    
    func clearDiskCache() {
        Task {
            await cacheManager.clearDiskCache()
        }
    }
    
    func clearMemoryCache() {
        Task {
            await cacheManager.clearMemoryCache()
        }
    }
    
    func clearAllCache() {
        Task {
            await cacheManager.clearAllCache()
        }
    }
    
    // MARK: - Privacy-Compliant Management
    
    func clearThirdPartyCookies() {
        Task {
            await cookieManager.deleteThirdPartyCookies()
        }
    }
    
    func clearHighRiskCookies() {
        Task {
            await cookieManager.deleteHighRiskCookies()
        }
    }
    
    func performPrivacyCleanup() {
        Task {
            await cookieManager.performPrivacyCleanup()
            await cacheManager.performPrivacyCompliantCleanup()
        }
    }
    
    func clearPersonalDataCache() {
        Task {
            await cacheManager.clearPersonalDataCache()
        }
    }
    
    func clearFaviconCache() {
        cacheManager.clearFaviconCache()
    }
    
    // MARK: - Extension Management
    
    func showExtensionInstallDialog() {
        if #available(macOS 15.5, *) {
            extensionManager?.showExtensionInstallDialog()
        } else {
            // Show unsupported OS alert
            let alert = NSAlert()
            alert.messageText = "Extensions Not Supported"
            alert.informativeText = "Extensions require macOS 15.5 or later."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func enableExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.enableExtension(extensionId)
        }
    }
    
    func disableExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.disableExtension(extensionId)
        }
    }
    
    func uninstallExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.uninstallExtension(extensionId)
        }
    }

    // MARK: - URL Utilities
    func copyCurrentURL() {
        if let url = tabManager.currentTab?.url.absoluteString {
            print("Attempting to copy URL: \(url)")
            
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(url, forType: .string)
                let e = NSHapticFeedbackManager.defaultPerformer
                e.perform(.generic, performanceTime: .drawCompleted)
                print("Clipboard operation success: \(success)")
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.didCopyURL = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    self.didCopyURL = false
                }
            }
        } else {
            print("No URL found to copy")
        }
    }
    
    // MARK: - Web Inspector
    func openWebInspector() {
        guard let currentTab = tabManager.currentTab else { 
            print("No current tab to inspect")
            return 
        }
        
        if #available(macOS 13.3, *) {
            let webView = currentTab.activeWebView
            if webView.isInspectable {
                DispatchQueue.main.async {
                    // Focus the webview and trigger context menu programmatically
                    self.presentInspectorContextMenu(for: webView)
                }
            } else {
                print("Web inspector not available for this tab")
            }
        } else {
            print("Web inspector requires macOS 13.3 or later")
        }
    }
    
    private func presentInspectorContextMenu(for webView: WKWebView) {
        // Focus the webview first
        webView.window?.makeFirstResponder(webView)
        
        // Create a right-click event at the center of the webview
        let bounds = webView.bounds
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        
        let rightClickEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: center,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: webView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
        
        if let event = rightClickEvent {
            webView.rightMouseDown(with: event)
        }
    }
}
