// Licensed under GPL-3.0. See LICENSE.
//
//  NookDragPreviewWindow.swift
//  Nook
//

import SwiftUI
import NookDesign
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (show: Bool) in
                if show {
                    // Position at cursor before showing to prevent flash at screen origin
                    if let mgr = self?.manager {
                        self?.alphaValue = 1
                        self?.updatePosition(screenPoint: mgr.cursorScreenLocation)
                    }
                    self?.orderFront(nil)
                } else {
                    self?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        manager.cursorScreenLocationSubject
            .sink { [weak self] screenPoint in
                self?.updatePosition(screenPoint: screenPoint)
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updatePosition(screenPoint: NSPoint) {
        guard let manager = manager, manager.isDragging, !manager.isSettlingDrop else { return }

        let windowSize = Self.previewSize
        let origin = NSPoint(
            x: screenPoint.x - windowSize.width / 2,
            y: screenPoint.y - windowSize.height / 2
        )
        setFrameOrigin(origin)
    }

    @MainActor
    func settle(to settlement: NookDropSettlement, completion: @escaping () -> Void) {
        if settlement.reduceMotion {
            NSAnimationContext.animate(.linear(duration: 0.1), changes: {
                self.animator().alphaValue = 0
            }, completion: completion)
            return
        }

        let frame = NSRect(
            x: settlement.destinationFrame.midX - Self.previewSize.width / 2,
            y: settlement.destinationFrame.midY - Self.previewSize.height / 2,
            width: Self.previewSize.width,
            height: Self.previewSize.height
        )
        NSAnimationContext.animate(.easeOut(duration: 0.16), changes: {
            self.animator().setFrame(frame, display: true)
        }, completion: completion)
    }
}

// MARK: - Preview Style

private enum NookPreviewStyle: Equatable {
    case tabRow
    case pinnedTile
    case ghost
}

// MARK: - Preview Content

private struct NookDragPreviewContent: View {
    @ObservedObject var manager: NookDragSessionManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var morphSpring: Animation {
        NookDesign.Motion.spring
    }

    var body: some View {
        ZStack {
            if manager.draggedItem != nil {
                NookMorphingPreview(
                    icon: manager.draggedIcon,
                    title: manager.draggedItem?.title ?? "",
                    style: currentStyle,
                    sidebarWidth: manager.sidebarScreenFrame.width,
                    folderDepth: currentStyle == .tabRow && manager.dropPosition != nil ? manager.dropDepth : 0
                )
                .animation(accessibilityReduceMotion ? nil : morphSpring, value: currentStyle)
                .animation(accessibilityReduceMotion ? nil : morphSpring, value: manager.dropDepth)
            }
        }
        .frame(width: NookDragPreviewWindow.previewSize.width, height: NookDragPreviewWindow.previewSize.height)
    }

    /// Tile over the favorites grid, row anywhere else over the sidebar (including gaps between
    /// drop zones), and the window-shaped ghost only once the cursor leaves the sidebar.
    private var currentStyle: NookPreviewStyle {
        if let settlement = manager.dropSettlement, !settlement.reduceMotion {
            switch settlement.previewStyle {
            case .tabRow: return .tabRow
            case .pinnedTile: return .pinnedTile
            }
        }
        switch manager.activeZone {
        case .favorites:
            return .pinnedTile
        case .section, .target:
            return .tabRow
        case nil:
            return manager.isCursorInSidebar && !manager.isOutsideWindow ? .tabRow : .ghost
        }
    }
}

// MARK: - Morphing Preview

private struct NookMorphingPreview: View {
    let icon: Image?
    let title: String
    let style: NookPreviewStyle
    let sidebarWidth: CGFloat
    /// Folder levels the drop lands inside. Inside a folder the row narrows from the leading
    /// edge so the folder shows beside it, a little more for each deeper level.
    let folderDepth: Int

    private let sidebarHorizontalPadding: CGFloat = 16
    private let insideFolderWidthFraction: CGFloat = 0.55
    private let perLevelWidthFraction: CGFloat = 0.08
    private let minimumWidthFraction: CGFloat = 0.3

    private var effectiveWidth: CGFloat {
        switch style {
        case .tabRow:
            if sidebarWidth > 0 {
                return max(120, sidebarWidth - sidebarHorizontalPadding)
            }
            return 200
        case .pinnedTile:
            return NookDesign.Size.essentialsTile
        case .ghost:
            return 160
        }
    }

    private var effectiveHeight: CGFloat {
        switch style {
        case .tabRow: return 36
        case .pinnedTile: return NookDesign.Size.essentialsTile
        case .ghost: return 100
        }
    }

    private var effectiveCornerRadius: CGFloat {
        switch style {
        case .tabRow: return NookDesign.Radius.lg
        case .pinnedTile: return NookDesign.Radius.lg
        case .ghost: return NookDesign.Radius.md
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .ghost:
            return Color(nsColor: .windowBackgroundColor).opacity(0.95)
        case .pinnedTile:
            return NookDesign.Surface.fill
        case .tabRow:
            return Color(nsColor: .controlBackgroundColor).opacity(0.95)
        }
    }

    var body: some View {
        NookDesign.Radius.shape(effectiveCornerRadius)
            .fill(backgroundColor)
            .overlay {
                VStack(spacing: 0) {
                    ghostTitleBar
                        .frame(height: style == .ghost ? 25 : 0)
                        .opacity(style == .ghost ? 1 : 0)
                        .clipped()

                    HStack(spacing: style == .pinnedTile ? 0 : 8) {
                        previewIcon
                            .frame(width: iconSize, height: iconSize)

                        Text(title)
                            .font(style == .ghost ? NookDesign.Font.caption : NookDesign.Font.body)
                            .foregroundStyle(style == .ghost ? .secondary : .primary)
                            .lineLimit(1)
                            .frame(width: style == .pinnedTile ? 0 : max(0, rowWidth - 52), alignment: .leading)
                            .opacity(style == .pinnedTile ? 0 : 1)
                            .clipped()
                    }
                    .padding(.horizontal, style == .pinnedTile ? 0 : 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .pinnedTile ? .center : .leading)
                }
            }
            .overlay {
                NookDesign.Radius.shape(effectiveCornerRadius)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    .opacity(style == .pinnedTile ? 0 : 1)
            }
            .frame(width: rowWidth, height: effectiveHeight)
            // Preserve the full row's trailing edge when showing a folder destination.
            .offset(x: (effectiveWidth - rowWidth) / 2)
            .frame(width: effectiveWidth, height: effectiveHeight)
            .nookElevation(.floating)
    }

    private var iconSize: CGFloat {
        style == .pinnedTile ? NookDesign.Size.essentialsFavicon : 16
    }

    @ViewBuilder
    private var previewIcon: some View {
        if let icon {
            icon
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
        } else {
            Image(systemName: "globe")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var ghostTitleBar: some View {
        VStack(spacing: 0) {
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
    }

    private var rowWidth: CGFloat {
        guard folderDepth > 0 else { return effectiveWidth }
        let fraction = insideFolderWidthFraction - CGFloat(folderDepth - 1) * perLevelWidthFraction
        return effectiveWidth * max(minimumWidthFraction, fraction)
    }
}
