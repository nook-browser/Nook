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
        container = try! ModelContainer(
            for: Schema([SpaceEntity.self, TabEntity.self, TabsStateEntity.self, HistoryEntity.self, ExtensionEntity.self])
        )
    }
}


@MainActor
class BrowserManager: ObservableObject {
    @Published var sidebarWidth: CGFloat = 250
    @Published var isSidebarVisible: Bool = true
    @Published var isCommandPaletteVisible: Bool = false
    
    var modelContext: ModelContext
    var tabManager: TabManager
    var settingsManager: SettingsManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    var historyManager: HistoryManager
    var cookieManager: CookieManager
    var cacheManager: CacheManager
    var extensionManager: ExtensionManager?
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard

    init() {
        self.modelContext = Persistence.shared.container.mainContext
        // Prepare native ExtensionManager reference early; defer attach until after init completes.
        if #available(macOS 15.5, *) {
            let mgr = ExtensionManager.shared
            self.extensionManager = mgr
        }

        self.tabManager = TabManager(browserManager: nil,context: modelContext)
        self.settingsManager = SettingsManager()
        self.dialogManager = DialogManager()
        self.downloadManager = DownloadManager.shared
        self.historyManager = HistoryManager(context: modelContext)
        self.cookieManager = CookieManager()
        self.cacheManager = CacheManager()
        self.tabManager.browserManager = self
        // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
        if #available(macOS 15.5, *), let mgr = self.extensionManager {
            mgr.attach(browserManager: self)
        }

        self.tabManager.reattachBrowserManager(self)
        loadSidebarSettings()
        
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
    
    func closeDialog() {
        dialogManager.closeDialog()
    }
    
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
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
}
