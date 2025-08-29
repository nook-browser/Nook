//
//  DragEnabledSidebarView.swift
//  Pulse
//
//  Main sidebar with advanced drag & drop functionality
//

import SwiftUI

struct DragEnabledSidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    private var dragManager = TabDragManager.shared
    
    var body: some View {
        SidebarView()
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
