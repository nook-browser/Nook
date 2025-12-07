//
//  DragEnabledSpacesSideBarView.swift
//  Nook
//
//  Main sidebar with advanced drag & drop functionality
//

import SwiftUI

struct DragEnabledSpacesSideBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(CommandPalette.self) private var commandPalette
    private var dragManager = TabDragManager.shared
    
    var body: some View {
        SpacesSideBarView()
            .environmentObject(browserManager)
            .environment(commandPalette)
            .environmentObject(browserManager.gradientColorManager)
            .environmentObject(dragManager)
            .tabDragManager(dragManager)
    }
}

// MARK: - Environment Key for DragManager

struct TabDragManagerKey: EnvironmentKey {
    static let defaultValue: TabDragManager? = nil
}

extension EnvironmentValues {
    var tabDragManager: TabDragManager? {
        get { self[TabDragManagerKey.self] }
        set { self[TabDragManagerKey.self] = newValue }
    }
}

extension View {
    func tabDragManager(_ dragManager: TabDragManager) -> some View {
        environment(\.tabDragManager, dragManager)
    }
}
