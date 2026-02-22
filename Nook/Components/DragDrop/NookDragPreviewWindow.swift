//
//  NookDragPreviewWindow.swift
//  Nook
//

import SwiftUI
import AppKit
import Combine

// MARK: - NookDragPreviewWindow

class NookDragPreviewWindow: NSWindow {
    static let previewSize = NSSize(width: 320, height: 160)

    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private weak var manager: NookDragSessionManager?

    @MainActor
    init(manager: NookDragSessionManager) {
        self.manager = manager

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.previewSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NookDragPreviewContent(manager: manager)
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = hosting
        self.hostingView = hosting

        observeManager(manager)
    }

    @MainActor
    private func observeManager(_ manager: NookDragSessionManager) {
        manager.$draggedItem
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] (show: Bool) in
                if show {
                    self?.orderFront(nil)
                } else {
                    self?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        manager.$cursorScreenLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] screenPoint in
                self?.updatePosition(screenPoint: screenPoint)
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updatePosition(screenPoint: NSPoint) {
        guard let manager = manager, manager.isDragging else { return }

        let windowSize = Self.previewSize

        if manager.isSidebarReorder && manager.isCursorInSidebar {
            let sidebarFrame = manager.sidebarScreenFrame
            let centerX = sidebarFrame.midX
            let origin = NSPoint(
                x: centerX - windowSize.width / 2,
                y: screenPoint.y - windowSize.height / 2
            )
            setFrame(NSRect(origin: origin, size: windowSize), display: true)
        } else {
            let origin = NSPoint(
                x: screenPoint.x - windowSize.width / 2,
                y: screenPoint.y - windowSize.height / 2
            )
            setFrame(NSRect(origin: origin, size: windowSize), display: true)
        }
    }
}

// MARK: - Preview Style

private enum NookPreviewStyle: Equatable {
    case tabRow
    case pinnedTile
    case ghost

    var showTitle: Bool {
        switch self {
        case .pinnedTile: return false
        default: return true
        }
    }

    var showGhostTitleBar: Bool { self == .ghost }
}

// MARK: - Preview Content

private struct NookDragPreviewContent: View {
    @ObservedObject var manager: NookDragSessionManager

    private var morphSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.78)
    }

    var body: some View {
        ZStack {
            if manager.draggedItem != nil {
                NookMorphingPreview(
                    tab: manager.draggedTab,
                    title: manager.draggedItem?.title ?? "",
                    style: currentStyle,
                    sidebarWidth: manager.sidebarScreenFrame.width,
                    pinnedConfig: manager.pinnedTabsConfig
                )
                .animation(morphSpring, value: currentStyle)
            }
        }
        .frame(width: NookDragPreviewWindow.previewSize.width, height: NookDragPreviewWindow.previewSize.height)
    }

    private var currentStyle: NookPreviewStyle {
        if manager.isSidebarReorder {
            return manager.isCursorInSidebar ? .tabRow : .ghost
        }

        switch manager.activeZone {
        case .essentials:
            return .pinnedTile
        case .spacePinned, .spaceRegular, .folder:
            return .tabRow
        case nil:
            return .ghost
        }
    }
}

// MARK: - Morphing Preview

private struct NookMorphingPreview: View {
    let tab: Tab?
    let title: String
    let style: NookPreviewStyle
    let sidebarWidth: CGFloat
    let pinnedConfig: PinnedTabsConfiguration

    @Environment(\.colorScheme) var colorScheme

    private let sidebarHorizontalPadding: CGFloat = 16

    private var effectiveWidth: CGFloat {
        switch style {
        case .tabRow:
            if sidebarWidth > 0 {
                return max(120, sidebarWidth - sidebarHorizontalPadding)
            }
            return 200
        case .pinnedTile:
            return pinnedConfig.minWidth
        case .ghost:
            return 160
        }
    }

    private var effectiveHeight: CGFloat {
        switch style {
        case .tabRow: return 36
        case .pinnedTile: return pinnedConfig.height
        case .ghost: return 100
        }
    }

    private var effectiveCornerRadius: CGFloat {
        switch style {
        case .tabRow: return 12
        case .pinnedTile: return pinnedConfig.cornerRadius
        case .ghost: return 10
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .ghost:
            return Color(nsColor: .windowBackgroundColor).opacity(0.95)
        case .pinnedTile:
            return colorScheme == .dark ? AppColors.pinnedTabIdleLight : AppColors.pinnedTabIdleDark
        case .tabRow:
            return Color(nsColor: .controlBackgroundColor).opacity(0.95)
        }
    }

    var body: some View {
        ZStack {
            if style == .pinnedTile {
                pinnedTilePreview
            } else {
                standardPreview
            }
        }
        .shadow(color: .black.opacity(0.25), radius: style == .ghost ? 12 : 8, y: style == .ghost ? 4 : 2)
    }

    private var pinnedTilePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: pinnedConfig.cornerRadius, style: .continuous)
                .fill(backgroundColor)

            if let tab = tab {
                tab.favicon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(height: pinnedConfig.faviconHeight)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: pinnedConfig.faviconHeight, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: pinnedConfig.minWidth, height: pinnedConfig.height)
        .clipShape(RoundedRectangle(cornerRadius: pinnedConfig.cornerRadius, style: .continuous))
    }

    private var standardPreview: some View {
        VStack(spacing: 0) {
            if style.showGhostTitleBar {
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 8, height: 8)
                    Circle().fill(Color.yellow.opacity(0.7)).frame(width: 8, height: 8)
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 8, height: 8)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider().opacity(0.3)
            }

            HStack(spacing: 8) {
                if let tab = tab {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if style.showTitle {
                    Text(title)
                        .font(.system(size: style == .ghost ? 11 : 13, weight: .medium))
                        .foregroundColor(style == .ghost ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if style.showGhostTitleBar {
                Spacer(minLength: 0)
            }
        }
        .frame(width: effectiveWidth, height: effectiveHeight)
        .background(
            RoundedRectangle(cornerRadius: effectiveCornerRadius)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: effectiveCornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
