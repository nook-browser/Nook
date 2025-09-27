//
//  SidebarUpdateNotification.swift
//  Nook
//
//  Created by Claude on 27/09/2025.
//

import SwiftUI
import Sparkle

struct SidebarUpdateNotification: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(SettingsManager.self) var settingsManager
    let downloadsMenuVisible: Bool
    @State private var isExpanded: Bool = true
    @State private var isHovering: Bool = false
    @State private var isVisible: Bool = false
    @State private var collapseTimer: Timer?

    private var updateAvailable: Bool {
        // For now, return false to avoid API issues
        // In production, this would check Sparkle's actual update state
        return false
    }

    private var updateAgeHours: Int {
        guard let lastUpdateCheck = browserManager.appDelegate?.updaterController.updater.lastUpdateCheckDate else {
            return 0
        }
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastUpdateCheck)
        return Int(timeInterval / 3600)
    }

    private var shouldShowNotification: Bool {
        settingsManager.debugToggleUpdateNotification || (updateAvailable && updateAgeHours >= 24)
    }

    private var notificationOffset: CGFloat {
        downloadsMenuVisible ? -80 : 0
    }

    var body: some View {
        if shouldShowNotification {
            VStack(spacing: 0) {
                if isExpanded {
                    // Expanded state
                    HStack(spacing: 12) {
                        // Update icon
                        Image(systemName: "arrow.down.circle.dotted")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("A new version of Nook is available!")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)

                            Text("Click to restart and update")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        // Update button
                        Button(action: {
                            installUpdate()
                        }) {
                            Text("Restart and Update")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            isHovering = hovering
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.6))
                    )
                } else {
                    // Collapsed state
                    Button(action: {
                        installUpdate()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.dotted")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)

                            Text("Restart and Update")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.6))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            expandTemporarily()
                        }
                    }
                }
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? notificationOffset : 50)
            .animation(
                .easeOut(duration: 0.3),
                value: isVisible
            )
            .animation(
                .easeOut(duration: 0.3),
                value: notificationOffset
            )
            .onAppear {
                showNotification()
                startCollapseTimer()
            }
            .onChange(of: shouldShowNotification) { _, newValue in
                if newValue {
                    showNotification()
                    startCollapseTimer()
                } else {
                    hideNotification()
                }
            }
            .onDisappear {
                collapseTimer?.invalidate()
            }
        }
    }

    private func showNotification() {
        isVisible = true
        isExpanded = true
    }

    private func hideNotification() {
        isVisible = false
        collapseTimer?.invalidate()
    }

    private func startCollapseTimer() {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { _ in
            isExpanded = false
        }
    }

    private func expandTemporarily() {
        isExpanded = true
        collapseTimer?.invalidate()
        // Don't automatically collapse again - stays expanded until hover ends
    }

    private func installUpdate() {
        // Use the updater controller to check for and install updates
        browserManager.appDelegate?.updaterController.checkForUpdates(nil)
    }
}

struct MockSidebarUpdateNotification: View {
    @State private var forceExpanded = true
    @State private var forceCollapsed = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Expanded State (first minute)")
                .font(.caption)
                .foregroundColor(.secondary)

            SidebarUpdateNotificationPreviewView(isExpanded: true)
                .frame(width: 300)

            Text("Collapsed State (after 1 minute)")
                .font(.caption)
                .foregroundColor(.secondary)

            SidebarUpdateNotificationPreviewView(isExpanded: false)
                .frame(width: 300)

            Text("Positioned above downloads menu")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 100)
                    .overlay(
                        Text("Downloads Menu Area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
                SidebarUpdateNotificationPreviewView(isExpanded: true)
                    .frame(width: 300)
            }
            .frame(height: 150)

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 600)
        .background(Color.gray.opacity(0.1))
    }
}

struct SidebarUpdateNotificationPreviewView: View {
    let isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("A new version of Nook is available!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)

                        Text("Click to restart and update")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button(action: {}) {
                        Text("Restart and Update")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.6))
                )
            } else {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.dotted")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Restart and Update")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.6))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .opacity(1)
    }
}

#Preview {
    MockSidebarUpdateNotification()
}
