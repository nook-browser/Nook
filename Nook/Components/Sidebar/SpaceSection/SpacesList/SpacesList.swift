//
//  SpacesList.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesList: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovering: Bool = false

    // Approximate layout math for compacting: each full icon needs ~32pt (24 cell + ~8 spacing)
    // The center area shares space with left/right controls; reserve ~120pt for them.
    private var shouldUseCompact: Bool {
        let count = browserManager.tabManager.spaces.count
        guard count > 0 else { return false }
        let available = max(browserManager.sidebarWidth - 120, 0)
        let needed = CGFloat(count) * 32.0
        return needed > available
    }
    
    // When sidebar is too small to display all spaces, show only 3 dots with faded sides
    private var shouldUseMinimal: Bool {
        let count = browserManager.tabManager.spaces.count
        guard count > 3 else { return false }
        let available = max(browserManager.sidebarWidth - 120, 0)
        let needed = CGFloat(count) * 16.0 // All dots at 16pt each
        return available < needed
    }
    
    private var visibleSpaces: [Space] {
        let allSpaces = browserManager.tabManager.spaces
        guard shouldUseMinimal, let currentSpaceId = windowState.currentSpaceId else {
            return allSpaces
        }
        
        // Find current space index
        guard let currentIndex = allSpaces.firstIndex(where: { $0.id == currentSpaceId }) else {
            return Array(allSpaces.prefix(3))
        }
        
        // Smart carousel: show 2-3 spaces depending on position
        var result: [Space] = []
        let count = allSpaces.count
        
        // Add left space only if not at the beginning
        if currentIndex > 0 {
            result.append(allSpaces[currentIndex - 1])
        }
        
        // Center space (current) - always included
        result.append(allSpaces[currentIndex])
        
        // Add right space only if not at the end
        if currentIndex < count - 1 {
            result.append(allSpaces[currentIndex + 1])
        }
        
        return result
    }

    var body: some View {
        HStack(spacing: shouldUseCompact ? 4 : 8) {
            ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                let isActive = windowState.currentSpaceId == space.id
                let isFaded = shouldUseMinimal && !isActive

                SpacesListItem(space: space, isActive: isActive, compact: shouldUseCompact)
                    .environment(browserManager)
                    .environment(windowState)
                    .id(space.id)
                    .opacity(isFaded ? 0.3 : 1.0)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.3), value: visibleSpaces.map(\.id))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
    }
}
