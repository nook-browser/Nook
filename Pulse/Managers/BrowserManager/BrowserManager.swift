//
//  BrowserManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI


import SwiftData

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer
    private init() {
        container = try! ModelContainer(
            for: Schema([SpaceEntity.self,TabEntity.self, TabsStateEntity.self])
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
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard

    init() {
        self.modelContext = Persistence.shared.container.mainContext
        self.tabManager = TabManager(browserManager: nil,context: modelContext)
        self.settingsManager = SettingsManager()
        self.tabManager.browserManager = self
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
        isCommandPaletteVisible = true
    }

    func closeCommandPalette() {
        isCommandPaletteVisible = false
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
        // TODO: Implement URL bar focus
        print("Focus URL bar")
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
}
