//
//  SimpleDragDropPreview.swift
//  Pulse
//
//  Simplified drag & drop preview for testing
//

import SwiftUI
import AppKit

struct SimpleDragDropPreview: View {
    @StateObject private var dragManager = TabDragManager()
    @State private var essentialTabs = [
        DragTab(name: "GitHub", icon: "externaldrive.connected.to.line.below"),
        DragTab(name: "Gmail", icon: "envelope"),
        DragTab(name: "Calendar", icon: "calendar")
    ]
    
    @State private var spacePinnedTabs = [
        DragTab(name: "Stack Overflow", icon: "questionmark.circle"),
        DragTab(name: "Docs", icon: "book")
    ]
    
    @State private var regularTabs = [
        DragTab(name: "Claude", icon: "brain"),
        DragTab(name: "OpenAI", icon: "lightbulb"),
        DragTab(name: "Anthropic", icon: "sparkles"),
        DragTab(name: "YouTube", icon: "play.rectangle"),
        DragTab(name: "Netflix", icon: "tv")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🧛 Dragula Test")
                .font(.title2)
                .fontWeight(.bold)
            
            // Essential Tabs Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Essential Tabs")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(essentialTabs.indices, id: \.self) { index in
                        DragTabEssentialView(
                            tab: essentialTabs[index],
                            dragManager: dragManager,
                            container: .essentials,
                            index: index
                        )
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Divider()
            
            // Space Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Development Space")
                    .font(.headline)
                
                // Space Pinned
                if !spacePinnedTabs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pinned in Space")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(spacePinnedTabs.indices, id: \.self) { index in
                            DragTabRowView(
                                tab: spacePinnedTabs[index],
                                dragManager: dragManager,
                                container: .spacePinned(UUID()),
                                index: index
                            )
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                }
                
                // Regular Tabs
                VStack(alignment: .leading, spacing: 4) {
                    Text("Regular Tabs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(regularTabs.indices, id: \.self) { index in
                        DragTabRowView(
                            tab: regularTabs[index],
                            dragManager: dragManager,
                            container: .spaceRegular(UUID()),
                            index: index
                        )
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Debug Panel
            VStack(alignment: .leading, spacing: 2) {
                Text("Debug:")
                    .fontWeight(.bold)
                Text("Dragging: \(dragManager.isDragging)")
                Text("Target: \(dragManager.dropTarget)")
                Text("Index: \(dragManager.insertionIndex)")
                Text("Show Line: \(dragManager.showInsertionLine)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 280, height: 700)
        .overlay(
            // Insertion Line
            Group {
                if dragManager.showInsertionLine {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: dragManager.insertionLineFrame.width, height: 3)
                        .position(
                            x: dragManager.insertionLineFrame.midX,
                            y: dragManager.insertionLineFrame.midY
                        )
                        .animation(.easeInOut(duration: 0.2), value: dragManager.insertionLineFrame)
                        .allowsHitTesting(false)
                }
            }
        )
        .onReceive(dragManager.objectWillChange) { _ in
            // React to drag state changes
        }
    }
}

// MARK: - Simple Tab Model
struct DragTab: Identifiable {
    let id = UUID()
    var name: String
    var icon: String
    
    init(name: String, icon: String) {
        self.name = name
        self.icon = icon
    }
}

// MARK: - Essential Tab View
struct DragTabEssentialView: View {
    let tab: DragTab
    let dragManager: TabDragManager
    let container: TabDragManager.DragContainer
    let index: Int
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    var body: some View {
        Button(action: {
            print("Activated: \(tab.name)")
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: tab.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(dragManager.isDragging && isDragging ? 0.5 : 1.0)
        .scaleEffect(dragManager.isDragging && isDragging ? 0.95 : 1.0)
        .offset(dragOffset)
        .animation(.easeInOut(duration: 0.2), value: dragManager.isDragging)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // Start drag with a dummy tab for preview
                        let dummyTab = Tab(url: URL(string: "https://example.com")!, name: tab.name, favicon: tab.icon)
                        dragManager.startDrag(tab: dummyTab, from: container, at: index)
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    dragOffset = .zero
                    _ = dragManager.endDrag(commit: true)
                }
        )
        .contextMenu {
            Button("Unpin from Essentials") { print("Unpin \(tab.name)") }
        }
    }
}

// MARK: - Row Tab View
struct DragTabRowView: View {
    let tab: DragTab
    let dragManager: TabDragManager
    let container: TabDragManager.DragContainer
    let index: Int
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            print("Activated: \(tab.name)")
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
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
                    Button(action: { print("Close \(tab.name)") }) {
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
        .opacity(dragManager.isDragging && isDragging ? 0.5 : 1.0)
        .scaleEffect(dragManager.isDragging && isDragging ? 0.95 : 1.0)
        .offset(dragOffset)
        .animation(.easeInOut(duration: 0.2), value: dragManager.isDragging)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // Start drag with a dummy tab for preview
                        let dummyTab = Tab(url: URL(string: "https://example.com")!, name: tab.name, favicon: tab.icon)
                        dragManager.startDrag(tab: dummyTab, from: container, at: index)
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    dragOffset = .zero
                    _ = dragManager.endDrag(commit: true)
                }
        )
        .contextMenu {
            Button("Move Up") { print("Move \(tab.name) up") }
            Button("Move Down") { print("Move \(tab.name) down") }
            Divider()
            Button("Pin to Space") { print("Pin \(tab.name) to space") }
            Button("Pin Globally") { print("Pin \(tab.name) globally") }
        }
    }
}

#Preview {
    SimpleDragDropPreview()
}