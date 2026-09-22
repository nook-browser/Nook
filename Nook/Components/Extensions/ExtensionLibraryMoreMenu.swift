// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionLibraryMoreMenu.swift
//  Nook
//

import SwiftUI
import WebKit
import CoreLocation
import NookDesign
import NookSettings
import NookWeb
import NookUI

struct MoreMenuView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let onDismiss: () -> Void

    @State private var cookieCount: Int?
    @State private var hasSiteData: Bool = false
    @State private var confirming: Confirmation?

    /// Clearing is destructive and silent otherwise, so it asks first.
    private enum Confirmation: String, Identifiable {
        case cookies, siteData, everything
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cookies: return "Clear cookies for this site?"
            case .siteData: return "Clear stored data for this site?"
            case .everything: return "Clear all data for this site?"
            }
        }

        var message: String {
            switch self {
            case .cookies: return "You will be signed out of this site."
            case .siteData: return "Caches, databases and local storage for this site are removed."
            case .everything: return "Cookies, caches and stored data for this site are removed, and you will be signed out."
            }
        }
    }

    private var currentHost: String? {
        browserManager.tabs.selectedSession(in: windowState)?.url.host
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MoreMenuItem(
                    icon: "list.bullet.rectangle",
                    iconColor: .orange,
                    label: "Cookies",
                    detail: cookieCount.map { "\($0)" } ?? "...",
                    action: (cookieCount ?? 0) > 0 ? { confirming = .cookies } : nil
                )

                MoreMenuItem(
                    icon: "folder.fill",
                    iconColor: .purple,
                    label: "Site Data",
                    detail: hasSiteData ? "Stored" : "None",
                    action: hasSiteData ? { confirming = .siteData } : nil
                )

                if let host = currentHost, let settings = browserManager.nookSettings {
                    MoreMenuItem(icon: "mic.fill", iconColor: .indigo, label: "Microphone") {
                        SitePermissionPicker(permission: .microphone, host: host, settings: settings)
                    }

                    MoreMenuItem(icon: "video.fill", iconColor: .cyan, label: "Camera") {
                        SitePermissionPicker(permission: .camera, host: host, settings: settings)
                    }
                }

                // Nook-wide, not per site: WebKit exposes no per-origin delegate for either on
                // macOS, so these open the System Settings pane that actually governs them
                // rather than implying this site can be changed here.
                MoreMenuItem(
                    icon: "bell.fill",
                    iconColor: .red,
                    label: "Notifications",
                    detail: "Nook",
                    action: { openSystemSettings("Notifications") }
                )

                MoreMenuItem(
                    icon: "location.fill",
                    iconColor: .blue,
                    label: "Location",
                    detail: locationStatus,
                    action: { openSystemSettings("Privacy_LocationServices") }
                )

                Divider().opacity(0.15).padding(.horizontal, 10).padding(.vertical, 4)

                Button {
                    confirming = .everything
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(.red.opacity(0.08))
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                        Text("Clear All Site Data")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.red.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.clear)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(currentHost == nil)
            }
            .padding(6)
        }
        .frame(width: 260)
        .onAppear { loadSiteInfo() }
        .confirmationDialog(
            confirming?.title ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { target in
            Button("Clear", role: .destructive) { perform(target) }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { target in
            Text(target.message)
        }
    }

    private func loadSiteInfo() {
        guard let host = currentHost,
              let webView = browserManager.tabs.selectedSession(in: windowState)?.webView else { return }

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


    /// Nook's own Location Services state, not this site's. Labelled as such in the row.
    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }



    private func perform(_ target: Confirmation) {
        guard let host = currentHost else { return }
        confirming = nil
        Task {
            switch target {
            case .cookies:
                await browserManager.cookieManager.deleteCookiesForDomain(host)
            case .siteData:
                await browserManager.cacheManager.clearCacheForDomain(host)
            case .everything:
                await browserManager.cacheManager.clearCacheForDomain(host)
                await browserManager.cookieManager.deleteCookiesForDomain(host)
            }
            loadSiteInfo()
        }
        if target == .everything { onDismiss() }
    }

    /// Opens the pane that actually governs a Nook-wide permission.
    private func openSystemSettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        if let url { NSWorkspace.shared.open(url) }
        onDismiss()
    }
}

// MARK: - More Menu Item

private struct MoreMenuItem<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let label: String
    var detail: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(iconColor.opacity(0.12))
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))

            Text(label)
                .font(NookDesign.Font.body)

            Spacer()

            if let detail {
                Text(detail)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovering && action != nil ? NookDesign.Surface.fill : Color.clear)
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { isHovering = $0 }
        .onTapGesture { action?() }
    }
}

extension MoreMenuItem where Trailing == EmptyView {
    init(icon: String, iconColor: Color, label: String, detail: String? = nil, action: (() -> Void)? = nil) {
        self.init(icon: icon, iconColor: iconColor, label: label, detail: detail, action: action) { EmptyView() }
    }
}

/// Per-site allow/block/ask for the two capabilities WebKit lets us answer without prompting.
private struct SitePermissionPicker: View {
    let permission: SitePermission
    let host: String
    let settings: NookSettingsService

    @State private var policy: SitePermissionPolicy = .ask

    var body: some View {
        Picker("", selection: $policy) {
            ForEach(SitePermissionPolicy.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .onAppear { policy = settings.permission(permission, for: host) }
        .onChange(of: policy) { _, newValue in
            settings.setPermission(permission, to: newValue, for: host)
        }
    }
}
