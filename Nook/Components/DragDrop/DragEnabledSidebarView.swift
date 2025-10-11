//
//  DragEnabledSidebarView.swift
//  Nook
//
//  Main sidebar with advanced drag & drop functionality
//

import SwiftUI

struct DragEnabledSidebarView: View {
    @Environment(BrowserManager.self) private var browserManager
    private var dragManager = TabDragManager.shared
    
    var body: some View {
        SidebarView()
            .environment(browserManager)
            .environment(dragManager)
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
