//
//  ExtensionLibraryMoreMenu.swift
//  Nook
//

import SwiftUI
import AppKit
import WebKit
import AVFoundation
import CoreLocation

@available(macOS 15.5, *)
@MainActor
final class ExtensionLibraryMoreMenuController {
    private var panel: NSPanel?
    private var localMonitor: Any?

    private let menuWidth: CGFloat = 260

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        anchorFrame: NSRect,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        onDismiss: @escaping () -> Void
    ) {
        let panel = self.panel ?? createPanel()
        self.panel = panel

        let content = MoreMenuView(
            browserManager: browserManager,
            windowState: windowState,
            onDismiss: { [weak self] in
                self?.dismiss()
                onDismiss()
            }
        )

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(visualEffect)
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container

        // Position adjacent to main panel
        let fittingSize = hosting.fittingSize
        let panelSize = CGSize(width: menuWidth, height: fittingSize.height)

        // Try right side of anchor, fall back to left
        var origin = CGPoint(
            x: anchorFrame.maxX + 4,
            y: anchorFrame.maxY - panelSize.height
        )

        if let screen = NSScreen.main, origin.x + panelSize.width > screen.visibleFrame.maxX {
            origin.x = anchorFrame.minX - menuWidth - 4
        }

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installEventMonitor()
    }

    func dismiss() {
        guard let panel = panel, panel.isVisible else { return }
        removeEventMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: menuWidth, height: 300)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func installEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return event }
            if let eventWindow = event.window, eventWindow == panel { return event }
            self.dismiss()
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

// MARK: - More Menu SwiftUI Content

@available(macOS 15.5, *)
private struct MoreMenuView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let onDismiss: () -> Void

    @State private var cookieCount: Int?
    @State private var hasSiteData: Bool = false

    private var currentHost: String? {
        browserManager.currentTab(for: windowState)?.url.host
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MoreMenuItem(
                    icon: "list.bullet.rectangle",
                    iconColor: .orange,
                    label: "Cookies",
                    detail: cookieCount.map { "\($0)" } ?? "..."
                )

                MoreMenuItem(
                    icon: "folder.fill",
                    iconColor: .purple,
                    label: "Site Data",
                    detail: hasSiteData ? "Stored" : "None"
                )

                MoreMenuItem(
                    icon: "bell.fill",
                    iconColor: .red,
                    label: "Notifications",
                    detail: notificationStatus
                )

                MoreMenuItem(
                    icon: "location.fill",
                    iconColor: .blue,
                    label: "Location",
                    detail: locationStatus
                )

                MoreMenuItem(
                    icon: "mic.fill",
                    iconColor: .indigo,
                    label: "Microphone",
                    detail: micStatus
                )

                MoreMenuItem(
                    icon: "video.fill",
                    iconColor: .cyan,
                    label: "Camera",
                    detail: cameraStatus
                )

                Divider().opacity(0.15).padding(.horizontal, 10).padding(.vertical, 4)

                Button {
                    clearAllSiteData()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("Clear All Site Data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(currentHost == nil)
            }
            .padding(6)
        }
        .frame(width: 260)
        .onAppear { loadSiteInfo() }
    }

    private func loadSiteInfo() {
        guard let host = currentHost,
              let tab = browserManager.currentTab(for: windowState),
              let webView = tab.webView else { return }

        // Load cookie count using async API
        let dataStore = webView.configuration.websiteDataStore
        Task {
            let cookies = await dataStore.httpCookieStore.allCookiesAsync()
            self.cookieCount = cookies.filter { $0.domain.contains(host) }.count

            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await dataStore.dataRecords(ofTypes: dataTypes)
            self.hasSiteData = records.contains { $0.displayName.contains(host) }
        }
    }

    private var notificationStatus: String {
        // UNUserNotificationCenter doesn't have a synchronous status check
        // App-level permission is what we can report
        return "Check"
    }

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private var micStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private var cameraStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private func clearAllSiteData() {
        guard let host = currentHost else { return }
        Task {
            await browserManager.cacheManager.clearCacheForDomain(host)
            await browserManager.cookieManager.deleteCookiesForDomain(host)
        }
        onDismiss()
    }
}

// MARK: - More Menu Item

private struct MoreMenuItem: View {
    let icon: String
    let iconColor: Color
    let label: String
    let detail: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(label)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovering ? Color.secondary.opacity(0.07) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHoverTracking { isHovering = $0 }
    }
}
