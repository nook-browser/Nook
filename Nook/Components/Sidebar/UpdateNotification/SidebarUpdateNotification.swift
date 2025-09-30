//
//  SidebarUpdateNotification.swift
//  Nook
//
//  Created by Jonathan Caudill on 27/09/2025.
//

import SwiftUI

#if RELEASE
import Sparkle
#endif

struct SidebarUpdateNotification: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(SettingsManager.self) var settingsManager
    let downloadsMenuVisible: Bool
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var isVisible: Bool = false
    @State private var buttonHovering: Bool = false
    @State private var gradientPhase: Double = 0.0

    private var updateAvailable: Bool {
        // For now, return false to avoid API issues
        // In production, this would check Sparkle's actual update state
        return false
    }

    private var updateAgeHours: Int {
        #if RELEASE
        guard let lastUpdateCheck = browserManager.appDelegate?.updaterController.updater.lastUpdateCheckDate else {
            return 0
        }
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastUpdateCheck)
        return Int(timeInterval / 3600)
        #else
        return 0
        #endif
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
                // The button that expands/collapses
                VStack(spacing: 0) {
                    // Title text that moves up on hover
                    Text("New version of Nook available")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .offset(y: isExpanded ? -25 : 0)
                        .zIndex(2)

                    // Expandable button that appears below
                    if isExpanded {
                        Button(action: {
                            installUpdate()
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
                        .onHover { hovering in
                            buttonHovering = hovering
                        }
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
            .animation(
                .easeOut(duration: 0.3),
                value: isVisible
            )
            .animation(
                .easeOut(duration: 0.3),
                value: notificationOffset
            )
            .animation(
                .easeInOut(duration: 0.2),
                value: isExpanded
            )
            .animation(
                .easeInOut(duration: 0.3),
                value: buttonHovering
            )
            .onAppear {
                showNotification()
                // Start smooth gradient scrolling
                Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                    gradientPhase += 0.005
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
        isExpanded = false // Start collapsed
    }

    private func hideNotification() {
        isVisible = false
    }

    private func installUpdate() {
        #if RELEASE
        // Use the updater controller to check for and install updates
        browserManager.appDelegate?.updaterController.checkForUpdates(nil)
        #endif
    }
}


