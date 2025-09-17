//
//  SpacesList.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesList: View {
    @EnvironmentObject var browserManager: BrowserManager
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

    var body: some View {
        HStack(spacing: shouldUseCompact ? 4 : 8) {
            ForEach(browserManager.tabManager.spaces, id: \.id) { space in
                let isActive = browserManager.tabManager.currentSpace?.id == space.id
                SpacesListItem(space: space, isActive: isActive, compact: shouldUseCompact)
                    .id(space.id)
            }
        }
    }
}
