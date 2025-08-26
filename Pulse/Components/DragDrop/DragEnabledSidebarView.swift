//
//  DragEnabledSidebarView.swift
//  Pulse
//
//  Main sidebar with advanced drag & drop functionality
//

import SwiftUI

struct DragEnabledSidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @StateObject private var dragManager = TabDragManager()
    
    var body: some View {
        TabDragContainerView(
            dragManager: dragManager,
            onDragCompleted: handleDragCompleted
        ) {
            SidebarView()
                .environmentObject(dragManager)
        }
        .insertionLineOverlay(dragManager: dragManager)
    }
    
    private func handleDragCompleted(_ operation: DragOperation) {
        print("🎯 Handling drag completion: \(operation)")
        browserManager.tabManager.handleDragOperation(operation)
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