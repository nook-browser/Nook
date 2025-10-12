//
//  DragDropPreview.swift
//  Nook
//
//  Live preview for testing the advanced drag & drop system
//

import SwiftUI
import AppKit
import Observation

// MARK: - Mock Models

@Observable
class MockTab: Identifiable {
    let id = UUID()
    var name: String
    var favicon: String
    var index: Int
    var spaceId: UUID?
    var url: URL = URL(string: "https://example.com")!
    
    init(name: String, favicon: String, index: Int = 0, spaceId: UUID? = nil) {
        self.name = name
        self.favicon = favicon
        self.index = index
        self.spaceId = spaceId
    }
}

struct MockSpace: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    
    init(name: String, icon: String = "square.grid.2x2") {
        self.name = name
        self.icon = icon
    }
}

// MARK: - Mock Tab Manager

@MainActor
@Observable
class MockTabManager {
    var globalPinnedTabs: [MockTab] = []
    var spacePinnedTabs: [UUID: [MockTab]] = [:]
    var regularTabs: [UUID: [MockTab]] = [:]
    var spaces: [MockSpace] = []
    var currentSpaceId: UUID?
    
    var currentSpace: MockSpace? {
        spaces.first { $0.id == currentSpaceId }
    }
    
    init() {
        setupMockData()
    }
    
    private func setupMockData() {
        // Create spaces
        let devSpace = MockSpace(name: "Development", icon: "hammer")
        let personalSpace = MockSpace(name: "Personal", icon: "person")
        spaces = [devSpace, personalSpace]
        currentSpaceId = devSpace.id
        
        // Global pinned tabs
        globalPinnedTabs = [
            MockTab(name: "GitHub", favicon: "externaldrive.connected.to.line.below", index: 0),
            MockTab(name: "Gmail", favicon: "envelope", index: 1),
            MockTab(name: "Calendar", favicon: "calendar", index: 2)
        ]
        
        // Space pinned tabs
        spacePinnedTabs[devSpace.id] = [
            MockTab(name: "Stack Overflow", favicon: "questionmark.circle", index: 0, spaceId: devSpace.id),
            MockTab(name: "Documentation", favicon: "book", index: 1, spaceId: devSpace.id)
        ]
        
        spacePinnedTabs[personalSpace.id] = [
            MockTab(name: "Reddit", favicon: "bubble.left.and.bubble.right", index: 0, spaceId: personalSpace.id)
        ]
        
        // Regular tabs
        regularTabs[devSpace.id] = [
            MockTab(name: "Claude", favicon: "brain", index: 0, spaceId: devSpace.id),
            MockTab(name: "OpenAI", favicon: "lightbulb", index: 1, spaceId: devSpace.id),
            MockTab(name: "Anthropic", favicon: "sparkles", index: 2, spaceId: devSpace.id)
        ]
        
        regularTabs[personalSpace.id] = [
            MockTab(name: "YouTube", favicon: "play.rectangle", index: 0, spaceId: personalSpace.id),
            MockTab(name: "Netflix", favicon: "tv", index: 1, spaceId: personalSpace.id)
        ]
    }
    
