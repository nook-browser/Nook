//
//  SidebarUpdateNotification.swift
//  Nook
//
//  Created by Jonathan Caudill on 27/09/2025.
//

import SwiftUI

struct SidebarUpdateNotification: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(NookSettingsService.self) var settingsManager
    let downloadsMenuVisible: Bool
    @State private var isVisible: Bool = false
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var gradientPhase: Double = 0.0

    private var availability: BrowserManager.UpdateAvailability? {
        if let update = browserManager.updateAvailability {
            return update
        }
        if settingsManager.debugToggleUpdateNotification {
            return BrowserManager.UpdateAvailability(
                version: "9999.0",
                shortVersion: "Preview Build",
                releaseNotesURL: nil,
                isDownloaded: true
            )
        }
        return nil
    }

    private var shouldShowNotification: Bool {
        availability != nil
    }

    private var notificationOffset: CGFloat {
        downloadsMenuVisible ? -80 : 0
    }

    var body: some View {
        if let availability, shouldShowNotification {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("New version of Nook available")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .offset(y: isExpanded ? -25 : 0)
                        .zIndex(2)

                    if isExpanded {
                        Button(action: {
                            installUpdate(wasDownloaded: availability.isDownloaded)
                        }) {
                            Text("Restart and Update")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.green,
                                                    Color.white,
                                                    Color.green,
                                                    Color.white
                                                ]),
                                                startPoint: UnitPoint(x: gradientPhase, y: gradientPhase),
                                                endPoint: UnitPoint(x: gradientPhase + 1.0, y: gradientPhase + 1.0)
                                            )
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                        .zIndex(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                )
                .frame(maxWidth: .infinity)
                .onHover { hovering in
                    isHovering = hovering
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded = hovering
                    }
                }
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? notificationOffset : 50)
            .animation(.easeOut(duration: 0.3), value: isVisible)
            .animation(.easeOut(duration: 0.3), value: notificationOffset)
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .onAppear {
                showNotification()
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    gradientPhase = 1.0
                }
            }
            .onChange(of: shouldShowNotification) { _, newValue in
                if newValue {
                    showNotification()
                } else {
                    hideNotification()
                }
            }
        }
    }

    private func showNotification() {
        isVisible = true
    }

    private func hideNotification() {
        isVisible = false
    }

    private func installUpdate(wasDownloaded: Bool) {
        browserManager.installPendingUpdateIfAvailable()
    }
}
