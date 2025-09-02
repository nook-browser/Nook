//
//  WindowView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack {
            // Gradient background for the current space (bottom-most layer)
            SpaceGradientBackgroundView()

            // Attach background context menu to the window background layer
            WindowBackgroundView()
                .contextMenu {
                    Button("Customize Space Gradient...") {
                        browserManager.showGradientEditor()
                    }
                    .disabled(browserManager.tabManager.currentSpace == nil)
                }

            HStack(spacing: 0) {
                DragEnabledSidebarView()
                if browserManager.isSidebarVisible {
                    SidebarResizeView()
                }
                VStack(spacing: 0) {
                    WebsiteLoadingIndicator()

                    WebsiteView()

                }
            }
            // Keep primary content interactive; background menu only triggers on empty areas
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            // Mini command palette anchored exactly to URL bar's top-left
            MiniCommandPaletteOverlay()

            CommandPaletteView()
            DialogView()
            
            // Working insertion line overlay
            InsertionLineView(dragManager: TabDragManager.shared)

            // Profile switch toast overlay
            if browserManager.isShowingProfileSwitchToast, let toast = browserManager.profileSwitchToast {
                ProfileSwitchToastView(toast: toast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.isShowingProfileSwitchToast)
                    .onTapGesture { browserManager.hideProfileSwitchToast() }
            }
        }
        // Named coordinate space for geometry preferences
        .coordinateSpace(name: "WindowSpace")
        // Keep BrowserManager aware of URL bar frame in window space
        .onPreferenceChange(URLBarFramePreferenceKey.self) { frame in
            browserManager.urlBarFrame = frame
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.gradientColorManager)
    }

}

// MARK: - Profile Switch Toast View
private struct ProfileSwitchToastView: View {
    @EnvironmentObject var browserManager: BrowserManager
    let toast: BrowserManager.ProfileSwitchToast

    private func iconView(for icon: String) -> some View {
        Group {
            if isEmoji(icon) {
                Text(icon)
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
        }
        .foregroundStyle(.primary)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        HStack(spacing: 10) {
            // From -> To icons
            if let from = toast.fromProfile {
                iconView(for: from.icon)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .offset(x: 12)
                    }
            }
            iconView(for: toast.toProfile.icon)

            VStack(alignment: .leading, spacing: 2) {
                Text("Switched to \(toast.toProfile.name)")
                    .font(.system(size: 13, weight: .semibold))
                Text(DateFormatter.localizedString(from: toast.timestamp, dateStyle: .none, timeStyle: .short))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
            (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
            (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

// MARK: - Mini Command Palette Overlay (above sidebar and webview)
private struct MiniCommandPaletteOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            if browserManager.isMiniCommandPaletteVisible && !browserManager.isCommandPaletteVisible {
                // Click-away hit target
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { browserManager.isMiniCommandPaletteVisible = false }

                // Use reported URL bar frame when reliable; otherwise compute manual fallback
                let barFrame = browserManager.urlBarFrame
                let hasFrame = barFrame.width > 1 && barFrame.height > 1
                let fallbackX: CGFloat = 8 // Window horizontal content padding
                let fallbackY: CGFloat = 8 /* sidebar top padding */ + 30 /* nav bar */ + 8 /* vstack spacing */
                let anchorX = hasFrame ? barFrame.minX : fallbackX
                let anchorY = hasFrame ? barFrame.minY : fallbackY
                // let width = hasFrame ? barFrame.width : browserManager.sidebarWidth

                MiniCommandPaletteView(
                    forcedWidth: 400,
                    forcedCornerRadius: 12
                )
                .offset(x: anchorX, y: anchorY)
                    .zIndex(1)
            }
        }
        .allowsHitTesting(browserManager.isMiniCommandPaletteVisible)
        .zIndex(999) // ensure above web content
    }
}
