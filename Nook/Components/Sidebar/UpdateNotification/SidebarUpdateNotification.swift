//
//  SidebarUpdateNotification.swift
//  Nook
//
//  Created by Jonathan Caudill on 27/09/2025.
//

import SwiftUI

struct SidebarUpdateNotification: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(SettingsManager.self) var settingsManager
    @Environment(\.colorScheme) private var colorScheme
    let downloadsMenuVisible: Bool
    @State private var isVisible: Bool = false

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

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    private var statusText: String {
        guard let availability else { return "" }
        if availability.isDownloaded {
            return "Update downloaded. Restart to apply."
        }
        return "Downloading in the background."
    }

    var body: some View {
        if let availability, shouldShowNotification {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nook \(availability.shortVersion) is ready")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Text(statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(secondaryTextColor)

                HStack(spacing: 10) {
                    Button {
                        installUpdate(wasDownloaded: availability.isDownloaded)
                    } label: {
                        Text("Restart and Update")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(buttonBackgroundColor)
                            )
                    }
                    .buttonStyle(.plain)

                    if let notesURL = availability.releaseNotesURL {
                        Link("Release notes", destination: notesURL)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 12, x: 0, y: 6)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? notificationOffset : 50)
            .animation(.easeOut(duration: 0.3), value: isVisible)
            .animation(.easeOut(duration: 0.3), value: notificationOffset)
            .onAppear(perform: showNotification)
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
        if wasDownloaded {
            browserManager.installPendingUpdateIfAvailable()
        } else {
            browserManager.appDelegate?.updaterController.checkForUpdates(nil)
        }
    }
}