    func handleDragOperation(_ operation: DragOperation) {
#if DEBUG
        print("🎯 Mock drag operation: \(operation.fromContainer) → \(operation.toContainer) at \(operation.toIndex)")
#endif
        
        guard let mockTab = mockTab(for: operation.tab.id) else {
#if DEBUG
            print("❌ Mock tab not found for drag operation: \(operation.tab.id)")
#endif
            return
        }
        
        // Mock implementation - just reorder within same container for now
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            reorderGlobalPinned(mockTab, to: operation.toIndex)
            
        case (.spacePinned(let spaceId), .spacePinned(let toSpaceId)) where spaceId == toSpaceId:
            reorderSpacePinned(mockTab, in: spaceId, to: operation.toIndex)
            
        case (.spaceRegular(let spaceId), .spaceRegular(let toSpaceId)) where spaceId == toSpaceId:
            reorderRegular(mockTab, in: spaceId, to: operation.toIndex)
            
        default:
#if DEBUG
            print("Cross-container moves not implemented in preview")
#endif
        }
    }
    
    private func reorderGlobalPinned(_ tab: MockTab, to index: Int) {
        guard let currentIndex = globalPinnedTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        globalPinnedTabs.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), globalPinnedTabs.count)
        globalPinnedTabs.insert(tab, at: clampedIndex)
        updateIndices(&globalPinnedTabs)
    }
    
    private func reorderSpacePinned(_ tab: MockTab, in spaceId: UUID, to index: Int) {
        guard var tabs = spacePinnedTabs[spaceId],
              let currentIndex = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: clampedIndex)
        updateIndices(&tabs)
        spacePinnedTabs[spaceId] = tabs
    }
    
    private func reorderRegular(_ tab: MockTab, in spaceId: UUID, to index: Int) {
        guard var tabs = regularTabs[spaceId],
              let currentIndex = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: clampedIndex)
        updateIndices(&tabs)
        regularTabs[spaceId] = tabs
    }
    
    private func mockTab(for id: UUID) -> MockTab? {
        if let tab = globalPinnedTabs.first(where: { $0.id == id }) {
            return tab
        }
        for (_, tabs) in spacePinnedTabs {
            if let tab = tabs.first(where: { $0.id == id }) {
                return tab
            }
        }
        for (_, tabs) in regularTabs {
            if let tab = tabs.first(where: { $0.id == id }) {
                return tab
            }
        }
        return nil
    }
    
    private func updateIndices(_ tabs: inout [MockTab]) {
        for (index, tab) in tabs.enumerated() {
            tab.index = index
        }
    }
}

// MARK: - Mock Tab View

struct MockTabView: View {
    @Bindable private var tab: MockTab
    private let action: () -> Void
    @State private var isHovering: Bool = false

    init(tab: MockTab, action: @escaping () -> Void = {}) {
        self._tab = Bindable(tab)
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.favicon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.secondary)
                
                Text(tab.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                if isHovering {
                    Button(action: { 
#if DEBUG
print("Close \(tab.name)")
#endif
 }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(3)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Move Up") { 
#if DEBUG
print("Move \(tab.name) up")
#endif
 }
            Button("Move Down") { 
#if DEBUG
print("Move \(tab.name) down")
#endif
 }
            Divider()
            Button("Pin to Space") { 
#if DEBUG
print("Pin \(tab.name) to space")
#endif
 }
            Button("Pin Globally") { 
#if DEBUG
print("Pin \(tab.name) globally")
#endif
 }
        }
    }
}

// MARK: - Mock Pinned Tab View

struct MockPinnedTabView: View {
    @Bindable private var tab: MockTab
    private let action: () -> Void
    @State private var isHovering: Bool = false

    init(tab: MockTab, action: @escaping () -> Void = {}) {
        self._tab = Bindable(tab)
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: tab.favicon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Unpin") { 
#if DEBUG
print("Unpin \(tab.name)")
#endif
 }
        }
    }
}

// MARK: - Drop Zone View
struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let onDrop: () -> Bool
    
    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            .frame(height: 3)
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

// MARK: - Main Preview View

struct DragDropPreview: View {
    @State private var dragManager = TabDragManager()
    @State private var tabManager = MockTabManager()
    
