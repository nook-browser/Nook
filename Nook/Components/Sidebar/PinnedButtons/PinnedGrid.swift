//
//      PinnedGrid.swift
//      Nook
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import UniformTypeIdentifiers

struct PinnedGrid: View {
    let width: CGFloat
    let profileId: UUID?
    let minButtonWidth: CGFloat = 50
    let itemSpacing: CGFloat = 8
    let rowSpacing: CGFloat = 6
    let maxColumns: Int = 3

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var draggedItem: UUID? = nil

    init(width: CGFloat, profileId: UUID? = nil) {
        self.width = width
        self.profileId = profileId
    }

    var body: some View {
        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
        let items: [Tab] = effectiveProfileId != nil
            ? browserManager.tabManager.essentialTabs(for: effectiveProfileId)
            : []
        let colsCount: Int = columnCount(for: width, itemCount: items.count)
        let columns: [GridItem] = makeColumns(count: colsCount)
        // Ora-style DnD: no geometry/boundary computation

        let shouldAnimate = (browserManager.activeWindowState?.id == windowState.id) && !browserManager.isTransitioningProfile

        // For embedded use, return proper sized container even when empty to support transitions
        if items.isEmpty {
            return AnyView(
                Color.clear
                    .frame(height: 44)
                    .onDrop(
                        of: [.text],
                        delegate: SidebarSectionDropDelegateSimple(
                            itemsCount: { 0 },
                            draggedItem: $draggedItem,
                            targetSection: .essentials,
                            tabManager: browserManager.tabManager
                        )
                    )
            )
        }

        return AnyView(ZStack { // Container to support transitions
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    LazyVGrid(columns: columns, alignment: .center, spacing: rowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { _, tab in
                            let isActive: Bool = (browserManager.currentTab(for: windowState)?.id == tab.id)
                            let title: String = safeTitle(tab)

                            PinnedTile(
                                title: title,
                                urlString: tab.url.absoluteString,
                                icon: tab.favicon,
                                isActive: isActive,
                                onActivate: { browserManager.selectTab(tab, in: windowState) },
                                onClose: { browserManager.tabManager.removeTab(tab.id) },
                                onRemovePin: { browserManager.tabManager.unpinTab(tab) },
                                onSplitRight: { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) },
                                onSplitLeft: { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) }
                            )
                            .onTabDrag(tab.id, draggedItem: $draggedItem)
                            .opacity(draggedItem == tab.id ? 0.0 : 1.0)
                            .onDrop(
                                of: [.text],
                                delegate: SidebarTabDropDelegateSimple(
                                    item: tab,
                                    draggedItem: $draggedItem,
                                    targetSection: .essentials,
                                    tabManager: browserManager.tabManager
                                )
                            )
                        }
                    }
                    // Section-level drop for empty grid or background
                    .onDrop(
                        of: [.text],
                        delegate: SidebarSectionDropDelegateSimple(
                            itemsCount: { items.count },
                            draggedItem: $draggedItem,
                            targetSection: .essentials,
                            tabManager: browserManager.tabManager
                        )
                    )
                }
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
            }
            // Natural updates; avoid cross-profile transition artifacts
        }
        .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: colsCount)
        .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: items.count)
        .allowsHitTesting(!browserManager.isTransitioningProfile)
        )
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * minButtonWidth + CGFloat(cols - 1) * itemSpacing
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: minButtonWidth),
                spacing: itemSpacing,
                alignment: .center
            ),
            count: count
        )
    }

    // no boundary math needed
}

private struct PinnedTile: View {
    let title: String
    let urlString: String
    let icon: Image
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onRemovePin: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void

    var body: some View {
        PinnedTabView(
            tabName: title,
            tabURL: urlString,
            tabIcon: icon,
            isActive: isActive,
            action: onActivate
        )
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button(action: onSplitRight) {
                Label("Open in Split (Right)", systemImage: "rectangle.split.2x1")
            }
            Button(action: onSplitLeft) {
                Label("Open in Split (Left)", systemImage: "rectangle.split.2x1")
            }
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("Close tab", systemImage: "xmark")
            }
            Button(action: onRemovePin) {
                Label("Remove pinned tab", systemImage: "pin.slash")
            }
        }
    }
}

// MARK: - Preference Keys

// no-op
