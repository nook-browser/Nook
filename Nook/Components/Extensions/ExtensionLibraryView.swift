//
//  ExtensionLibraryView.swift
//  Nook
//

import SwiftUI
import AppKit
import WebKit
import os

@available(macOS 15.5, *)
struct ExtensionLibraryView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService
    let onDismiss: () -> Void

    @State private var moreMenuController = ExtensionLibraryMoreMenuController()

    private let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary")

    private var currentTab: Tab? {
        browserManager.currentTab(for: windowState)
    }

    private var currentHost: String? {
        currentTab?.url.host
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Utility Buttons
            utilityButtonsSection

            Divider().opacity(0.15)

            // MARK: - Extensions Grid
            extensionsSection

            Divider().opacity(0.15)

            // MARK: - Site Settings
            siteSettingsSection

            // MARK: - Footer
            footerSection
        }
        .frame(width: 300)
        .background(.clear)
    }

    // MARK: - Utility Buttons

    private var utilityButtonsSection: some View {
        HStack(spacing: 6) {
            CopyButton(icon: "link", label: "Copy Link") {
                guard let url = currentTab?.url.absoluteString else { return false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                return true
            }
            .disabled(currentTab == nil)

            CopyButton(icon: "doc.on.doc", label: "Copy Title") {
                guard let title = currentTab?.name else { return false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(title, forType: .string)
                return true
            }
            .disabled(currentTab == nil)

            MuteButton(tab: currentTab)
        }
        .padding(12)
    }

    // MARK: - Extensions Grid

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTENSIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .tracking(0.4)
                .padding(.horizontal, 4)

            let extensions = browserManager.extensionManager?.installedExtensions.filter { $0.isEnabled } ?? []

            ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(extensions, id: \.id) { ext in
                    ExtensionGridItem(
                        ext: ext,
                        isPinned: settings.pinnedExtensionIDs.contains(ext.id),
                        browserManager: browserManager,
                        windowState: windowState,
                        settings: settings
                    )
                }

                // Add New button
                Button {
                    ExtensionManager.shared.showExtensionInstallDialog()
                } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(.secondary.opacity(0.2))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary.opacity(0.3))
                            }
                        Text("Add New")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
            }
            }
            .frame(maxHeight: 300)
        }
        .padding(12)
    }

    // MARK: - Site Settings

    @State private var contentBlockerEnabled: Bool = true

    private var siteSettingsSection: some View {
        VStack(spacing: 2) {
            // Content Blocker Toggle
            if let host = currentHost {
                SiteSettingRow(
                    icon: "shield.checkered",
                    iconColor: .green,
                    title: "Content Blocker",
                    subtitle: contentBlockerEnabled ? "Enabled" : "Disabled for this site"
                ) {
                    Toggle("", isOn: $contentBlockerEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: contentBlockerEnabled) { _, enabled in
                            // Use currentHost (not captured host) to always reference the active tab
                            guard let activeHost = currentHost else { return }
                            // Skip if the state already matches (e.g. during sync from tab switch)
                            let isAllowed = browserManager.contentBlockerManager.isDomainAllowed(activeHost)
                            guard (!enabled) != isAllowed else { return }
                            browserManager.contentBlockerManager.allowDomain(activeHost, allowed: !enabled)
                        }
                }
                .onAppear {
                    contentBlockerEnabled = !browserManager.contentBlockerManager.isDomainAllowed(host)
                }
                .onChange(of: currentHost) { _, newHost in
                    if let h = newHost {
                        contentBlockerEnabled = !browserManager.contentBlockerManager.isDomainAllowed(h)
                    }
                }
            }

            // Page Zoom
            if currentTab != nil {
                SiteSettingRow(
                    icon: "magnifyingglass",
                    iconColor: .blue,
                    title: "Page Zoom",
                    subtitle: nil
                ) {
                    HStack(spacing: 6) {
                        Button {
                            zoomOut()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)

                        Text("\(browserManager.zoomManager.currentZoomPercentage)%")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36)

                        Button {
                            zoomIn()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: currentTab?.url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(currentHost ?? "No site loaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            Spacer()

            Button {
                // Find the library panel by looking for our visible NSPanel
                if let panelWindow = NSApp.windows.first(where: {
                    $0 is NSPanel && $0.isVisible && $0.level == .floating && $0.styleMask.contains(.nonactivatingPanel)
                }) {
                    moreMenuController.show(
                        anchorFrame: panelWindow.frame,
                        browserManager: browserManager,
                        windowState: windowState,
                        onDismiss: {}
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.08))
    }

    // MARK: - Zoom Helpers

    private func zoomIn() {
        guard let tab = currentTab, let webView = tab.webView else { return }
        browserManager.zoomManager.zoomIn(for: webView, domain: tab.url.host, tabId: tab.id)
    }

    private func zoomOut() {
        guard let tab = currentTab, let webView = tab.webView else { return }
        browserManager.zoomManager.zoomOut(for: webView, domain: tab.url.host, tabId: tab.id)
    }
}

// MARK: - Mute Button (reactive to tab state)

private struct MuteButton: View {
    let tab: Tab?

    @State private var isMuted = false
    @State private var isHovering = false

    var body: some View {
        Button {
            tab?.toggleMute()
            // Update local state immediately for snappy UI
            if tab != nil { isMuted.toggle() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
                Text(isMuted ? "Unmute" : "Mute")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(tab == nil)
        .onHoverTracking { isHovering = $0 }
        .onAppear { isMuted = tab?.isAudioMuted ?? false }
        .onChange(of: tab?.isAudioMuted) { _, newValue in
            isMuted = newValue ?? false
        }
    }
}

// MARK: - Copy Button (with checkmark feedback)

private struct CopyButton: View {
    let icon: String
    let label: String
    let action: () -> Bool  // returns true if copy succeeded

    @State private var isHovering = false
    @State private var showCheckmark = false

    var body: some View {
        Button {
            if action() {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCheckmark = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showCheckmark = false
                    }
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: showCheckmark ? "checkmark" : icon)
                    .font(.system(size: 15))
                    .foregroundStyle(showCheckmark ? .green : .primary)
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
                Text(showCheckmark ? "Copied!" : label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(showCheckmark ? .green : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHoverTracking { isHovering = $0 }
    }
}

// MARK: - Extension Grid Item

@available(macOS 15.5, *)
private struct ExtensionGridItem: View {
    let ext: InstalledExtension
    let isPinned: Bool
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService

    @State private var isHovering = false
    @State private var badgeText: String?

    private var currentTab: Tab? {
        browserManager.currentTab(for: windowState)
    }

    var body: some View {
        Button {
            triggerExtensionAction()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let iconPath = ext.iconPath,
                           let nsImage = NSImage(contentsOfFile: iconPath) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                        } else {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                    if let badge = badgeText, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }

                }

                Text(ext.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 72)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.8))
                        .rotationEffect(.degrees(45))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHoverTracking { isHovering = $0 }
        .onAppear { refreshBadge() }
        .contextMenu {
            if isPinned {
                Button("Unpin from URL Bar") {
                    settings.pinnedExtensionIDs.removeAll { $0 == ext.id }
                }
            } else {
                Button("Pin to URL Bar") {
                    settings.pinnedExtensionIDs.append(ext.id)
                }
            }
        }
        .accessibilityLabel(ext.name)
        .accessibilityHint("Extension. Double-tap to activate.")
        .accessibilityAddTraits(.isButton)
    }

    private func triggerExtensionAction() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else { return }

        if ctx.webExtension.hasBackgroundContent {
            ctx.loadBackgroundContent { error in
                if let error { Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary").error("Background wake failed: \(error.localizedDescription, privacy: .public)") }
            }
        }

        let adapter: ExtensionTabAdapter? = currentTab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
        ctx.performAction(for: adapter)
    }

    private func refreshBadge() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            badgeText = nil
            return
        }
        let adapter: ExtensionTabAdapter? = currentTab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
        badgeText = ctx.action(for: adapter)?.badgeText
    }
}

// MARK: - Site Setting Row

private struct SiteSettingRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @ViewBuilder let control: () -> Control

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            Spacer()

            control()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(isHovering ? Color.secondary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHoverTracking { isHovering = $0 }
    }
}