    var body: some View {
        TabDragContainerView(
            dragManager: dragManager,
            onDragCompleted: handleDragCompleted
        ) {
            VStack(spacing: 16) {
                Text("🧛 Dragula Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(spacing: 12) {
                    // Global Pinned Tabs (Essentials)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Essential Tabs (Global)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(tabManager.globalPinnedTabs.indices, id: \.self) { index in
                                let tab = tabManager.globalPinnedTabs[index]
                                MockPinnedTabView(tab: tab, action: {
#if DEBUG
                                    print("Activated: \(tab.name)")
#endif
                                })
                                .onDrag {
                                    dragManager.startDrag(tab: convertToRealTab(tab), from: .essentials, at: index)
                                    return NSItemProvider(object: tab.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers, location in
                                    handleDrop(providers: providers, toContainer: .essentials, atIndex: index)
                                }
                            }
                            
                            // Drop zone at the end of essentials
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                                .onDrop(of: [.text], isTargeted: nil) { providers, location in
                                    handleDrop(providers: providers, toContainer: .essentials, atIndex: tabManager.globalPinnedTabs.count)
                                }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    Divider()
                    
                    // Current Space
                    if let currentSpace = tabManager.currentSpace {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Space: \(currentSpace.name)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            // Space Pinned Tabs
                            if let spacePinned = tabManager.spacePinnedTabs[currentSpace.id], !spacePinned.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pinned in Space")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(spacePinned.indices, id: \.self) { index in
                                        let tab = spacePinned[index]
                                        VStack(spacing: 0) {
                                            // Drop zone above each item
                                            if index == 0 {
                                                DropZoneView(isTargeted: .constant(false)) {
                                                    false
                                                }
                                                .onDrop(of: [.text], isTargeted: Binding(
                                                    get: { dragManager.isDragging },
                                                    set: { _ in }
                                                )) { providers, location in
                                                    handleDrop(providers: providers, toContainer: .spacePinned(currentSpace.id), atIndex: index)
                                                }
                                            }
                                            
                                            MockTabView(tab: tab, action: {
#if DEBUG
                                                print("Activated: \(tab.name)")
#endif
                                            })
                                            .environment(tab)
                                            .onDrag {
                                                dragManager.startDrag(tab: convertToRealTab(tab), from: .spacePinned(currentSpace.id), at: index)
                                                return NSItemProvider(object: tab.id.uuidString as NSString)
                                            }
                                            
                                            // Drop zone below each item  
                                            DropZoneView(isTargeted: .constant(false)) {
                                                false
                                            }
                                            .onDrop(of: [.text], isTargeted: Binding(
                                                get: { dragManager.isDragging },
                                                set: { _ in }
                                            )) { providers, location in
                                                handleDrop(providers: providers, toContainer: .spacePinned(currentSpace.id), atIndex: index + 1)
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                            }
                            
                            // Regular Tabs
                            if let regularTabs = tabManager.regularTabs[currentSpace.id], !regularTabs.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Regular Tabs")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(regularTabs.indices, id: \.self) { index in
                                        let tab = regularTabs[index]
                                        VStack(spacing: 0) {
                                            // Drop zone above each item
                                            if index == 0 {
                                                Rectangle()
                                                    .fill(dragManager.showInsertionLine && dragManager.insertionIndex == index && dragManager.dropTarget == .spaceRegular(currentSpace.id) ? Color.accentColor : Color.clear)
                                                    .frame(height: 3)
                                                    .onDrop(of: [.text], isTargeted: nil) { providers, location in
                                                        handleDrop(providers: providers, toContainer: .spaceRegular(currentSpace.id), atIndex: index)
                                                    }
                                            }
                                            
                                            MockTabView(tab: tab, action: {
#if DEBUG
                                                print("Activated: \(tab.name)")
#endif
                                            })
                                            .environment(tab)
                                            .onDrag {
                                                dragManager.startDrag(tab: convertToRealTab(tab), from: .spaceRegular(currentSpace.id), at: index)
                                                return NSItemProvider(object: tab.id.uuidString as NSString)
                                            }
                                            
                                            // Drop zone below each item
                                            Rectangle()
                                                .fill(dragManager.showInsertionLine && dragManager.insertionIndex == index + 1 && dragManager.dropTarget == .spaceRegular(currentSpace.id) ? Color.accentColor : Color.clear)
                                                .frame(height: 3)
                                                .onDrop(of: [.text], isTargeted: nil) { providers, location in
                                                    handleDrop(providers: providers, toContainer: .spaceRegular(currentSpace.id), atIndex: index + 1)
                                                }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                
                Spacer()
                
                // Debug Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info:")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text(#"Is Dragging: \#(dragManager.isDragging.description)"#)
                    Text(#"Dragged Tab: \#(dragManager.draggedTab?.name ?? "None")"#)
                    Text(#"Insertion Index: \#(dragManager.insertionIndex.description)"#)
                    Text(#"Show Line: \#(dragManager.showInsertionLine.description)"#)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .insertionLineOverlay(dragManager: dragManager)
        .frame(width: 300, height: 600)
    }
    
    private func handleDragCompleted(_ operation: DragOperation) {
#if DEBUG
        print("🎯 Drag completed: \(operation)")
#endif
        tabManager.handleDragOperation(operation)
    }
    
    private func convertToRealTab(_ mockTab: MockTab) -> Tab {
        // Create a minimal Tab instance for drag purposes
        return Tab(
            id: mockTab.id,
            url: mockTab.url, 
            name: mockTab.name, 
            favicon: mockTab.favicon,
            spaceId: mockTab.spaceId,
            index: mockTab.index
        )
    }
    
    private func handleDrop(providers: [NSItemProvider], toContainer: TabDragManager.DragContainer, atIndex: Int) -> Bool {
#if DEBUG
        print("🎯 Drop attempted: container=\(toContainer), index=\(atIndex)")
#endif
        
        guard let draggedTab = dragManager.draggedTab else {
#if DEBUG
            print("❌ No dragged tab found")
#endif
            return false
        }
        
        // Find the mock tab to move
        guard let mockTab = findMockTab(by: draggedTab.id) else {
#if DEBUG
            print("❌ Could not find mock tab with ID: \(draggedTab.id)")
#endif
            return false
        }
        
        // Remove from source
        removeMockTab(mockTab)
        
        // Add to destination
        insertMockTab(mockTab, toContainer: toContainer, atIndex: atIndex)
        
        // End the drag
        _ = dragManager.endDrag(commit: true)
        
#if DEBUG
        print("✅ Successfully moved \(mockTab.name) to \(toContainer) at index \(atIndex)")
#endif
        return true
    }
    
    private func findMockTab(by id: UUID) -> MockTab? {
        // Search in all containers
        if let tab = tabManager.globalPinnedTabs.first(where: { $0.id == id }) { return tab }
        
        for (_, tabs) in tabManager.spacePinnedTabs {
            if let tab = tabs.first(where: { $0.id == id }) { return tab }
        }
        
        for (_, tabs) in tabManager.regularTabs {
            if let tab = tabs.first(where: { $0.id == id }) { return tab }
        }
        
        return nil
    }
    
    private func removeMockTab(_ tab: MockTab) {
        // Remove from global pinned
        tabManager.globalPinnedTabs.removeAll { $0.id == tab.id }
        
        // Remove from space pinned
        for spaceId in tabManager.spacePinnedTabs.keys {
            tabManager.spacePinnedTabs[spaceId]?.removeAll { $0.id == tab.id }
        }
        
        // Remove from regular tabs
        for spaceId in tabManager.regularTabs.keys {
            tabManager.regularTabs[spaceId]?.removeAll { $0.id == tab.id }
        }
    }
    
    private func insertMockTab(_ tab: MockTab, toContainer: TabDragManager.DragContainer, atIndex: Int) {
        switch toContainer {
        case .essentials:
            let clampedIndex = min(max(atIndex, 0), tabManager.globalPinnedTabs.count)
            tabManager.globalPinnedTabs.insert(tab, at: clampedIndex)
            tab.spaceId = nil
            
        case .spacePinned(let spaceId):
            if tabManager.spacePinnedTabs[spaceId] == nil {
                tabManager.spacePinnedTabs[spaceId] = []
            }
            // Safely access the array with optional chaining instead of force unwrap
            if var spacePinnedArray = tabManager.spacePinnedTabs[spaceId] {
                let clampedIndex = min(max(atIndex, 0), spacePinnedArray.count)
                spacePinnedArray.insert(tab, at: clampedIndex)
                tabManager.spacePinnedTabs[spaceId] = spacePinnedArray
            }
            tab.spaceId = spaceId
            
        case .spaceRegular(let spaceId):
            if tabManager.regularTabs[spaceId] == nil {
                tabManager.regularTabs[spaceId] = []
            }
            // Safely access the array with optional chaining instead of force unwrap
            if var regularTabsArray = tabManager.regularTabs[spaceId] {
                let clampedIndex = min(max(atIndex, 0), regularTabsArray.count)
                regularTabsArray.insert(tab, at: clampedIndex)
                tabManager.regularTabs[spaceId] = regularTabsArray
            }
            tab.spaceId = spaceId
            
        case .none:
#if DEBUG
            print("❌ Invalid drop container")
#endif
        case .folder(_):
            // Handle folder drop container
            break
        }
    }
}

// MARK: - Preview

#Preview {
    DragDropPreview()
        .frame(width: 320, height: 640)
}
